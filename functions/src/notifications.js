const { getMessaging } = require("firebase-admin/messaging");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

/**
 * Sends a push notification to every FCM token registered for `userId`.
 * Tokens that Firebase reports as no longer valid are pruned from the
 * user's `fcmTokens` array so they aren't retried on future sends.
 *
 * @param {string} userId Firestore `users/{userId}` document id.
 * @param {{title: string, body: string, data?: Record<string, string>}} message
 */
async function sendNotificationToUser(userId, { title, body, data = {} }) {
  const db = getFirestore();
  const userRef = db.collection("users").doc(userId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) return;

  const tokens = userSnap.get("fcmTokens") || [];
  if (tokens.length === 0) return;

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
      }
    }
  });

  if (invalidTokens.length > 0) {
    await userRef.update({
      fcmTokens: FieldValue.arrayRemove(...invalidTokens),
    });
  }
}

module.exports = { sendNotificationToUser };
