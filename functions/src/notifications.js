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
    // tokens or this user's push preference. Sprint 7.4.1: kicked off here
    // (not awaited yet) and joined below alongside the FCM send, instead of
    // sequentially blocking it — a slow Firestore write must not delay
    // push delivery.
    const recordPromise = recordNotification(userId, { title, body, data });

    // Sprint 7.4.8 Objetivo A/C/D: a single, central preference check that
    // every notification type goes through (Encargado/Grupo/Admin/
    // Recordatorio all call this function). `pushNotificationsEnabled` is
    // the current field; `receiveTaskCreationPush` is the Sprint 7.4.7
    // admin-only field it replaces, read here only as a fallback for
    // documents written before this migration — neither field is ever
    // written by new code under that legacy name. Only an explicit
    // `false` disables the push; the in-app record above already happened
    // either way.
    const pushEnabled =
      userSnap.get("pushNotificationsEnabled") ??
      userSnap.get("receiveTaskCreationPush") ??
      true;
    if (pushEnabled === false) {
      console.log(`[FCM] Push skipped (preference disabled): ${userId}`);
      await recordPromise;
      return 0;
    }

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
 * in [adminIds] (Sprint 7.4.7 Objetivo D). Sprint 7.4.8: the push-preference
 * check (record always, push only if enabled) now lives centrally in
 * [sendNotificationToUser] and applies uniformly to every notification
 * type, so this is a thin admin-specific alias of [sendNotificationToUsers]
 * — kept as its own named export so the call site in `onTaskCreate.js`
 * stays self-documenting about which audience it's notifying.
 *
 * @param {string[]} adminIds
 * @param {{title: string, body: string, data?: Record<string, string>}} message
 * @returns {Promise<number>} total tokens the push was actually sent to.
 */
async function notifyAdminsOfTaskCreated(adminIds, message) {
  return sendNotificationToUsers(adminIds, message);
}

module.exports = {
  sendNotificationToUser,
  sendNotificationToUsers,
  notifyAdminsOfTaskCreated,
};
