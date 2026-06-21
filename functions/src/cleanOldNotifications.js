const { onSchedule } = require("firebase-functions/v2/scheduler");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

const RETENTION_DAYS = 180;
const BATCH_SIZE = 500;

/**
 * Runs once a day (Sprint 7.4.7 Objetivo G). Manual deletion (Objetivos
 * E/F) only covers users who clean up their own history — this is the
 * backstop so the `notifications` collection doesn't grow unbounded across
 * the whole organization for the majority who never do. 180 days keeps
 * enough history for auditing/troubleshooting without unlimited growth.
 *
 * Loops in batches of [BATCH_SIZE] within a single invocation so a large
 * backlog (the first run after this sprint ships, or a long-idle project)
 * doesn't require multiple days to fully catch up.
 */
const cleanOldNotifications = onSchedule("every 24 hours", async () => {
  const db = getFirestore();
  const cutoff = Timestamp.fromMillis(
    Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000
  );

  let totalRemoved = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await db
      .collection("notifications")
      .where("createdAt", "<", cutoff)
      .limit(BATCH_SIZE)
      .get();

    if (snap.empty) break;

    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    totalRemoved += snap.docs.length;

    if (snap.docs.length < BATCH_SIZE) break;
  }

  console.log(`[NOTIFICATIONS]\ncleanup_removed=${totalRemoved}`);
});

module.exports = { cleanOldNotifications };
