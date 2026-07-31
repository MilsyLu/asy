const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

/**
 * Creates a brand-new empresa (tenant) plus its first admin user. Callable
 * only by a platform owner (see `platformOwners/{uid}` — never by a
 * tenant's own super_admin, no matter how privileged).
 *
 * Must run server-side: a client can never create a Firebase Auth account
 * for someone else (same reason `deleteUserPermanently` in deleteUser.js
 * runs server-side for the opposite operation) — this is how Michel
 * provisions a brand-new customer's first login without them ever
 * self-registering.
 *
 * Order matters for consistency: if creating the Auth account fails after
 * the empresa doc was already written, the orphaned empresa doc is rolled
 * back so a failed attempt never leaves a half-created tenant behind.
 */
const createEmpresa = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }

  const db = getFirestore();
  const ownerSnap = await db.collection("platformOwners").doc(callerUid).get();
  if (!ownerSnap.exists) {
    throw new HttpsError(
      "permission-denied",
      "Solo el propietario de la plataforma puede crear empresas."
    );
  }

  const { empresaName, adminEmail, adminPassword, adminName } = request.data || {};
  if (
    !empresaName || typeof empresaName !== "string" ||
    !adminEmail || typeof adminEmail !== "string" ||
    !adminPassword || typeof adminPassword !== "string" ||
    !adminName || typeof adminName !== "string"
  ) {
    throw new HttpsError("invalid-argument", "Faltan datos para crear la empresa.");
  }

  const empresaRef = await db.collection("empresas").add({
    name: empresaName.trim(),
    activo: true,
    createdAt: FieldValue.serverTimestamp(),
    createdBy: callerUid,
    suspendedAt: null,
    suspendedReason: null,
  });

  let userRecord;
  try {
    userRecord = await getAuth().createUser({
      email: adminEmail.trim(),
      password: adminPassword,
      displayName: adminName.trim(),
    });
  } catch (e) {
    await empresaRef.delete();
    throw new HttpsError(
      "already-exists",
      `No se pudo crear la cuenta del administrador: ${e.message}`
    );
  }

  await db.collection("users").doc(userRecord.uid).set({
    email: adminEmail.trim(),
    name: adminName.trim(),
    role: "super_admin",
    empresaId: empresaRef.id,
    groupId: null,
    managedGroupIds: [],
    permissions: {},
    fcmTokens: [],
    lastLogin: null,
    streakDays: 0,
    maxStreakDays: 0,
    createdAt: FieldValue.serverTimestamp(),
    isActive: true,
  });

  console.log(`[Empresas] Created empresa ${empresaRef.id} (${empresaName}) with admin ${userRecord.uid}`);

  return { empresaId: empresaRef.id, adminUid: userRecord.uid };
});

module.exports = { createEmpresa };
