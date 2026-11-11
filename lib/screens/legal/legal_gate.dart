import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/legal/legal_documents.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../providers/auth_provider.dart';
import '../../services/legal_repository.dart';
import '../../widgets/brand_logo.dart';
import 'legal_page.dart';

/// Deja pasar a [child] sólo cuando la persona ya aceptó los documentos
/// legales vigentes.
///
/// La aceptación es lo que convierte a la política en algo que de verdad
/// protege: la Ley 1581 de 2012 no pide sólo publicarla, pide poder probar
/// que el titular autorizó el tratamiento de sus datos. Esa prueba es el
/// registro que queda aquí.
class LegalGate extends StatefulWidget {
  const LegalGate({super.key, required this.child});

  final Widget child;

  @override
  State<LegalGate> createState() => _LegalGateState();
}

class _LegalGateState extends State<LegalGate> {
  Future<List<LegalDoc>>? _pendientes;
  String? _paraUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.watch<AuthProvider>().appUser?.id;
    // Se consulta una vez por sesión y por persona. Volver a preguntarlo en
    // cada reconstrucción sería una lectura por cada cambio de pantalla.
    if (uid != null && uid != _paraUid) {
      _paraUid = uid;
      _pendientes = context.read<LegalRepository>().pendientesDe(uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mientras falten los datos del responsable, los documentos son un
    // borrador y no se le pide a nadie que acepte un borrador.
    if (!LegalResponsable.completo) return widget.child;

    final future = _pendientes;
    if (future == null) return widget.child;

    return FutureBuilder<List<LegalDoc>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        // Si la consulta falla —sin señal, por ejemplo— se deja entrar. El
        // riesgo de no tener el registro de hoy es mucho menor que el de
        // dejar a un equipo entero sin poder trabajar por una caída.
        final pendientes = snap.data ?? const <LegalDoc>[];
        if (pendientes.isEmpty) return widget.child;

        return _PantallaAceptacion(
          pendientes: pendientes,
          onAceptado: () => setState(() {
            _pendientes = Future.value(const <LegalDoc>[]);
          }),
        );
      },
    );
  }
}

class _PantallaAceptacion extends StatefulWidget {
  const _PantallaAceptacion({required this.pendientes, required this.onAceptado});

  final List<LegalDoc> pendientes;
  final VoidCallback onAceptado;

  @override
  State<_PantallaAceptacion> createState() => _PantallaAceptacionState();
}

class _PantallaAceptacionState extends State<_PantallaAceptacion> {
  bool _marcada = false;
  bool _guardando = false;

  /// Desde dónde se aceptó. Queda en el registro: ante un reclamo, poder
  /// decir desde qué clase de dispositivo se hizo es parte de la prueba.
  String get _origen => kIsWeb ? 'web' : defaultTargetPlatform.name;

  Future<void> _aceptar() async {
    final user = context.read<AuthProvider>().appUser;
    if (user == null || _guardando) return;

    setState(() => _guardando = true);
    try {
      await context.read<LegalRepository>().aceptar(
        uid: user.id,
        nombre: user.name,
        correo: user.email,
        empresaId: user.empresaId,
        docs: widget.pendientes,
        origen: _origen,
      );
      widget.onAceptado();
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final esActualizacion = widget.pendientes.length < LegalDocs.todos.length;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              shrinkWrap: true,
              children: [
                const Center(child: BrandLogo(size: 56)),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  esActualizacion
                      ? 'Actualizamos nuestras condiciones'
                      : 'Antes de continuar',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  esActualizacion
                      ? 'Hay una versión nueva de los documentos que rigen el '
                            'uso de CheCu. Léala y acéptela para seguir.'
                      : 'Para usar CheCu necesitamos su autorización para '
                            'tratar sus datos personales. Esto es lo que eso '
                            'significa:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const _Punto(
                  icono: Icons.person_outline,
                  texto:
                      'Guardamos su nombre, su correo y lo que hace dentro de '
                      'la aplicación, para poder asignarle tareas y avisarle.',
                ),
                const _Punto(
                  icono: Icons.block_outlined,
                  texto:
                      'No vendemos sus datos, no hacemos publicidad con ellos '
                      'y ninguna otra empresa que use CheCu los ve.',
                ),
                const _Punto(
                  icono: Icons.lock_outline,
                  texto:
                      'Puede pedir en cualquier momento que se los mostremos, '
                      'los corrijamos o los borremos.',
                ),
                const SizedBox(height: AppSpacing.md),
                ...widget.pendientes.map(
                  (doc) => _EnlaceDocumento(doc: doc),
                ),
                const SizedBox(height: AppSpacing.sm),
                // La casilla arranca vacía y nadie la marca por el usuario:
                // una autorización que ya viene marcada no es una
                // autorización, y así lo ha dicho la Superintendencia.
                CheckboxListTile(
                  value: _marcada,
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _marcada = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    esActualizacion
                        ? 'He leído y acepto la versión nueva.'
                        : 'He leído y autorizo el tratamiento de mis datos '
                              'personales en los términos de estos documentos.',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton(
                  onPressed: _marcada && !_guardando ? _aceptar : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Text('Aceptar y continuar'),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  onPressed: _guardando
                      ? null
                      : () => context.read<AuthProvider>().signOut(),
                  child: Text(
                    'Ahora no, cerrar sesión',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnlaceDocumento extends StatelessWidget {
  const _EnlaceDocumento({required this.doc});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: OutlinedButton.icon(
        onPressed: () => mostrarDocumentoLegal(context, doc),
        icon: const Icon(Icons.description_outlined, size: 18),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Leer la ${doc.titulo.toLowerCase()}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 12,
          ),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}
