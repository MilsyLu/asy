const crypto = require("crypto");
const sharp = require("sharp");
const { getStorage } = require("firebase-admin/storage");
const { pool } = require("./vinny");

// Una foto usada por tantos productos no es del plato: es el logo o una imagen
// de relleno que el restaurante subió para no dejar el producto vacío.
const MAX_SHARED_USES = 6;
// Por debajo de esto son logos o códigos QR de mesa (en Celena, 200 px y 390 px).
const MIN_PHOTO_SIDE = 400;

async function download(url) {
  const res = await fetch(url, { headers: { "User-Agent": "CheCu-CartaDigital/1.0" } });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return Buffer.from(await res.arrayBuffer());
}

function publicUrl(bucket, path, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
}

/**
 * Descarga las fotos, descarta las de relleno, las reduce a WebP y las sube a
 * Storage en `cartas/<company>/`. Devuelve el menú con `img` (URL pública o
 * null) en lugar de `src`, más portada y logo ya subidos.
 *
 * Las fotos originales pesan hasta 1280 px; un cliente con datos móviles
 * bajaría decenas de MB si la carta las usara tal cual.
 */
async function processImages(company, carta) {
  const bucket = getStorage().bucket();
  const prefix = `cartas/${company}/`;

  const sources = [...new Set(carta.menu.flatMap((c) => c.products.map((p) => p.src)).filter(Boolean))];
  const brandSources = [carta.company.logoSrc, carta.company.coverSrc].filter(Boolean);

  const info = new Map(); // src -> { hash, buffer, width, height }
  await pool([...new Set([...sources, ...brandSources])], 8, async (src) => {
    try {
      const buffer = await download(src);
      const meta = await sharp(buffer).metadata();
      info.set(src, {
        buffer,
        hash: crypto.createHash("md5").update(buffer).digest("hex"),
        width: meta.width || 0,
        height: meta.height || 0,
      });
    } catch (e) {
      console.warn("carta: no se pudo leer la imagen", src, e.message);
    }
  });

  const uses = new Map(); // hash -> cuántos productos la usan
  for (const c of carta.menu) {
    for (const p of c.products) {
      const i = info.get(p.src);
      if (i) uses.set(i.hash, (uses.get(i.hash) || 0) + 1);
    }
  }
  const logoHash = info.get(carta.company.logoSrc)?.hash;
  const isPlaceholder = (i) =>
    i.hash === logoHash ||
    Math.min(i.width, i.height) < MIN_PHOTO_SIDE ||
    (uses.get(i.hash) || 0) >= MAX_SHARED_USES;

  // URL con token de descarga: se ve sin iniciar sesión y sin tocar storage.rules.
  const token = crypto.randomUUID();
  const uploaded = new Map(); // ruta en Storage -> URL pública
  const keep = new Set();
  async function upload(i, name, maxSide) {
    const path = prefix + name;
    if (!uploaded.has(path)) {
      const out = await sharp(i.buffer)
        .rotate()
        .resize(maxSide, maxSide, { fit: "inside", withoutEnlargement: true })
        .webp({ quality: 76 })
        .toBuffer();
      await bucket.file(path).save(out, {
        contentType: "image/webp",
        resumable: false,
        metadata: {
          cacheControl: "public, max-age=31536000, immutable",
          metadata: { firebaseStorageDownloadTokens: token },
        },
      });
      uploaded.set(path, publicUrl(bucket.name, path, token));
    }
    keep.add(path);
    return uploaded.get(path);
  }

  const toUpload = [];
  for (const c of carta.menu) {
    for (const p of c.products) {
      const i = info.get(p.src);
      p.img = null;
      if (i && !isPlaceholder(i)) toUpload.push([p, i]);
    }
  }
  await pool(toUpload, 6, async ([p, i]) => {
    try {
      p.img = await upload(i, i.hash.slice(0, 16) + ".webp", 720);
    } catch (e) {
      console.warn("carta: no se pudo subir la imagen", p.src, e.message);
    }
  });

  const brand = async (src, name, side) => {
    const i = info.get(src);
    if (!i) return null;
    try {
      return await upload(i, `${name}-${i.hash.slice(0, 8)}.webp`, side);
    } catch (e) {
      console.warn("carta: no se pudo subir", name, e.message);
      return null;
    }
  };
  carta.company.logo = await brand(carta.company.logoSrc, "logo", 300);
  carta.company.cover = await brand(carta.company.coverSrc, "portada", 1400);

  // Fotos de una versión anterior de la carta que ya nadie usa.
  const [files] = await bucket.getFiles({ prefix });
  await Promise.all(files.filter((f) => !keep.has(f.name)).map((f) => f.delete().catch(() => {})));

  for (const c of carta.menu) for (const p of c.products) delete p.src;
  delete carta.company.logoSrc;
  delete carta.company.coverSrc;

  const products = carta.menu.reduce((n, c) => n + c.products.length, 0);
  const withPhoto = carta.menu.reduce((n, c) => n + c.products.filter((p) => p.img).length, 0);
  return { products, withPhoto };
}

module.exports = { processImages };
