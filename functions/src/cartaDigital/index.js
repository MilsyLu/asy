const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { companyFromUrl, fetchMenu } = require("./vinny");
const { processImages } = require("./images");
const { renderCarta } = require("./render");

const COLLECTION = "cartasDigitales";
const baseUrl = () => `https://${process.env.GCLOUD_PROJECT}.web.app`;

/**
 * Generador de QR → "Carta digital": recibe el enlace de Vinny de un
 * restaurante, lee su menú una vez y guarda una carta de solo consulta en
 * `cartasDigitales/<company>`. Los precios quedan fijos hasta que alguien la
 * vuelva a generar; el enlace (y por tanto el QR) no cambia entre versiones.
 *
 * `precios`: "domicilio" (por defecto) o "mesa". Son dos cartas distintas
 * del mismo restaurante, cada una con su enlace: `/carta/<company>` y
 * `/carta/<company>-mesa`, porque van en QR distintos (el de la mesa y el
 * de los domicilios).
 *
 * Abierto a cualquier usuario con sesión, igual que el generador de QR.
 */
const generarCartaDigital = onCall(
  { timeoutSeconds: 300, memory: "1GiB" },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
    }
    const company = companyFromUrl(request.data?.url);
    if (!company) {
      throw new HttpsError(
        "invalid-argument",
        "Ese enlace no es de una carta de Vinny. Debe verse así: https://vinny.vinapp.co/?company=nombre"
      );
    }

    const precios = request.data?.precios === "mesa" ? "mesa" : "domicilio";
    const slug = precios === "mesa" ? `${company}-mesa` : company;

    let carta;
    try {
      carta = await fetchMenu(company, precios);
    } catch (e) {
      if (e.message === "NOT_FOUND") {
        throw new HttpsError("not-found", `Vinny no tiene ningún restaurante llamado "${company}".`);
      }
      console.error("carta: falló la lectura de Vinny", company, e);
      throw new HttpsError("unavailable", "No se pudo leer el menú en Vinny. Intenta de nuevo en un momento.");
    }
    if (!carta.menu.length) {
      throw new HttpsError("failed-precondition", "Ese restaurante no tiene productos publicados en Vinny.");
    }

    const { products, withPhoto } = await processImages(slug, carta);
    const generadoEn = new Date().toISOString();

    const ref = getFirestore().collection(COLLECTION).doc(slug);
    // Una carta pertenece a la empresa que la creó primero: si otra la vuelve
    // a generar, se actualiza pero no desaparece de la lista de su dueña.
    const previous = (await ref.get()).data();
    await ref.set({
      ...carta,
      generadoEn,
      generadoPor: request.auth.uid,
      empresaId: previous?.empresaId || request.auth.token?.empresaId || null,
      vinnyUrl: String(request.data.url).trim(),
      precios,
      productos: products,
      conFoto: withPhoto,
    });

    return {
      url: `${baseUrl()}/carta/${slug}`,
      nombre: carta.company.name,
      precios,
      categorias: carta.menu.length,
      productos: products,
      conFoto: withPhoto,
      generadoEn,
    };
  }
);

function requireEmpresa(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }
  const empresaId = request.auth.token?.empresaId;
  if (!empresaId) {
    throw new HttpsError("failed-precondition", "Tu usuario no tiene una empresa asignada.");
  }
  return empresaId;
}

/** Cartas que creó la empresa de quien pregunta, la más reciente primero. */
const listarCartasDigitales = onCall(async (request) => {
  const empresaId = requireEmpresa(request);
  const snap = await getFirestore().collection(COLLECTION)
    .where("empresaId", "==", empresaId)
    .select("company.name", "generadoEn", "productos", "vinnyUrl", "precios")
    .get();
  const bucket = getStorage().bucket();
  const cartas = await Promise.all(snap.docs.map(async (d) => {
    const c = d.data();
    // Lo que pesan sus fotos en Storage: es lo único de una carta que ocupa
    // espacio de verdad (el texto son unos pocos KB).
    const [files] = await bucket.getFiles({ prefix: `cartas/${d.id}/` });
    return {
      slug: d.id,
      nombre: c.company?.name || d.id,
      url: `${baseUrl()}/carta/${d.id}`,
      vinnyUrl: c.vinnyUrl || `https://vinny.vinapp.co/?company=${d.id}`,
      precios: c.precios || "domicilio",
      generadoEn: c.generadoEn || null,
      productos: c.productos || 0,
      bytes: files.reduce((n, f) => n + Number(f.metadata.size || 0), 0),
    };
  }));
  cartas.sort((a, b) => String(b.generadoEn).localeCompare(String(a.generadoEn)));
  return { cartas };
});

/**
 * Borra una carta y sus fotos. Su enlace (y el QR impreso) muestran desde ese
 * momento "Esta carta no existe".
 */
const borrarCartaDigital = onCall(async (request) => {
  const empresaId = requireEmpresa(request);
  const slug = String(request.data?.slug || "").toLowerCase();
  if (!/^[a-z0-9][a-z0-9_-]{0,80}$/.test(slug)) {
    throw new HttpsError("invalid-argument", "Carta inválida.");
  }
  const ref = getFirestore().collection(COLLECTION).doc(slug);
  const snap = await ref.get();
  if (!snap.exists) return { borrada: false };
  if (snap.data().empresaId !== empresaId) {
    throw new HttpsError("permission-denied", "Esta carta es de otra empresa.");
  }
  await ref.delete();
  await getStorage().bucket().deleteFiles({ prefix: `cartas/${slug}/` });
  return { borrada: true };
});

/**
 * Sirve la carta pública en /carta/<company> (firebase.json reescribe esa
 * ruta a esta función). Sin sesión: es lo que abre el cliente al escanear.
 */
const verCarta = onRequest({ invoker: "public", memory: "256MiB" }, async (req, res) => {
  const company = (req.path.split("/").filter(Boolean).pop() || "").toLowerCase();
  const snap = /^[a-z0-9][a-z0-9_-]{0,80}$/.test(company)
    ? await getFirestore().collection(COLLECTION).doc(company).get()
    : null;

  if (!snap?.exists) {
    res.status(404).set("Cache-Control", "no-store").type("html").send(
      `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">` +
      `<title>Carta no encontrada</title><body style="font-family:system-ui,sans-serif;padding:48px 20px;text-align:center;color:#333">` +
      `<h1 style="font-weight:600">Esta carta no existe</h1><p>Revise el código QR o pida la carta a su mesero.</p></body>`
    );
    return;
  }

  // Sin caché: con la anterior (5 minutos en la CDN) "Actualizar precios"
  // parecía no funcionar, porque al abrir la carta enseguida seguía
  // saliendo el precio viejo. Cada visita lee Firestore una vez; las fotos,
  // que son lo pesado, sí se guardan en caché un año (ver images.js).
  res.set("Cache-Control", "no-cache, no-store, must-revalidate");
  res.type("html").send(renderCarta(snap.data()));
});

module.exports = { generarCartaDigital, listarCartasDigitales, borrarCartaDigital, verCarta };
