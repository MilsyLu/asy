const { onSchedule } = require("firebase-functions/v2/scheduler");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { sendNotificationToUser } = require("./notifications");

/**
 * Today's date as a `YYYY-MM-DD` key in the app's local timezone (the same
 * format `task.date` is stored in, built client-side from the device's local
 * calendar day) — comparing against UTC would misjudge "hoy"/"mañana" near
 * the day boundary.
 */
function todayDateKey() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Bogota" }).format(new Date());
}

/** Whole-day difference between two `YYYY-MM-DD` keys (a - b). */
function dayDiff(dateKeyA, dateKeyB) {
  const a = new Date(`${dateKeyA}T00:00:00Z`);
  const b = new Date(`${dateKeyB}T00:00:00Z`);
  return Math.round((a - b) / 86400000);
}

/** `YYYY-MM-DD` -> `DD/MM/YYYY`, for dates that are neither today nor tomorrow. */
function formatDateKeyDisplay(dateKey) {
  const [y, m, d] = dateKey.split("-");
  return `${d}/${m}/${y}`;
}

/**
 * Sprint 7.4.10: relative-day label for `task.date` against the current
 * server date — replaces the previous hardcoded "hoy" literal, which never
 * actually compared anything and was wrong whenever the task wasn't today.
 */
function relativeDayLabel(taskDateKey) {
  const diff = dayDiff(taskDateKey, todayDateKey());
  if (diff === 0) return "hoy";
  if (diff === 1) return "mañana";
  return formatDateKeyDisplay(taskDateKey);
}

/** `"HH:MM"` (24h) -> `"hh:mm a. m./p. m."`, matching the app's own
 * `AppDateUtils.formatTime12h` convention. */
function formatHour12h(hourStr) {
  const parts = (hourStr || "").split(":");
  const hour = parseInt(parts[0], 10);
  const minute = parseInt(parts[1], 10);
  if (Number.isNaN(hour) || Number.isNaN(minute)) return hourStr || "";
  const ampm = hour < 12 ? "a. m." : "p. m.";
  const hour12 = hour % 12 === 0 ? 12 : hour % 12;
  return `${String(hour12).padStart(2, "0")}:${String(minute).padStart(2, "0")} ${ampm}`;
}

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
          const dayLabel = relativeDayLabel(task.date || todayDateKey());
          const hourLabel = formatHour12h(hour);
          const count = await sendNotificationToUser(assignedUserId, {
            title: "Recordatorio de tarea",
            body: `${clientName} - ${dayLabel} a las ${hourLabel}`,
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
