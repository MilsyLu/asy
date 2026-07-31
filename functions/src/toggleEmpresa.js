const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

/**
 * Activates or deactivates an empresa (tenant) — Michel's manual "cut off
 * for non-payment" switch. Callable only by a platform owner. Runs as a
 * Cloud Function rather than a direct client write to `empresas/{id}`
 * (which firestore.rules would also permit for a platform owner) so
 * `suspendedAt`/`suspendedReason` are always set atomically and
 * consistently, and so this is the natural place to add future side
 * effects (e.g. revoking every affected user's refresh tokens) without
 * touching security rules again later.
 */
const toggleEmpresa = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }

  const db = getFirestore();
  const ownerSnap = await db.collection("platformOwners").doc(callerUid).get();
  if (!ownerSnap.exists) {
    throw new HttpsError(
      "permission-denied",
      "Solo el propietario de la plataforma puede activar/desactivar empresas."
    );
  }

  const { empresaId, activo, reason } = request.data || {};
  if (!empresaId || typeof empresaId !== "string" || typeof activo !== "boolean") {
    throw new HttpsError("invalid-argument", "Faltan datos.");
  }

  const empresaRef = db.collection("empresas").doc(empresaId);
  const empresaSnap = await empresaRef.get();
  if (!empresaSnap.exists) {
    throw new HttpsError("not-found", "Esa empresa no existe.");
  }

  await empresaRef.update({
    activo,
    suspendedAt: activo ? null : FieldValue.serverTimestamp(),
    suspendedReason: activo ? null : (reason || null),
  });

  console.log(`[Empresas] ${empresaId} set to activo=${activo} by ${callerUid}`);

  return { success: true };
});

module.exports = { toggleEmpresa };
