import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../services/notification_navigation.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/checu_mark.dart';
import '../../widgets/google_g_logo.dart';
import 'forgot_password_page.dart';

/// Fixed CheCu institutional colors (Sprint 7.3.2A). Login has its own brand
/// identity and must look identical regardless of the signed-out visitor's
/// eventual light/dark mode or accent color preference — those are per-user
/// settings stored on the Firestore profile, which isn't loaded yet at this
/// screen. Deliberately not sourced from [ThemeColors]/`context.colors`.
const _kLoginBackground = AppConstants.brandBackground;
const _kLoginPrimary = AppConstants.brandPrimary;

/// Warm neutral for field outlines and dividers — a plain grey reads cold
/// against the cream background.
const _kHairline = Color(0xFFE4E1D9);

/// Below this the two-column card would squeeze both halves too narrow, so it
/// stacks instead. Measured on the card, not the window: what matters is the
/// space the card actually got.
const double _kTwoColumnWidth = 900;

const double _kCardMaxWidth = 1040;
const double _kCardHeight = 620;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  bool get _busy => _isLoading || _isGoogleLoading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showDeactivationMessageIfAny());
  }

  void _showDeactivationMessageIfAny() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final message = auth.deactivationMessage;
    if (message == null) return;
    auth.clearDeactivationMessage();
    SnackbarUtils.showError(context, message);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await context.read<AuthProvider>().signIn(
            _emailController.text.trim(),
            _passwordController.text,
          );
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    setState(() => _isGoogleLoading = true);
    try {
      await context.read<AuthProvider>().signInWithGoogle();
    } on AccountNotProvisionedException catch (e) {
      // Naming the address matters: the Google chooser remembers personal
      // accounts, and picking the wrong one is by far the likeliest way to
      // land here — likelier than genuinely not having access.
      final email = e.email;
      _showLoginError(
        email == null
            ? 'Esa cuenta de Google no está registrada en CheCu'
            : '$email no está registrado en CheCu. Pídele a un administrador '
                'que cree tu cuenta, o ingresa con tu correo y contraseña',
      );
    } catch (e) {
      // Closing the Google window is a decision, not a failure — an error
      // banner here would just restate what the user had already done.
      final raw = e.toString();
      if (raw.contains('popup-closed-by-user') ||
          raw.contains('cancelled-popup-request') ||
          raw.contains('user-cancelled') ||
          raw.contains('web-context-canceled')) {
        return;
      }
      _showLoginError(SnackbarUtils.firebaseErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  /// Shows a login failure through the root navigator rather than this
  /// widget's own context.
  ///
  /// A rejected Google sign-in is authenticated first and refused second, and
  /// that gap is enough to tear this screen down: the moment the popup
  /// succeeds, Firebase reports a signed-in user, [AuthGate] swaps LoginPage
  /// for the boot splash, and this State is disposed while the entitlement
  /// check is still awaiting. By the time the rejection lands, `mounted` is
  /// false — so guarding on it, as the password path can afford to, would
  /// silently swallow the one message that explains what just happened and
  /// drop the user back on the login screen with no reason given.
  void _showLoginError(String message) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    SnackbarUtils.showError(context, message);
  }

  Future<void> _openSalesWhatsApp() async {
    final uri = Uri.parse(
      'https://wa.me/${AppConstants.salesWhatsAppNumber}'
      '?text=${Uri.encodeComponent(AppConstants.salesWhatsAppMessage)}',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      SnackbarUtils.showError(
        context,
        'No se pudo abrir WhatsApp. Escríbenos al +57 312 780 2648',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kLoginBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kCardMaxWidth),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumn = constraints.maxWidth >= _kTwoColumnWidth;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                      boxShadow: [
                        BoxShadow(
                          color: _kLoginPrimary.withValues(alpha: 0.10),
                          blurRadius: 40,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                      child: twoColumn
                          ? SizedBox(
                              height: _kCardHeight,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Expanded(child: _BrandPanel()),
                                  Expanded(child: _buildFormColumn(scrollable: true)),
                                ],
                              ),
                            )
                          : _buildFormColumn(scrollable: false),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The right-hand half on desktop, the whole card on a phone.
  ///
  /// Beside the brand panel its height is fixed by the panel, so it scrolls
  /// internally on a short window. Stacked, the page's own scroll view already
  /// handles that and a second one would fight it.
  Widget _buildFormColumn({required bool scrollable}) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: _CreateAccountButton(onPressed: _openSalesWhatsApp),
          ),
          // Stacked there is no brand panel, so the logo has to carry the
          // identity here rather than opening on a bare form.
          if (!scrollable) ...[
            const SizedBox(height: AppSpacing.lg),
            const Center(child: BrandLogo(size: 64)),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            '¡Bienvenido de nuevo a ${AppConstants.appName}!',
            style: const TextStyle(
              fontSize: 26,
              height: 1.2,
              fontWeight: FontWeight.bold,
              color: _kLoginPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppConstants.appTagline,
            style: TextStyle(
              fontSize: 13,
              color: _kLoginPrimary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LabeledField(
                  label: 'Correo electrónico',
                  child: TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    style: const TextStyle(color: _kLoginPrimary),
                    decoration: _fieldDecoration(
                      hint: 'ejemplo@correo.com',
                      icon: Icons.mail_outline,
                    ),
                    validator: Validators.email,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _LabeledField(
                  label: 'Contraseña',
                  child: TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    style: const TextStyle(color: _kLoginPrimary),
                    decoration: _fieldDecoration(
                      hint: '••••••••',
                      icon: Icons.lock_outline,
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Mostrar contraseña'
                            : 'Ocultar contraseña',
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: _kLoginPrimary.withValues(alpha: 0.5),
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'La contraseña es requerida' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: _kLoginPrimary.withValues(alpha: 0.75),
                      textStyle: const TextStyle(fontSize: 12),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
                      );
                    },
                    child: const Text('¿Olvidaste tu contraseña?'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kLoginPrimary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _kLoginPrimary.withValues(alpha: 0.4),
                      disabledForegroundColor: Colors.white70,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Iniciar sesión',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _OrDivider(),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 46,
            child: OutlinedButton(
              onPressed: _busy ? null : _signInWithGoogle,
              style: OutlinedButton.styleFrom(
                foregroundColor: _kLoginPrimary,
                side: const BorderSide(color: _kHairline),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
              ),
              child: _isGoogleLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: _kLoginPrimary,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GoogleGLogo(size: 18),
                        SizedBox(width: AppSpacing.sm),
                        Text(
                          'Continuar con Google',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _LoginFooter(),
        ],
      ),
    );

    return scrollable ? SingleChildScrollView(child: content) : content;
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      borderSide: const BorderSide(color: _kHairline),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: _kLoginPrimary.withValues(alpha: 0.35),
        fontSize: 14,
      ),
      prefixIcon: Icon(icon, size: 20, color: _kLoginPrimary.withValues(alpha: 0.45)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 14,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: const BorderSide(color: _kLoginPrimary, width: 1.6),
      ),
    );
  }
}

/// A field with its label above it rather than floating inside — at this size
/// a floating label shifts the layout on every focus change, and the labels
/// stay readable while the field holds text.
class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _kLoginPrimary.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// "Crear cuenta" — a sales enquiry, not a sign-up form. CheCu provisions
/// accounts from the admin panel, so this opens WhatsApp instead.
class _CreateAccountButton extends StatelessWidget {
  const _CreateAccountButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: _kLoginPrimary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: const Text('Crear cuenta'),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: _kHairline, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            'O INICIAR SESIÓN CON',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: _kLoginPrimary.withValues(alpha: 0.4),
            ),
          ),
        ),
        const Expanded(child: Divider(color: _kHairline, height: 1)),
      ],
    );
  }
}

/// One rotating panel: a photograph, a headline over it, and the dots.
typedef _Slide = ({String title, String subtitle, String asset});

/// The left half of the card — photographs chosen by Michel, rotating.
///
/// Each slide falls back to the brand gradient if its file is missing, so the
/// screen never shows a broken image: the artwork lives in `assets/branding/`
/// and is swapped there without touching this file.
class _BrandPanel extends StatefulWidget {
  const _BrandPanel();

  @override
  State<_BrandPanel> createState() => _BrandPanelState();
}

class _BrandPanelState extends State<_BrandPanel> {
  static const List<_Slide> _slides = [
    (
      title: 'Impulsa tu productividad',
      subtitle: 'Simplifica la gestión de tus tareas y cumplimiento',
      asset: 'assets/branding/login_slide_1.webp',
    ),
    (
      title: 'Todo tu equipo, al día',
      subtitle: 'Asigna, reprograma y haz seguimiento en un solo lugar',
      asset: 'assets/branding/login_slide_2.webp',
    ),
  ];

  final _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_controller.hasClients) return;
      _goTo((_index + 1) % _slides.length);
    });
  }

  void _goTo(int index) {
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      // Shows for the instant before the first photo decodes, so the panel
      // never flashes white against the card.
      color: _kLoginPrimary,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The photo and its caption travel together — sliding the words over
          // a stationary picture reads as two unrelated things moving.
          PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: _slides.length,
            itemBuilder: (context, i) => _BrandSlide(slide: _slides[i]),
          ),
          // Fixed furniture, outside the PageView: these belong to the panel,
          // not to any one slide.
          const Positioned(
            top: AppSpacing.xl,
            left: AppSpacing.xl,
            child: _PanelLogo(),
          ),
          Positioned(
            bottom: AppSpacing.xl,
            left: AppSpacing.xl,
            child: Row(
              children: List.generate(_slides.length, (i) {
                final active = i == _index;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => _goTo(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 5,
                      width: active ? 28 : 8,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: active ? 0.95 : 0.4),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandSlide extends StatelessWidget {
  const _BrandSlide({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          slide.asset,
          fit: BoxFit.cover,
          // Until the artwork is dropped into assets/branding/, and if a file
          // is ever renamed away, the panel falls back to the brand gradient
          // rather than to Flutter's broken-image box.
          errorBuilder: (context, error, stackTrace) => const _BrandGradient(),
        ),
        // Navy rather than black: it darkens the photograph enough for white
        // text to hold at any exposure while keeping the panel on-brand.
        //
        // Weighted hard to the bottom, where the caption sits, and kept light
        // at the top. An even veil strong enough to carry the text drained the
        // daylight out of both photographs and left them looking flat and
        // washed — the opposite of why they were chosen. These values were
        // checked by compositing the real scrim over the real crops.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _kLoginPrimary.withValues(alpha: 0.14),
                _kLoginPrimary.withValues(alpha: 0.34),
                _kLoginPrimary.withValues(alpha: 0.92),
              ],
              stops: const [0, 0.5, 1],
            ),
          ),
        ),
        Positioned(
          left: AppSpacing.xl,
          right: AppSpacing.xl,
          // Clears the dots, which sit at AppSpacing.xl from the bottom.
          bottom: AppSpacing.xl + 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                slide.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                slide.subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Stand-in for a missing photograph: the brand gradient the panel used before
/// there was any artwork, with two soft glows so it does not read as flat.
class _BrandGradient extends StatelessWidget {
  const _BrandGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF243063), _kLoginPrimary, Color(0xFF101632)],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(top: -90, right: -70, child: _Glow(size: 260, opacity: 0.16)),
          Positioned(bottom: -60, left: -80, child: _Glow(size: 220, opacity: 0.10)),
        ],
      ),
    );
  }
}

class _PanelLogo extends StatelessWidget {
  const _PanelLogo();

  @override
  Widget build(BuildContext context) {
    // A solid white disc with the symbol punched out of it in brand navy —
    // no ring here, since the disc's own edge against the dark panel already
    // reads as one.
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: const CheCuMark(size: 24, color: _kLoginPrimary),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.white.withValues(alpha: opacity),
              Colors.white.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Desarrollado por CustoDesk 2026" — always shown at the bottom of the
/// login card (Sprint 7.3.2A Parte 1).
class _LoginFooter extends StatelessWidget {
  const _LoginFooter();

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: 'Desarrollado por ',
        children: [
          TextSpan(
            text: AppConstants.appDeveloper,
            style: TextStyle(
              color: _kLoginPrimary.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: _kLoginPrimary.withValues(alpha: 0.45),
        fontSize: 11,
      ),
    );
  }
}
