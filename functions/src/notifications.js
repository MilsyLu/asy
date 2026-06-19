const { getMessaging } = require("firebase-admin/messaging");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

/** Strips null/empty/duplicate entries from a raw `fcmTokens` array. */
function sanitizeTokens(tokens) {
  if (!Array.isArray(tokens)) return [];
  return [...new Set(tokens.filter((t) => typeof t === "string" && t.length > 0))];
}

/**
 * Sends a push notification to every valid FCM token registered for
 * `userId`. Tokens that Firebase reports as no longer valid are pruned from
 * the user's `fcmTokens` array so they aren't retried on future sends.
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

    const tokens = sanitizeTokens(userSnap.get("fcmTokens"));
    if (tokens.length === 0) return 0;

    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data,
      android: { priority: "high" },
      apns: { payload: { aps: { sound: "default" } } },
    });

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
          console.error(`[FCM] Send failed for user ${userId}: ${code || result.error}`);
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
    console.error(`[FCM] sendNotificationToUser failed for ${userId}: ${e}`);
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

module.exports = { sendNotificationToUser, sendNotificationToUsers };
