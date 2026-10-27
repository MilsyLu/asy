const fs = require("fs");
const path = require("path");

const TEMPLATE = fs.readFileSync(path.join(__dirname, "carta.html"), "utf8");

const escHtml = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

// Texto negro o blanco sobre el color de la marca, según cuál se lee mejor.
// El color de la marca no se toca.
function textOn(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return (lum + 0.05) / 0.05 > 1.05 / (lum + 0.05) ? "#111111" : "#ffffff";
}

function displayName(name) {
  const s = String(name || "").trim().toLowerCase();
  return s.replace(/(^|\s)(\S)/g, (m, a, b) => a + b.toUpperCase());
}

/** Arma el HTML final de la carta a partir de lo guardado en Firestore. */
function renderCarta(doc) {
  const carta = {
    company: doc.company,
    menu: doc.menu,
    generadoEn: doc.generadoEn,
    precios: doc.precios || "domicilio",
  };
  // `</` dentro del JSON cerraría la etiqueta <script> antes de tiempo.
  const json = JSON.stringify(carta).replace(/</g, "\\u003c");
  const name = escHtml(displayName(doc.company.name));
  const og = doc.company.cover ? `<meta property="og:image" content="${escHtml(doc.company.cover)}">` : "";
  return TEMPLATE
    .replaceAll("__NOMBRE__", name)
    .replace("__OG_IMAGE__", og)
    .replace("__COLOR__", doc.company.color)
    .replace("__ON_COLOR__", textOn(doc.company.color))
    .replace("__DATA__", () => json);
}

module.exports = { renderCarta };
