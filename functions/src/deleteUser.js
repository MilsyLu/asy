const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

/**
 * Permanently deletes a user's Firestore profile and Firebase Auth account
 * (Sprint 7.3.1, "Eliminación permanente segura"). Callable only by
 * super_admin, and only when the target has no task history — re-validated
 * here server-side regardless of what the client already checked, since the
 * client can't be trusted to enforce this on its own.
 *
 * Order matters for atomicity: the Auth account is deleted first. If that
 * fails, the function throws before touching Firestore, so the user's
 * Firestore doc is never left orphaned without a matching Auth account.
 */
const deleteUserPermanently = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }

  const db = getFirestore();
  const callerSnap = await db.collection("users").doc(callerUid).get();
  if (!callerSnap.exists || callerSnap.get("role") !== "super_admin") {
    throw new HttpsError(
      "permission-denied",
      "Solo un administrador puede eliminar usuarios."
    );
  }

  const targetUid = request.data?.uid;
  if (!targetUid || typeof targetUid !== "string") {
    throw new HttpsError("invalid-argument", "Falta el id del usuario a eliminar.");
  }

  const tasksSnap = await db
    .collection("tasks")
    .where("assignedUserId", "==", targetUid)
    .get();

  if (!tasksSnap.empty) {
    const [completedStatusSnap, rescheduledStatusSnap] = await Promise.all([
      db.collection("statuses").where("name", "==", "Completada").limit(1).get(),
      db.collection("statuses").where("name", "==", "Reprogramada").limit(1).get(),
    ]);
    const completedId = completedStatusSnap.empty ? null : completedStatusSnap.docs[0].id;
    const rescheduledId = rescheduledStatusSnap.empty ? null : rescheduledStatusSnap.docs[0].id;

    let completed = 0;
    let rescheduled = 0;
    tasksSnap.forEach((doc) => {
      const statusId = doc.get("statusId");
      if (completedId && statusId === completedId) completed++;
      if (rescheduledId && statusId === rescheduledId) rescheduled++;
    });

    throw new HttpsError(
      "failed-precondition",
      "No es posible eliminar este usuario. Se encontraron registros " +
        `históricos asociados: tareas asignadas: ${tasksSnap.size}, ` +
        `completadas: ${completed}, reprogramadas: ${rescheduled}. ` +
        "Para conservar la integridad de los datos, desactiva el usuario " +
        "en lugar de eliminarlo."
    );
  }

  try {
    await getAuth().deleteUser(targetUid);
  } catch (e) {
    if (e.code !== "auth/user-not-found") {
      console.error(`[Users] Failed to delete Auth account for ${targetUid}: ${e}`);
      throw new HttpsError(
        "internal",
        "No se pudo eliminar la cuenta de autenticación."
      );
    }
  }

  await db.collection("users").doc(targetUid).delete();
  console.log(`[Users] Permanently deleted user ${targetUid}`);

  return { success: true };
});

module.exports = { deleteUserPermanently };
