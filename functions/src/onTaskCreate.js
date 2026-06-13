const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { sendNotificationToUser } = require("./notifications");

/**
 * Notifies the assigned worker as soon as a new task is scheduled for them.
 */
const onTaskCreate = onDocumentCreated("tasks/{taskId}", async (event) => {
  const task = event.data?.data();
  if (!task) return;

  const { assignedUserId, clientName, date, hour } = task;
  if (!assignedUserId) return;

  await sendNotificationToUser(assignedUserId, {
    title: "Nueva tarea asignada",
    body: `${clientName} - ${date} a las ${hour}`,
    data: {
      type: "task_created",
      taskId: event.params.taskId,
      date: date || "",
      hour: hour || "",
    },
  });
});

module.exports = { onTaskCreate };
