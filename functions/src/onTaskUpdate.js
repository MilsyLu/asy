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

  const { assignedUserId, clientName, taskTypeId, groupId, hour, date, empresaId, updatedBy } =
    after;
  if (!assignedUserId) return;

  console.log(`[FCM] Task rescheduled: ${taskId}`);

  const db = getFirestore();
  const [taskTypeSnap, assignedUserSnap, groupDoc, updatedBySnap] = await Promise.all([
    taskTypeId ? db.collection("taskTypes").doc(taskTypeId).get() : null,
    db.collection("users").doc(assignedUserId).get(),
    groupId ? db.collection("groups").doc(groupId).get() : null,
    updatedBy ? db.collection("users").doc(updatedBy).get() : null,
  ]);

  const taskTypeName =
    taskTypeSnap && taskTypeSnap.exists ? taskTypeSnap.get("name") || "Tarea" : "Tarea";
  const assignedUserName =
    assignedUserSnap.exists ? assignedUserSnap.get("name") || "Sin nombre" : "Sin nombre";
  const groupName = groupDoc && groupDoc.exists ? groupDoc.get("name") || groupId : groupId;

  // `updatedBy` is absent on tasks last written before the field existed, and
  // on writes with nobody behind them (the Google Sheets bridge). Those keep
  // the original impersonal wording rather than inventing a name, so a
  // notification never credits someone who didn't do it.
  const updatedByName =
    updatedBySnap && updatedBySnap.exists ? updatedBySnap.get("name") || null : null;

  const basePayload = { taskId, groupId: groupId || "", assignedUserId };
  const pending = [];

  // --- Encargado: push personal ---
  pending.push(
    sendNotificationToUser(assignedUserId, {
      title: "🔄 Tarea reprogramada",
      body:
        (updatedByName ? `${updatedByName} reprogramó tu tarea\n` : "") +
        `${taskTypeName}\nCliente: ${clientName}\nNueva fecha: ${date} ${hour}`,
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
            .where("empresaId", "==", empresaId)
            .where("groupIds", "array-contains", groupId)
            .get();

          const memberIds = groupMembersSnap.docs
            .map((doc) => doc.id)
            .filter((id) => id !== assignedUserId);

          if (memberIds.length === 0) return;

          const count = await sendNotificationToUsers(memberIds, {
            title: "🔄 Tarea del grupo reprogramada",
            body:
              `${taskTypeName}\nCliente: ${clientName}\n` +
              `Encargado: ${assignedUserName}\n` +
              (updatedByName ? `Reprogramada por: ${updatedByName}\n` : "") +
              `Nueva fecha: ${date} ${hour}`,
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
        // Same rule as onTaskCreate: skip the assigned worker, who already got
        // the specific "Tarea reprogramada" notification above. Without this
        // filter an admin who is also the encargado got the same reschedule
        // announced twice.
        const adminIds = (await getAdminIdsForTask(db, empresaId, groupId)).filter(
          (id) => id !== assignedUserId
        );
        if (adminIds.length === 0) return;

        const who = updatedByName || "Alguien";
        const body = groupId
          ? `${who} reprogramó una tarea del grupo ${groupName} para ${date} ${hour}.`
          : `${who} reprogramó una tarea para ${date} ${hour}.`;

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
