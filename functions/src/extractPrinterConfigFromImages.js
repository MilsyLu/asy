const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore } = require("firebase-admin/firestore");
const { buildToolProperties } = require("./printerConfigSchema");

// Overridable without a code change — lets Michel A/B against a cheaper
// model later without redeploying source, just the env var.
const ANTHROPIC_MODEL_ID = process.env.ANTHROPIC_MODEL_ID || "claude-opus-5";
const MAX_IMAGES = 6;
const ALLOWED_MEDIA_TYPES = new Set(["image/png", "image/jpeg", "image/webp"]);

/**
 * Sends 1+ VinApp Print settings screenshots (a separate, unrelated desktop
 * program — see lib/core/constants/printer_config_schema.dart) to Claude's
 * vision + tool-use API and returns whichever fields Claude could
 * confidently read. Never persists the images anywhere — pure request/
 * response, no Storage writes; the images are discarded by the client
 * immediately after this returns.
 *
 * Callable only by a user with `managePrinterConfigs` (or super_admin),
 * checked server-side against their own users/{uid} doc — mirrors
 * deleteUser.js's caller-role check, not a Firestore rules bypass (this
 * function runs with the Admin SDK, which ignores firestore.rules).
 */
const extractPrinterConfigFromImages = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }

  const db = getFirestore();
  const callerSnap = await db.collection("users").doc(callerUid).get();
  if (!callerSnap.exists) {
    throw new HttpsError("permission-denied", "Usuario no encontrado.");
  }
  const role = callerSnap.get("role");
  const permissions = callerSnap.get("permissions") || {};
  const hasAccess =
    role === "super_admin" ||
    (role === "admin_equipo" && permissions.managePrinterConfigs === true);
  if (!hasAccess) {
    throw new HttpsError("permission-denied", "No tienes permiso para usar esta función.");
  }

  const images = request.data?.images;
  if (!Array.isArray(images) || images.length === 0) {
    throw new HttpsError("invalid-argument", "Debes enviar al menos una imagen.");
  }
  if (images.length > MAX_IMAGES) {
    throw new HttpsError("invalid-argument", `Máximo ${MAX_IMAGES} imágenes por solicitud.`);
  }
  for (const img of images) {
    if (!img?.data || typeof img.data !== "string" || !ALLOWED_MEDIA_TYPES.has(img.mediaType)) {
      throw new HttpsError("invalid-argument", "Una o más imágenes tienen un formato inválido.");
    }
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    console.error("[VinAppPrint] ANTHROPIC_API_KEY is not set.");
    throw new HttpsError("failed-precondition", "La extracción por IA no está configurada.");
  }

  const toolProperties = buildToolProperties();
  const content = [
    ...images.map((img) => ({
      type: "image",
      source: { type: "base64", media_type: img.mediaType, data: img.data },
    })),
    {
      type: "text",
      text:
        "Estas son capturas de pantalla (posiblemente parciales o recortadas) de la " +
        "pantalla de configuración de la aplicación de escritorio 'VinApp Print'. " +
        "Extrae únicamente los valores de los campos que puedas leer con claridad en " +
        "estas imágenes. NO adivines ni infieras un valor para un campo que no sea " +
        "visible o legible en ninguna imagen — omite ese campo por completo del " +
        "resultado. Cada imagen puede mostrar solo una parte de la pantalla completa " +
        "(la aplicación original no es responsiva y se corta visualmente).",
    },
  ];

  let response;
  try {
    response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: ANTHROPIC_MODEL_ID,
        max_tokens: 4096,
        tools: [
          {
            name: "record_printer_config_fields",
            description:
              "Registra los valores de configuración de VinApp Print visibles en las imágenes.",
            input_schema: {
              type: "object",
              properties: toolProperties,
              additionalProperties: false,
            },
          },
        ],
        tool_choice: { type: "tool", name: "record_printer_config_fields" },
        messages: [{ role: "user", content }],
      }),
    });
  } catch (e) {
    console.error("[VinAppPrint] Anthropic API request failed:", e);
    throw new HttpsError("internal", "No se pudo contactar al servicio de IA.");
  }

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    console.error(`[VinAppPrint] Anthropic API error ${response.status}: ${body}`);
    throw new HttpsError("internal", "El servicio de IA devolvió un error.");
  }

  const data = await response.json();
  const toolUseBlock = (data.content || []).find((b) => b.type === "tool_use");
  if (!toolUseBlock || !toolUseBlock.input) {
    throw new HttpsError("internal", "La IA no pudo reconocer datos en las imágenes enviadas.");
  }

  // Defensive: only keep known keys, in case the model returns something
  // outside the schema despite the forced tool_choice.
  const knownKeys = new Set(Object.keys(toolProperties));
  const fields = {};
  for (const [k, v] of Object.entries(toolUseBlock.input)) {
    if (knownKeys.has(k)) fields[k] = v;
  }

  console.log(`[VinAppPrint] Extracted ${Object.keys(fields).length} field(s) from ${images.length} image(s) for ${callerUid}`);

  return { fields };
});

module.exports = { extractPrinterConfigFromImages };
