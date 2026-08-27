import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Turns on Firebase App Check, which vouches that a request came from the
/// real CheCu and not from a script.
///
/// The security rules already decide *what* a signed-in person may read; they
/// are the defence and they hold. What they cannot do is stop a stranger from
/// trying. Firebase's web configuration is public by design — it ships inside
/// the JavaScript of the site — so anyone can point a script at the database.
/// Every one of those attempts is rejected, and every one of them is a
/// billable read on Michel's account. App Check refuses them before they get
/// that far.
///
/// **Order matters, and getting it wrong locks everybody out.** App Check
/// starts in the console as *unenforced*: the app sends its token, Firebase
/// records whether requests carry a valid one, and nothing is blocked yet.
/// Only once that monitoring shows real traffic passing does enforcement get
/// switched on. Enforcing first would reject every request the moment a key is
/// misconfigured, with no warning and no way in.
abstract final class AppCheckService {
  /// reCAPTCHA v3 site key for the web build, created in the Firebase console
  /// under App Check → Apps → CheCu (web).
  ///
  /// Empty means "not configured yet", and that is a supported state, not an
  /// oversight: this file ships before the key exists so activating it is one
  /// paste rather than a code change, and an empty key skips activation
  /// instead of crashing the app at startup.
  ///
  /// Publishing the site key is expected — it is meant to be readable in the
  /// page. What proves the request is the token reCAPTCHA issues for it, which
  /// cannot be forged from the key alone.
  static const String _recaptchaSiteKey = String.fromEnvironment(
    'APP_CHECK_RECAPTCHA_KEY',
    defaultValue: '',
  );

  /// Whether a key is configured for this build.
  static bool get isConfigured => _recaptchaSiteKey.isNotEmpty;

  /// Activates App Check when a key is available, and does nothing otherwise.
  ///
  /// Never throws: App Check is a hardening layer, and a hardening layer that
  /// can stop the app from starting is worse than not having it. A failure
  /// here leaves the security rules doing exactly what they did before.
  static Future<void> activate() async {
    if (!isConfigured) {
      debugPrint(
        '[APP_CHECK] Sin clave configurada — se omite. '
        'Las reglas de seguridad siguen siendo la defensa.',
      );
      return;
    }

    try {
      await FirebaseAppCheck.instance.activate(
        providerWeb: ReCaptchaV3Provider(_recaptchaSiteKey),
        // Debug providers on the mobile builds: a real device attestation is
        // not available in an emulator, and without this a debug build cannot
        // reach Firebase at all once enforcement is on.
        providerAndroid: kReleaseMode
            ? const AndroidPlayIntegrityProvider()
            : const AndroidDebugProvider(),
        providerApple: kReleaseMode
            ? const AppleAppAttestProvider()
            : const AppleDebugProvider(),
      );
      debugPrint('[APP_CHECK] Activado');
    } catch (e) {
      debugPrint('[APP_CHECK][ERROR] No se pudo activar: $e');
    }
  }
}
