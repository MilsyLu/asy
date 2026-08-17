const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { getAuth } = require("firebase-admin/auth");

/**
 * Mirrors `users/{uid}.empresaId` into the user's Firebase Auth custom claims.
 *
 * Why this exists: `storage.rules` used to resolve the caller's empresa with a
 * cross-service `firestore.get()`. Uploads under `supportCases/` were denied
 * with `storage/unauthorized` from the day the feature shipped — 23 cases, not
 * one attachment ever stored — while `profile_photos/`, whose rule does not
 * make that call, kept working throughout. Reading the empresa from the token
 * removes the cross-service dependency entirely, and is what Firebase
 * recommends for tenant scoping in rules: no extra read, no extra latency, no
 * second service that has to be reachable for an upload to be allowed.
 *
 * Runs on every write to a user document, but only touches Auth when the value
 * actually differs from the claim already on the account — user docs change
 * often (fcmTokens, lastLogin, streaks) and setting claims on each of those
 * would be pure cost, plus it invalidates nothing useful.
 */
const syncEmpresaClaim = onDocumentWritten("users/{uid}", async (event) => {
  const uid = event.params.uid;
  const after = event.data?.after?.data();

  // Document deleted: the Auth user is usually gone too (deleteUserPermanently),
  // and clearing claims on a non-existent account throws. Nothing to do.
  if (!after) return;

  const empresaId = after.empresaId ?? null;

  try {
    const user = await getAuth().getUser(uid);
    const claims = user.customClaims || {};

    if (claims.empresaId === empresaId) return;

    // setCustomUserClaims REPLACES the whole claim object, so anything already
    // there (set by another feature now or later) has to be carried over.
    await getAuth().setCustomUserClaims(uid, { ...claims, empresaId });
    console.log(`[CLAIMS] empresaId sincronizado para ${uid}: ${empresaId}`);
  } catch (e) {
    // A Firestore user doc can legitimately exist without an Auth account
    // (created moments before, or already deleted) — that is not an error
    // worth failing the trigger over.
    if (e.code === "auth/user-not-found") {
      console.log(`[CLAIMS] sin cuenta de Auth para ${uid}, se omite`);
      return;
    }
    console.error(`[CLAIMS][ERROR] no se pudo sincronizar ${uid}: ${e}`);
  }
});

module.exports = { syncEmpresaClaim };
