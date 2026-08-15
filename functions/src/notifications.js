const { getMessaging } = require("firebase-admin/messaging");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

/** Deployed web app origin — used to build the "open this task" click link. */
const APP_ORIGIN = "https://chhecu.web.app";

/** Strips null/empty/duplicate entries from a raw `fcmTokens` array. */
function sanitizeTokens(tokens) {
  if (!Array.isArray(tokens)) return [];
  return [...new Set(tokens.filter((t) => typeof t === "string" && t.length > 0))];
}

/**
 * Sprint 7.5.0 Objetivo F — resolves the effective `pushNotificationMode`
 * for a `users/{uid}` doc, migrating virtually (no write, no script) from
 * the booleans it replaces: `pushNotificationsEnabled` (Sprint 7.4.8) and,
 * before that, the admin-only `receiveTaskCreationPush` (Sprint 7.4.7).
 * `false` -> "none", `true` -> "all". Brand-new docs with none of these
 * fields default to "all", matching the old default-enabled behavior.
 *
 * @param {FirebaseFirestore.DocumentSnapshot} userSnap
 * @returns {string}
 */
function resolvePushMode(userSnap) {
  const mode = userSnap.get("pushNotificationMode");
  if (typeof mode === "string" && mode.length > 0) return mode;

  const legacyEnabled = userSnap.get("pushNotificationsEnabled");
  if (typeof legacyEnabled === "boolean") return legacyEnabled ? "all" : "none";

  const legacyReceive = userSnap.get("receiveTaskCreationPush");
  if (typeof legacyReceive === "boolean") return legacyReceive ? "all" : "none";

  return "all";
}

/**
 * Sprint 7.5.0 Objetivo D — the single point of decision for whether a push
 * of a given notification `type` is allowed under a given `mode`. Every
 * Cloud Function that sends a push (`onTaskCreate.js`, `checkReminders.js`,
 * any future one) goes through [sendNotificationToUser] below instead of
 * branching on role/type itself, so this is the only place that logic
 * lives.
 *
 * - "all": every type.
 * - "assigned_only": task_created_assigned + task_reminder only (used by
 *   both roles).
 * - "group_only": task_created_group only (offered to super_admin in the
 *   Settings UI; a worker's own tasks are always "assigned", so this mode
 *   has no special meaning for them beyond the literal type match).
 * - "none": nothing.
 * - anything else (unrecognized/missing): treated as "all", matching the
 *   pre-7.5.0 default-enabled behavior.
 *
 * @param {string} mode
 * @param {string | undefined} type
 * @returns {boolean}
 */
function isPushAllowed(mode, type) {
  switch (mode) {
    case "none":
      return false;
    case "assigned_only":
      return (
        type === "task_created_assigned" ||
        type === "task_reminder" ||
        type === "task_reprogrammed_assigned"
      );
    case "group_only":
      return type === "task_created_group" || type === "task_reprogrammed_group";
    case "all":
    default:
      return true;
  }
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
      caseId: data.caseId || null,
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

    // Sprint 7.5.0 Objetivo D: a single, central mode+type check that every
    // notification (Encargado/Grupo/Admin/Recordatorio, and any future
    // type) goes through here — callers never branch on role/type
    // themselves. The in-app record above already happened either way.
    const mode = resolvePushMode(userSnap);
    if (!isPushAllowed(mode, data.type)) {
      console.log(`[FCM] Push skipped (mode=${mode}, type=${data.type || "n/a"}): ${userId}`);
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

    // Tap-to-open destination. A task takes priority if a message somehow
    // carried both (never happens today). Only added to the FCM payload (not
    // to `data` itself, which recordNotification above already persisted) —
    // the in-app notification-center tap path doesn't need it, it already has
    // taskId/caseId directly.
    let clickUrl = null;
    if (data.taskId) {
      clickUrl = `${APP_ORIGIN}/?openTask=${data.taskId}`;
    } else if (data.caseId) {
      clickUrl = `${APP_ORIGIN}/?openCase=${data.caseId}`;
    }
    const pushData = clickUrl ? { ...data, url: clickUrl } : data;

    const [response] = await Promise.all([
      getMessaging().sendEachForMulticast({
        tokens,
        notification: { title, body },
        data: pushData,
        android: { priority: "high" },
        apns: { payload: { aps: { sound: "default" } } },
        // Without this, Chrome's own auto-display of the `notification`
        // payload (which fires for background tabs independently of the
        // service worker's onBackgroundMessage handler) falls back to a
        // blank/generic icon — the "notification without the logo" the
        // user was seeing alongside the one the service worker shows
        // manually with an icon (web/firebase-messaging-sw.js).
        webpush: {
          notification: {
            icon: "/icons/Icon-192.png",
            badge: "/icons/Icon-192.png",
          },
          // `fcmOptions.link` is the ONLY thing that makes a web push click
          // navigate anywhere. The Firebase SW SDK registers its own
          // `notificationclick` listener when `firebase.messaging()` is
          // called, and that listener starts with
          // `event.stopImmediatePropagation()` — so any handler the app
          // registers afterwards (see web/firebase-messaging-sw.js) never
          // runs at all. The SDK's handler then looks for the destination in
          // `fcmOptions.link` (or `notification.click_action`) and does
          // nothing when both are absent. Sending the URL only in `data.url`,
          // as this function did before, meant every click on a background
          // push was silently a no-op.
          ...(clickUrl ? { fcmOptions: { link: clickUrl } } : {}),
        },
      }),
      recordPromise,
    ]);

    console.log(
      `[FCM_TIMING]\npush_sent\ntaskId=${data.taskId || "n/a"}\nuserId=${userId}\ntimestamp=${Date.now()}`
    );

    console.log(
      `[FCM_DIAG] Multicast completed\n` +
      `  successCount=${response.successCount}\n` +
      `  failureCount=${response.failureCount}\n` +
      `  responses.length=${response.responses.length}\n` +
      `  tokens.length=${tokens.length}`
    );

    const invalidTokens = [];
    response.responses.forEach((result, index) => {
      const _tok = tokens[index] || "";
      const _tokHead = _tok.substring(0, 25);
      const _tokTail = _tok.length > 10 ? _tok.substring(_tok.length - 10) : _tok;
      if (result.success) {
        console.log(
          `[FCM_DIAG] Token[${index}]\n` +
          `  token=${_tokHead}...${_tokTail}\n` +
          `  success=true\n` +
          `  messageId=${result.messageId}`
        );
      } else {
        const _err = result.error;
        console.log(
          `[FCM_DIAG] Token[${index}]\n` +
          `  token=${_tokHead}...${_tokTail}\n` +
          `  success=false\n` +
          `  code=${_err && _err.code}\n` +
          `  message=${_err && _err.message}\n` +
          `  stack=${_err && _err.stack}\n` +
          `  errorType=${_err && _err.constructor && _err.constructor.name}`
        );
      }
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

/**
 * Resolves every admin who should be notified about a task belonging to
 * [groupId], WITHIN [empresaId]: every super_admin of that empresa (org-wide
 * oversight, unchanged since Sprint 7.4.7), plus — for the permissions
 * system — every admin_equipo of that same empresa whose `managedGroupIds`
 * includes that team. `groupId` may be null/empty for legacy/ungrouped
 * tasks, in which case only super_admins are returned, same as before this
 * system existed.
 *
 * Multi-tenant (empresas): [empresaId] is required and always filtered on —
 * without it, this would resolve every super_admin across every tenant in
 * the database, notifying other companies' admins about a task that isn't
 * theirs (this was the actual behavior here before empresas existed, since
 * a task belonged to exactly one deployment back then).
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} empresaId
 * @param {string | null | undefined} groupId
 * @returns {Promise<string[]>} deduped admin user ids.
 */
async function getAdminIdsForTask(db, empresaId, groupId) {
  const queries = [
    db
      .collection("users")
      .where("empresaId", "==", empresaId)
      .where("role", "==", "super_admin")
      .get(),
  ];
  if (groupId) {
    queries.push(
      db
        .collection("users")
        .where("empresaId", "==", empresaId)
        .where("role", "==", "admin_equipo")
        .where("managedGroupIds", "array-contains", groupId)
        .get()
    );
  }
  const snaps = await Promise.all(queries);
  const ids = new Set();
  for (const snap of snaps) {
    for (const doc of snap.docs) ids.add(doc.id);
  }
  return [...ids];
}

/**
 * Resolves every user who should be notified about a Casos de Soporte
 * threshold reminder, WITHIN [empresaId]: every super_admin, plus every
 * admin_equipo who has the `manageSupportCases` permission — the same
 * "encargado + supervisión" shape as [getAdminIdsForTask], but without a
 * groupId dimension, since a support case isn't scoped to one equipo the
 * way a task is (Casos de Soporte is empresa-wide).
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} empresaId
 * @returns {Promise<string[]>} deduped user ids.
 */
async function getSupportCaseSupervisorIds(db, empresaId) {
  const [superSnap, scopedSnap] = await Promise.all([
    db.collection("users").where("empresaId", "==", empresaId).where("role", "==", "super_admin").get(),
    db
      .collection("users")
      .where("empresaId", "==", empresaId)
      .where("role", "==", "admin_equipo")
      .where("permissions.manageSupportCases", "==", true)
      .get(),
  ]);
  const ids = new Set();
  for (const doc of superSnap.docs) ids.add(doc.id);
  for (const doc of scopedSnap.docs) ids.add(doc.id);
  return [...ids];
}

module.exports = {
  sendNotificationToUser,
  sendNotificationToUsers,
  notifyAdminsOfTaskCreated,
  getAdminIdsForTask,
  getSupportCaseSupervisorIds,
};
