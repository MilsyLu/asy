const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

/**
 * Lets an `admin_equipo` with the `manageTeams` permission create a brand
 * new team AND become its manager in one atomic step — something the
 * client can never do directly, since `firestore.rules`' `groups` `create`
 * rule is deliberately `isSuperAdmin()`-only (an admin_equipo "never
 * creates/removes teams, even their own"). Running server-side with the
 * Admin SDK sidesteps needing a much more intricate self-service rule (a
 * user granting themselves `managedGroupIds` only for a team they just
 * created) — the permission check below is the only gate, and it's
 * server-side so it can't be bypassed from the client.
 *
 * super_admin keeps using the existing direct Firestore write for team
 * creation (unchanged) — this function is only for the scoped-admin path.
 */
const createTeamAsScopedAdmin = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }

  const db = getFirestore();
  const callerRef = db.collection("users").doc(callerUid);
  const callerSnap = await callerRef.get();
  if (!callerSnap.exists) {
    throw new HttpsError("permission-denied", "Cuenta no encontrada.");
  }
  const caller = callerSnap.data();
  const canCreateTeams =
    caller.role === "admin_equipo" && caller.permissions?.manageTeams === true;
  if (!canCreateTeams) {
    throw new HttpsError(
      "permission-denied",
      "No tienes permiso para crear equipos."
    );
  }
  if (!caller.empresaId) {
    throw new HttpsError("failed-precondition", "Tu cuenta no tiene una empresa asignada.");
  }

  const { name, description } = request.data || {};
  if (!name || typeof name !== "string" || !name.trim()) {
    throw new HttpsError("invalid-argument", "El nombre del equipo es obligatorio.");
  }

  const groupRef = db.collection("groups").doc();
  await db.runTransaction(async (tx) => {
    tx.set(groupRef, {
      name: name.trim(),
      description: typeof description === "string" ? description.trim() : "",
      empresaId: caller.empresaId,
      timeSelectionMode: "catalog",
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.update(callerRef, {
      managedGroupIds: FieldValue.arrayUnion(groupRef.id),
    });
  });

  return { groupId: groupRef.id };
});

module.exports = { createTeamAsScopedAdmin };
