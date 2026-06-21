const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { getFirestore } = require("firebase-admin/firestore");
const {
  sendNotificationToUser,
  sendNotificationToUsers,
  notifyAdminsOfTaskCreated,
} = require("./notifications");

/**
 * Notifies the assigned worker (personal push) and, when the task belongs
 * to a group, the rest of that group (group push, excluding the assigned
 * worker) as soon as a task is created. The creator is never notified about
 * their own action — whether they self-assigned the task or merely belong
 * to the same group (Sprint 7.4.1).
 *
 * Sprint 7.2 — first business notification flow built on the FCM
 * infrastructure from Sprint 7.1. Runs entirely server-side: Flutter never
 * talks to FCM directly, only Firestore.
 *
 * Sprint 7.4.1 — the assigned-user push and the group lookup+push are
 * independent of each other (both only need the task-type/assigned-user
 * names resolved up front), so they now run concurrently via Promise.all
 * instead of one fully completing before the other starts.
 */
const onTaskCreate = onDocumentCreated("tasks/{taskId}", async (event) => {
  const taskId = event.params.taskId;
  const task = event.data?.data();
  if (!task) return;

  console.log(`[FCM] Task created: ${taskId}`);

  // Sprint 7.4.3 Parte 2 — latency measurement only, no behavior change.
  console.log(`[FCM_TIMING]\ntrigger_received\ntaskId=${taskId}\ntimestamp=${Date.now()}`);

  const { assignedUserId, clientName, taskTypeId, groupId, hour, createdBy } = task;
  if (!assignedUserId) return;

  const db = getFirestore();

  const [taskTypeSnap, assignedUserSnap, groupDoc, createdBySnap] = await Promise.all([
    taskTypeId ? db.collection("taskTypes").doc(taskTypeId).get() : null,
    db.collection("users").doc(assignedUserId).get(),
    groupId ? db.collection("groups").doc(groupId).get() : null,
    createdBy ? db.collection("users").doc(createdBy).get() : null,
  ]);

  const taskTypeName =
    taskTypeSnap && taskTypeSnap.exists ? taskTypeSnap.get("name") || "Tarea" : "Tarea";
  const assignedUserName =
    assignedUserSnap.exists ? assignedUserSnap.get("name") || "Sin nombre" : "Sin nombre";
  const groupName = groupDoc && groupDoc.exists ? groupDoc.get("name") || groupId : groupId;
  const createdByName =
    createdBySnap && createdBySnap.exists ? createdBySnap.get("name") || "Alguien" : "Alguien";

  const basePayload = {
    taskId,
    groupId: groupId || "",
    assignedUserId,
  };

  const pending = [];

  // --- Encargado: push personal --- (skipped if the creator assigned the task to themselves)
  if (createdBy && createdBy === assignedUserId) {
    console.log(`[FCM] Creator skipped: ${assignedUserId} (self-assigned task)`);
  } else {
    pending.push(
      sendNotificationToUser(assignedUserId, {
        title: "📋 Nueva tarea asignada",
        body: `${taskTypeName}\nCliente: ${clientName}\nHora: ${hour}`,
        data: { ...basePayload, type: "task_created_assigned" },
      }).then((count) => {
        console.log(`[FCM] Assigned notified: ${assignedUserId}`);
        console.log(`[FCM] Push sent: ${count}`);
      }).catch((e) => {
        console.error(`[FCM][ERROR] Assigned notification failed for ${assignedUserId}: ${e}`);
      })
    );
  }

  // --- Grupo: push grupal, excluyendo al encargado y al creador ---
  if (groupId) {
    pending.push(
      (async () => {
        try {
          const groupMembersSnap = await db
            .collection("users")
            .where("groupId", "==", groupId)
            .get();

          const memberIds = groupMembersSnap.docs
            .map((doc) => doc.id)
            .filter((id) => id !== assignedUserId && id !== createdBy);

          if (memberIds.length === 0) {
            console.log(`[FCM] Group notified: ${groupId} (${groupName}) - no other members`);
            return;
          }

          const count = await sendNotificationToUsers(memberIds, {
            title: "📢 Nueva tarea para el grupo",
            body: `${taskTypeName}\nCliente: ${clientName}\nEncargado: ${assignedUserName}\nHora: ${hour}`,
            data: { ...basePayload, type: "task_created_group" },
          });

          console.log(`[FCM] Group notified: ${groupId} (${groupName})`);
          console.log(`[FCM] Push sent: ${count}`);
        } catch (e) {
          console.error(`[FCM][ERROR] Group notification failed for ${groupId}: ${e}`);
        }
      })()
    );
  }

  // --- Administradores: visibilidad global (Sprint 7.4.7 Objetivo D) ---
  // Every super_admin except the creator — independent of whether they're
  // also the assignedUserId or a group member, since this notification
  // serves a different purpose (org-wide oversight) than the operational
  // "Encargado"/"Grupo" ones above.
  pending.push(
    (async () => {
      try {
        const adminsSnap = await db
          .collection("users")
          .where("role", "==", "super_admin")
          .get();

        const adminIds = adminsSnap.docs
          .map((doc) => doc.id)
          .filter((id) => id !== createdBy);

        if (adminIds.length === 0) return;

        const body = groupId
          ? `${createdByName} creó una nueva tarea para el grupo ${groupName}.`
          : `${createdByName} creó una nueva tarea.`;

        const count = await notifyAdminsOfTaskCreated(adminIds, {
          title: "Nueva tarea creada",
          body,
          data: { ...basePayload, type: "task_created_admin" },
        });

        console.log(`[FCM] Admins notified: ${adminIds.length}`);
        console.log(`[FCM] Push sent: ${count}`);
      } catch (e) {
        console.error(`[FCM][ERROR] Admin notification failed: ${e}`);
      }
    })()
  );

  await Promise.all(pending);
});

module.exports = { onTaskCreate };
