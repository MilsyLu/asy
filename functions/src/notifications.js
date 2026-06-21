const { getMessaging } = require("firebase-admin/messaging");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

/** Strips null/empty/duplicate entries from a raw `fcmTokens` array. */
function sanitizeTokens(tokens) {
  if (!Array.isArray(tokens)) return [];
  return [...new Set(tokens.filter((t) => typeof t === "string" && t.length > 0))];
}

/**
 * Sprint 7.4 — writes a `notifications/{id}` document so the in-app
 * notification center has a durable record of every push, independent of
 * whether a device token exists or the user dismisses the system
 * notification. Never throws: a failed write here must not abort the FCM
 * send itself.
 *
 * @param {string} userId
 * @param {{title: string, body: string, data?: Record<string, string>}} message
 */
async function recordNotification(userId, { title, body, data = {} }) {
  try {
    const db = getFirestore();
    const ref = await db.collection("notifications").add({
      userId,
      type: data.type || "generic",
      title,
      body,
      taskId: data.taskId || null,
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
    });
    console.log(`[FCM] Notification stored: ${ref.id}`);
  } catch (e) {
    console.error(`[FCM][ERROR] recordNotification failed for ${userId}: ${e}`);
  }
}

/**
 * Sends a push notification to every valid FCM token registered for
 * `userId`, and records it in the `notifications` collection (Sprint 7.4)
 * so it survives the user dismissing/missing the system notification.
 * Tokens that Firebase reports as no longer valid are pruned from the
 * user's `fcmTokens` array so they aren't retried on future sends.
 *
 * Never throws — a failed send for one user must not abort a batch (e.g. a
 * whole group) of notifications.
 *
 * @param {string} userId Firestore `users/{userId}` document id.
 * @param {{title: string, body: string, data?: Record<string, string>}} message
 * @returns {Promise<number>} number of tokens the push was actually sent to.
 */
async function sendNotificationToUser(userId, { title, body, data = {} }) {
  try {
    const db = getFirestore();
    const userRef = db.collection("users").doc(userId);
    const userSnap = await userRef.get();
    if (!userSnap.exists) return 0;

    if (userSnap.get("isActive") === false) {
      console.log(`[FCM] Skipped: user ${userId} is inactive`);
      return 0;
    }

    // Recorded regardless of whether a push can be delivered right now —
    // the in-app history is the durable record, independent of device
    // tokens. Sprint 7.4.1: kicked off here (not awaited yet) and joined
    // below alongside the FCM send, instead of sequentially blocking it —
    // a slow Firestore write must not delay push delivery.
    const recordPromise = recordNotification(userId, { title, body, data });

    const tokens = sanitizeTokens(userSnap.get("fcmTokens"));
    if (tokens.length === 0) {
      await recordPromise;
      return 0;
    }

    // Sprint 7.4.3 Parte 2 — latency measurement only, no behavior change.
    console.log(
      `[FCM_TIMING]\nsending_push\ntaskId=${data.taskId || "n/a"}\nuserId=${userId}\ntimestamp=${Date.now()}`
    );

    const [response] = await Promise.all([
      getMessaging().sendEachForMulticast({
        tokens,
        notification: { title, body },
        data,
        android: { priority: "high" },
        apns: { payload: { aps: { sound: "default" } } },
      }),
      recordPromise,
    ]);

    console.log(
      `[FCM_TIMING]\npush_sent\ntaskId=${data.taskId || "n/a"}\nuserId=${userId}\ntimestamp=${Date.now()}`
    );

    const invalidTokens = [];
    response.responses.forEach((result, index) => {
      if (!result.success) {
        const code = result.error && result.error.code;
        if (
          code === "messaging/invalid-registration-token" ||
          code === "messaging/registration-token-not-registered"
        ) {
          invalidTokens.push(tokens[index]);
        } else {
          console.error(`[FCM][ERROR] Send failed for user ${userId}: ${code || result.error}`);
        }
      }
    });

    if (invalidTokens.length > 0) {
      console.log(`[FCM] Invalid token removed/skipped: ${invalidTokens.length} for user ${userId}`);
      await userRef.update({
        fcmTokens: FieldValue.arrayRemove(...invalidTokens),
      });
    }

    return tokens.length - invalidTokens.length;
  } catch (e) {
    console.error(`[FCM][ERROR] sendNotificationToUser failed for ${userId}: ${e}`);
    return 0;
  }
}

/**
 * Sends the same push to several users at once (e.g. every member of a
 * task's group), reusing the per-user token validation/pruning in
 * [sendNotificationToUser]. A failure for one user never affects the others.
 *
 * @param {string[]} userIds
 * @param {{title: string, body: string, data?: Record<string, string>}} message
 * @returns {Promise<number>} total tokens the push was sent to, across all users.
 */
async function sendNotificationToUsers(userIds, message) {
  const counts = await Promise.all(
    userIds.map((id) => sendNotificationToUser(id, message))
  );
  return counts.reduce((sum, n) => sum + n, 0);
}

/**
 * Sends the "task created" global-visibility notification to every admin
 * in [adminIds] (Sprint 7.4.7 Objetivo C/D). The in-app `notifications`
 * record is always written; the FCM push is skipped for admins whose
 * `receiveTaskCreationPush` field is explicitly `false` (defaults to
 * `true` for documents that don't have it yet — the preference is opt-out,
 * not opt-in). A failure for one admin never affects the others.
 *
 * @param {string[]} adminIds
 * @param {{title: string, body: string, data?: Record<string, string>}} message
 * @returns {Promise<number>} total tokens the push was actually sent to.
 */
async function notifyAdminsOfTaskCreated(adminIds, message) {
  const db = getFirestore();
  let pushCount = 0;

  await Promise.all(
    adminIds.map(async (adminId) => {
      try {
        const snap = await db.collection("users").doc(adminId).get();
        if (!snap.exists || snap.get("isActive") === false) return;

        if (snap.get("receiveTaskCreationPush") === false) {
          await recordNotification(adminId, message);
          return;
        }

        pushCount += await sendNotificationToUser(adminId, message);
      } catch (e) {
        console.error(`[FCM][ERROR] Admin notification failed for ${adminId}: ${e}`);
      }
    })
  );

  return pushCount;
}

module.exports = {
  sendNotificationToUser,
  sendNotificationToUsers,
  notifyAdminsOfTaskCreated,
};
