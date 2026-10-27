/**
 * Lee el menú público de un restaurante en Vinny (vinny.vinapp.co/?company=<uri>).
 *
 * La página de Vinny llega vacía y pide el menú a api.vinny.la al abrirse;
 * aquí se hacen esas mismas consultas de solo lectura, una vez, al generar la
 * carta. La API rechaza (500) cualquier petición que traiga un Origin ajeno,
 * por eso esto corre en el servidor y nunca desde el navegador.
 */

const API = "https://api.vinny.la/api";
const HEADERS = { "User-Agent": "CheCu-CartaDigital/1.0", Accept: "application/json" };

/** Devuelve el `company` de un enlace de Vinny, o null si el enlace no es de Vinny. */
function companyFromUrl(raw) {
  let url;
  try {
    url = new URL(String(raw || "").trim());
  } catch (_) {
    return null;
  }
  if (!/(^|\.)vinny\.vinapp\.co$|(^|\.)vinny\.la$/.test(url.hostname)) return null;
  const company = (url.searchParams.get("company") || "").trim().toLowerCase();
  return /^[a-z0-9][a-z0-9_-]{0,80}$/.test(company) ? company : null;
}

async function getJson(path) {
  const res = await fetch(API + path, { headers: HEADERS });
  if (!res.ok) throw new Error(`Vinny respondió ${res.status} en ${path}`);
  return res.json();
}

/** Corre `fn` sobre cada elemento con como máximo `limit` a la vez. */
async function pool(items, limit, fn) {
  const out = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i], i);
    }
  }));
  return out;
}

/**
 * Precios de mesa: los que ve el mesero en `vinapp.co/<uri>?mesero`.
 *
 * Vinny solo entrega el precio de domicilio. La carta del mesero es la misma
 * consulta pública de VinApp con `mesero=true`, sin PIN, y trae el precio de
 * mesa de cada producto y de cada opción de sus adiciones. También dice qué
 * productos se venden en mesa: los que no aparecen ahí solo son de domicilio.
 *
 * Devuelve { products: Map(id -> {price, old}), options: Map(idDetalle -> precio) }.
 */
async function fetchMesaPrices(companyId) {
  const form = new FormData();
  form.append("id_companie", String(companyId));
  form.append("mesero", "true");
  const res = await fetch("https://back.vinapp.co/api/category/getOptimizedCategoriesV2", {
    method: "POST",
    body: form,
    headers: { "User-Agent": HEADERS["User-Agent"] },
  });
  if (!res.ok) throw new Error(`VinApp respondió ${res.status} con los precios de mesa`);
  const json = await res.json();
  const products = new Map();
  const options = new Map();
  for (const cat of json?.categories || []) {
    for (const p of cat.products || []) {
      products.set(Number(p.id), {
        price: Number(p.value_sale) || 0,
        old: Number(p.old_price) || 0,
      });
      for (const d of p.addition_detail || []) {
        options.set(Number(d.id_product_addition_detail), Number(d.value) || 0);
      }
    }
  }
  return { products, options };
}

/**
 * Trae negocio, categorías y productos. Las imágenes vienen como URL de
 * VinApp; images.js decide cuáles son fotos reales.
 *
 * `precios` es "domicilio" (lo que da Vinny) o "mesa" (los mismos productos
 * con el precio de mesa, quitando los que no se venden en mesa).
 */
async function fetchMenu(company, precios = "domicilio") {
  const resolved = await getJson(`/pwa/resolve/${encodeURIComponent(company)}`);
  const data = resolved?.data;
  const companyId = data?.company?.id;
  const point = data?.points?.[0];
  if (!resolved?.success || !companyId || !point) {
    throw new Error("NOT_FOUND");
  }

  const catsRes = await getJson(`/pwa/categories/${companyId}?point_id=${point.id}`);
  const cats = catsRes?.categories || [];

  const mesa = precios === "mesa" ? await fetchMesaPrices(companyId) : null;

  const menu = await pool(cats, 6, async (cat) => {
    const products = [];
    for (let offset = 0; offset < 2000; offset += 50) {
      const page = await getJson(
        `/pwa/category/${cat.id}/products?company_id=${companyId}&limit=50&offset=${offset}&point_id=${point.id}`
      );
      const batch = page?.products || page?.data || [];
      products.push(...batch);
      if (batch.length < 50) break;
    }
    return {
      name: String(cat.name || "").trim(),
      products: products.map((p) => ({
        id: p.id,
        name: String(p.name || "").trim(),
        desc: String(p.description || "").trim(),
        price: Number(p.value_sale) || 0,
        old: Number(p.old_price) || 0,
        src: p.images || null,
      })),
    };
  });

  if (mesa) {
    for (const cat of menu) {
      cat.products = cat.products
        .filter((p) => mesa.products.has(Number(p.id)))
        .map((p) => ({ ...p, ...mesa.products.get(Number(p.id)) }));
    }
  }

  // Adiciones y combinaciones de cada plato (ej. "Acompañamiento", obligatorio, máximo 1).
  const products = menu.flatMap((cat) => cat.products);
  await pool(products, 8, async (p) => {
    p.groups = [];
    try {
      const res = await getJson(`/menu/product/${p.id}/additions`);
      p.groups = (res?.data?.groups || [])
        .filter((g) => g.options?.length)
        .sort((a, b) => (a.position || 0) - (b.position || 0))
        .map((g) => ({
          name: String(g.name || "").trim(),
          // 139 es "obligatorio" en VinApp; is_required no siempre viene marcado.
          required: g.is_required === true || g.id_tipo === 139,
          max: Number(g.limite) || 0,
          options: g.options.map((o) => ({
            name: String(o.name || "").trim(),
            price: mesa?.options.has(Number(o.id_product_addition_detail))
              ? mesa.options.get(Number(o.id_product_addition_detail))
              : Number(o.price) || 0,
          })),
        }));
    } catch (e) {
      console.warn("carta: no se pudieron leer las adiciones", p.id, e.message);
    }
  });

  // VinApp guarda logo y portada como "jpeg;webp;jp2" relativos a admin.vinapp.co
  const brandImg = (field) => {
    const first = String(field || "").split(";").find((s) => s.endsWith(".webp")) ||
      String(field || "").split(";")[0];
    return first ? new URL(first, "https://admin.vinapp.co").href : null;
  };

  const c = data.company;
  const pagos = [];
  if (c.cash) pagos.push("Efectivo");
  if (c.transfer) pagos.push("Transferencia");
  if (c.dataphone) pagos.push("Datáfono");

  const color = /^#[0-9a-f]{6}$/i.test(data.branding?.colors?.buttons || "")
    ? data.branding.colors.buttons
    : "#2f3b3a";

  return {
    company: {
      name: c.name || company,
      address: point.address || "",
      phone: point.telefono_pedidos || point.phone || "",
      color,
      pagos,
      // El horario de la empresa marca los días cerrados (activo:false); el del
      // punto de venta los omite. Se usa el de la empresa y se descartan los inactivos.
      horarios: (data.horarios || point.horarios || []).filter((h) => h.activo !== false),
      logoSrc: brandImg(data.branding?.logo),
      coverSrc: brandImg(data.branding?.cover),
    },
    menu: menu.filter((cat) => cat.products.length),
  };
}

module.exports = { companyFromUrl, fetchMenu, pool };
