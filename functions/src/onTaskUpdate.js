const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { getFirestore } = require("firebase-admin/firestore");
const {
  sendNotificationToUser,
  sendNotificationToUsers,
  notifyAdminsOfTaskCreated,
  getAdminIdsForTask,
} = require("./notifications");

/**
 * Notifies the assigned worker (personal push), the rest of the group
 * (group push), and every admin whenever a task's scheduled date/hour
 * actually changes — the same three-way structure as `onTaskCreate.js`,
 * mirrored here for reschedules.
 *
 * Fires on ANY write that changes `date`/`hour` on `tasks/{taskId}`,
 * regardless of which client made it — the in-app "Reprogramar" flow
 * (`TaskRepository.rescheduleTask`), the in-app "Editar" flow, or an
 * external integration (e.g. the Google Sheets bridge in
 * `syncTaskFromSheet.js`) writing directly to Firestore. Before this
 * function existed, rescheduling a task never sent a notification from
 * any of those paths — this is a genuinely new notification, not just a
 * port of existing client logic.
 *
 * Editing other fields (observations, client name, etc.) without touching
 * date/hour must not fire this — only a real schedule change does.
 */
const onTaskUpdate = onDocumentUpdated("tasks/{taskId}", async (event) => {
  const taskId = event.params.taskId;
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!before || !after) return;

  const dateChanged = before.date !== after.date;
  const hourChanged = before.hour !== after.hour;
  if (!dateChanged && !hourChanged) return;
  if (after.isDeleted) return;

  const { assignedUserId, clientName, taskTypeId, groupId, hour, date } = after;
  if (!assignedUserId) return;

  console.log(`[FCM] Task rescheduled: ${taskId}`);

  const db = getFirestore();
  const [taskTypeSnap, assignedUserSnap, groupDoc] = await Promise.all([
    taskTypeId ? db.collection("taskTypes").doc(taskTypeId).get() : null,
    db.collection("users").doc(assignedUserId).get(),
    groupId ? db.collection("groups").doc(groupId).get() : null,
  ]);

  const taskTypeName =
    taskTypeSnap && taskTypeSnap.exists ? taskTypeSnap.get("name") || "Tarea" : "Tarea";
  const assignedUserName =
    assignedUserSnap.exists ? assignedUserSnap.get("name") || "Sin nombre" : "Sin nombre";
  const groupName = groupDoc && groupDoc.exists ? groupDoc.get("name") || groupId : groupId;

  const basePayload = { taskId, groupId: groupId || "", assignedUserId };
  const pending = [];

  // --- Encargado: push personal ---
  pending.push(
    sendNotificationToUser(assignedUserId, {
      title: "🔄 Tarea reprogramada",
      body: `${taskTypeName}\nCliente: ${clientName}\nNueva fecha: ${date} ${hour}`,
      data: { ...basePayload, type: "task_reprogrammed_assigned" },
    }).then((count) => {
      console.log(`[FCM] Reschedule (assigned) notified: ${assignedUserId}`);
      console.log(`[FCM] Push sent: ${count}`);
    }).catch((e) => {
      console.error(`[FCM][ERROR] Reschedule (assigned) failed for ${assignedUserId}: ${e}`);
    })
  );

  // --- Grupo: push grupal, excluyendo al encargado ---
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
            .filter((id) => id !== assignedUserId);

          if (memberIds.length === 0) return;

          const count = await sendNotificationToUsers(memberIds, {
            title: "🔄 Tarea del grupo reprogramada",
            body:
              `${taskTypeName}\nCliente: ${clientName}\n` +
              `Encargado: ${assignedUserName}\nNueva fecha: ${date} ${hour}`,
            data: { ...basePayload, type: "task_reprogrammed_group" },
          });

          console.log(`[FCM] Reschedule (group) notified: ${groupId} (${groupName})`);
          console.log(`[FCM] Push sent: ${count}`);
        } catch (e) {
          console.error(`[FCM][ERROR] Reschedule (group) failed for ${groupId}: ${e}`);
        }
      })()
    );
  }

  // --- Administradores: visibilidad global (+ admin_equipo de este equipo) ---
  pending.push(
    (async () => {
      try {
        const adminIds = await getAdminIdsForTask(db, groupId);
        if (adminIds.length === 0) return;

        const body = groupId
          ? `Una tarea del grupo ${groupName} fue reprogramada para ${date} ${hour}.`
          : `Una tarea fue reprogramada para ${date} ${hour}.`;

        const count = await notifyAdminsOfTaskCreated(adminIds, {
          title: "Tarea reprogramada",
          body,
          data: { ...basePayload, type: "task_reprogrammed_admin" },
        });

        console.log(`[FCM] Reschedule (admin) notified: ${adminIds.length}`);
        console.log(`[FCM] Push sent: ${count}`);
      } catch (e) {
        console.error(`[FCM][ERROR] Reschedule (admin) failed: ${e}`);
      }
    })()
  );

  await Promise.all(pending);
});

module.exports = { onTaskUpdate };
