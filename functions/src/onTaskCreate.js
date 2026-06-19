const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { getFirestore } = require("firebase-admin/firestore");
const { sendNotificationToUser, sendNotificationToUsers } = require("./notifications");

/**
 * Notifies the assigned worker (personal push) and, when the task belongs
 * to a group, the rest of that group (group push, excluding the assigned
 * worker) as soon as a task is created.
 *
 * Sprint 7.2 — first business notification flow built on the FCM
 * infrastructure from Sprint 7.1. Runs entirely server-side: Flutter never
 * talks to FCM directly, only Firestore.
 */
const onTaskCreate = onDocumentCreated("tasks/{taskId}", async (event) => {
  const taskId = event.params.taskId;
  const task = event.data?.data();
  if (!task) return;

  console.log(`[FCM] Task created: ${taskId}`);

  const { assignedUserId, clientName, taskTypeId, groupId, hour } = task;
  if (!assignedUserId) return;

  const db = getFirestore();

  const [taskTypeSnap, assignedUserSnap] = await Promise.all([
    taskTypeId ? db.collection("taskTypes").doc(taskTypeId).get() : null,
    db.collection("users").doc(assignedUserId).get(),
  ]);

  const taskTypeName =
    taskTypeSnap && taskTypeSnap.exists ? taskTypeSnap.get("name") || "Tarea" : "Tarea";
  const assignedUserName =
    assignedUserSnap.exists ? assignedUserSnap.get("name") || "Sin nombre" : "Sin nombre";

  const basePayload = {
    taskId,
    groupId: groupId || "",
    assignedUserId,
  };

  // --- Encargado: push personal ---
  const assignedTokensSent = await sendNotificationToUser(assignedUserId, {
    title: "📋 Nueva tarea asignada",
    body: `${taskTypeName}\nCliente: ${clientName}\nHora: ${hour}`,
    data: { ...basePayload, type: "task_created_assigned" },
  });

  console.log(`[FCM] Assigned user notified: ${assignedUserId}`);
  console.log(`[FCM] Tokens sent: ${assignedTokensSent}`);

  if (!groupId) return;

  // --- Grupo: push grupal, excluyendo al encargado para evitar doble aviso ---
  const [groupMembersSnap, groupDoc] = await Promise.all([
    db.collection("users").where("groupId", "==", groupId).get(),
    db.collection("groups").doc(groupId).get(),
  ]);
  const groupName = groupDoc.exists ? groupDoc.get("name") || groupId : groupId;

  const memberIds = groupMembersSnap.docs
    .map((doc) => doc.id)
    .filter((id) => id !== assignedUserId);

  if (memberIds.length === 0) {
    console.log(`[FCM] Group notified: ${groupId} (${groupName}) - no other members`);
    return;
  }

  const groupTokensSent = await sendNotificationToUsers(memberIds, {
    title: "📢 Nueva tarea para el grupo",
    body: `${taskTypeName}\nCliente: ${clientName}\nEncargado: ${assignedUserName}\nHora: ${hour}`,
    data: { ...basePayload, type: "task_created_group" },
  });

  console.log(`[FCM] Group notified: ${groupId} (${groupName})`);
  console.log(`[FCM] Tokens sent: ${groupTokensSent}`);
});

module.exports = { onTaskCreate };
