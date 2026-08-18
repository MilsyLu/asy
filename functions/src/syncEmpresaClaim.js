const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { getAuth } = require("firebase-admin/auth");

/**
 * Keeps two Firebase Auth facts in step with `users/{uid}`:
 *
 *  1. `empresaId` as a custom claim, and
 *  2. `emailVerified`, for accounts an administrator provisioned.
 *
 * ── (1) Why the claim exists ──────────────────────────────────────────────
 * `storage.rules` used to resolve the caller's empresa with a cross-service
 * `firestore.get()`. Uploads under `supportCases/` were denied with
 * `storage/unauthorized` from the day the feature shipped — 23 cases, not one
 * attachment ever stored — while `profile_photos/`, whose rule does not make
 * that call, kept working throughout. Reading the empresa from the token
 * removes the cross-service dependency entirely, and is what Firebase
 * recommends for tenant scoping in rules: no extra read, no extra latency, no
 * second service that has to be reachable for an upload to be allowed.
 *
 * ── (2) Why the account is marked verified ────────────────────────────────
 * Nobody signs up for CheCu: an administrator creates the account with a
 * password (`AuthService.createUser`) and hands the credentials over. Nothing
 * in that flow ever sends a verification email, so every account sat with
 * `emailVerified: false`.
 *
 * That flag is not cosmetic. When somebody signs in with a provider that owns
 * a verified email — the "Continuar con Google" button on the login screen —
 * and an *unverified* password account already holds that address, Firebase
 * treats the password account as untrusted and strips its password credential,
 * on the assumption it was planted by an impersonator. The real user would
 * click Google once and silently lose the password their administrator gave
 * them: it would simply stop working, with no message and nothing in the UI
 * explaining why, and the administrator re-sending the same password would not
 * fix it.
 *
 * Marking the address verified is not a shortcut around that protection — it
 * is the protection being satisfied. The administrator provisioning a
 * corporate address *is* the authority on it, exactly as in any managed
 * workspace. Once verified, Google links onto the existing account instead of
 * displacing it, and both ways in keep working.
 *
 * Runs on every write to a user document, but only touches Auth when a value
 * actually differs from what the account already carries — user docs change
 * often (fcmTokens, lastLogin, streaks) and writing on each of those would be
 * pure cost. `getUser()` is fetched once and serves both checks.
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

    if (claims.empresaId !== empresaId) {
      // setCustomUserClaims REPLACES the whole claim object, so anything already
      // there (set by another feature now or later) has to be carried over.
      await getAuth().setCustomUserClaims(uid, { ...claims, empresaId });
      console.log(`[CLAIMS] empresaId sincronizado para ${uid}: ${empresaId}`);
    }

    if (!user.emailVerified && user.email) {
      await getAuth().updateUser(uid, { emailVerified: true });
      console.log(`[CLAIMS] cuenta marcada como verificada: ${uid}`);
    }
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
