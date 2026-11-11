import 'package:flutter/material.dart';

import '../../core/legal/legal_documents.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/theme/theme_colors.dart';

/// Abre un documento legal como página completa, con su botón de volver.
Future<void> mostrarDocumentoLegal(BuildContext context, LegalDoc doc) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => LegalPage(doc: doc)),
  );
}

/// Muestra un documento legal.
///
/// Se puede abrir sin haber iniciado sesión: desde el pie del inicio de
/// sesión y desde la pantalla de aceptación. Un documento que sólo se puede
/// leer después de entrar no está publicado — y la ley pide que la política
/// de tratamiento esté disponible para consulta.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.doc});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: Text(doc.titulo)),
      body: SafeArea(
        child: Center(
          // Un texto largo a todo el ancho de un monitor es ilegible: el ojo
          // pierde el renglón al volver. Se limita a una medida de lectura.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              children: [
                if (!LegalResponsable.completo) const _AvisoBorrador(),
                Text(
                  doc.titulo,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 22,
                    height: 1.25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Versión ${doc.version} · Vigente desde el ${doc.vigenteDesde}',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: AppSpacing.md),
                ...cuerpoLegalEnWidgets(doc.cuerpo, colors),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Convierte el texto del documento en widgets.
///
/// Un formato mínimo —`## ` para título, `- ` para viñeta— en vez de una
/// librería de Markdown: son dos marcas en todo el documento, y añadir una
/// dependencia entera para eso trae su propio mantenimiento. `**negrita**`
/// se respeta porque dentro de los plazos de ley conviene resaltarlos.
List<Widget> cuerpoLegalEnWidgets(String cuerpo, AppColorsExtension colors) {
  final widgets = <Widget>[];

  for (final crudo in cuerpo.trim().split('\n')) {
    final linea = crudo.trim();
    if (linea.isEmpty) continue;

    if (linea.startsWith('## ')) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: 6),
          child: Text(
            linea.substring(3),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      continue;
    }

    if (linea.startsWith('- ')) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 10),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              Expanded(child: _parrafo(linea.substring(2), colors)),
            ],
          ),
        ),
      );
      continue;
    }

    widgets.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _parrafo(linea, colors),
      ),
    );
  }

  return widgets;
}

/// Un párrafo, con los tramos entre `**` en negrita.
Widget _parrafo(String texto, AppColorsExtension colors) {
  final base = TextStyle(
    color: colors.textPrimary,
    fontSize: 13.5,
    height: 1.55,
  );

  final partes = texto.split('**');
  return SelectableText.rich(
    TextSpan(
      children: [
        for (var i = 0; i < partes.length; i++)
          TextSpan(
            text: partes[i],
            // Los tramos impares son los que iban entre los dos asteriscos.
            style: i.isOdd
                ? base.copyWith(fontWeight: FontWeight.w700)
                : base,
          ),
      ],
    ),
    style: base,
  );
}

/// Sale mientras falten datos del responsable en [LegalResponsable].
///
/// Publicar una política con espacios sin llenar es peor que no publicarla:
/// deja por escrito que no se sabe quién responde. Este aviso existe para
/// que eso no llegue en silencio a producción.
class _AvisoBorrador extends StatelessWidget {
  const _AvisoBorrador();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: colors.error.withValues(alpha: 0.4)),
      ),
      child: Text(
        'BORRADOR — faltan los datos del responsable. Este documento aún no '
        'tiene validez y no se le está pidiendo a nadie que lo acepte.',
        style: TextStyle(
          color: colors.error,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
