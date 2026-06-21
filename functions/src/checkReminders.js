const { onSchedule } = require("firebase-functions/v2/scheduler");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { sendNotificationToUser } = require("./notifications");

/**
 * Looks up the document id of the status named "Completada", if any.
 * Used to skip sending stale reminders for tasks already finished.
 */
async function getCompletedStatusId(db) {
  const snap = await db
    .collection("statuses")
    .where("name", "==", "Completada")
    .limit(1)
    .get();
  return snap.empty ? null : snap.docs[0].id;
}

/**
 * Runs every minute. Sends a push notification for every task whose
 * `reminderTime` has passed and `reminderSent` is still `false`, then
 * marks it as sent so it isn't repeated.
 */
const checkReminders = onSchedule("every 1 minutes", async () => {
  const db = getFirestore();
  const now = Timestamp.now();
  const completedStatusId = await getCompletedStatusId(db);

  const snap = await db
    .collection("tasks")
    .where("reminderSent", "==", false)
    .where("reminderTime", "<=", now)
    .get();

  if (snap.empty) return;

  await Promise.all(
    snap.docs.map(async (doc) => {
      try {
        const task = doc.data();

        if (completedStatusId && task.statusId === completedStatusId) {
          await doc.ref.update({ reminderSent: true });
          return;
        }

        const { assignedUserId, clientName, hour } = task;
        if (assignedUserId) {
          const count = await sendNotificationToUser(assignedUserId, {
            title: "Recordatorio de tarea",
            body: `${clientName} - hoy a las ${hour}`,
            data: {
              type: "task_reminder",
              taskId: doc.id,
              date: task.date || "",
              hour: hour || "",
            },
          });
          console.log(`[FCM] Reminder notified: ${assignedUserId}`);
          console.log(`[FCM] Push sent: ${count}`);
        }

        await doc.ref.update({ reminderSent: true });
      } catch (e) {
        console.error(`[FCM][ERROR] Reminder processing failed for ${doc.id}: ${e}`);
      }
    })
  );
});

module.exports = { checkReminders };
