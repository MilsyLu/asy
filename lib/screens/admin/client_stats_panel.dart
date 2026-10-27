import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/support_case_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../models/client_model.dart';
import '../../models/support_case_model.dart';
import '../../providers/catalog_provider.dart';
import '../../services/support_case_repository.dart';
import '../../widgets/side_panel_shell.dart';

/// Resumen de la cartera de clientes, debajo de "Nuevo cliente": ocupa el
/// espacio que quedaba vacío con lo que se pregunta al entrar a Clientes
/// (cuántos son, cuántos llegaron este mes, quién tiene casos abiertos).
class ClientStatsPanel extends StatelessWidget {
  const ClientStatsPanel({super.key, this.compact = false});

  /// Menos aire entre filas, para la columna derecha de escritorio donde
  /// comparte el alto con "Nuevo cliente" y no debe necesitar scroll.
  final bool compact;

  static String _norm(String s) => s.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final clients = context.watch<CatalogProvider>().clients;
    final now = DateTime.now();
    final nuevosMes = clients
        .where((c) => c.createdAt != null &&
            c.createdAt!.year == now.year &&
            c.createdAt!.month == now.month)
        .length;
    final sinTelefono = clients.where((c) => c.phone.trim().isEmpty).length;

    return SidePanelShell(
      title: 'Resumen',
      icon: LucideIcons.barChart3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${clients.length}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: compact ? 28 : 34,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  clients.length == 1 ? 'cliente' : 'clientes',
                  style: TextStyle(color: colors.textSecondary, fontSize: 14),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 14),
          _StatLine(
            compact: compact,
            icon: LucideIcons.sparkles,
            label: 'Nuevos este mes',
            value: nuevosMes,
          ),
          _StatLine(
            compact: compact,
            icon: LucideIcons.phoneOff,
            label: 'Sin teléfono',
            value: sinTelefono,
          ),
          StreamBuilder<List<SupportCaseModel>>(
            stream: context.read<SupportCaseRepository>().watchAll(),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              final porCliente = _casesByClient(clients, snap.data!);
              final conAbiertos =
                  porCliente.values.where((s) => s.abiertos > 0).length;
              final top = porCliente.entries.toList()
                ..sort((a, b) => b.value.total.compareTo(a.value.total));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatLine(
                    compact: compact,
                    icon: LucideIcons.lifeBuoy,
                    label: 'Con casos abiertos',
                    value: conAbiertos,
                  ),
                  if (top.isNotEmpty) ...[
                    SizedBox(height: compact ? 8 : 12),
                    Divider(color: colors.divider, height: 1),
                    SizedBox(height: compact ? 8 : 12),
                    Text(
                      'Más casos de soporte',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final e in top.take(3))
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: compact ? 2 : 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.key.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: colors.textPrimary, fontSize: 13),
                              ),
                            ),
                            Text(
                              e.value.abiertos > 0
                                  ? '${e.value.total} · ${e.value.abiertos} abiertos'
                                  : '${e.value.total}',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Mismo criterio que la ficha del cliente: enlazado por id o, en los
  /// casos antiguos sin enlace, por nombre exacto.
  static Map<ClientModel, ({int total, int abiertos})> _casesByClient(
    List<ClientModel> clients,
    List<SupportCaseModel> cases,
  ) {
    final byId = {for (final c in clients) c.id: c};
    final byName = <String, ClientModel>{};
    for (final c in clients) {
      byName.putIfAbsent(_norm(c.name), () => c);
    }
    final out = <ClientModel, ({int total, int abiertos})>{};
    for (final sc in cases) {
      final client = sc.clientId != null ? byId[sc.clientId] : byName[_norm(sc.clientName)];
      if (client == null) continue;
      final prev = out[client] ?? (total: 0, abiertos: 0);
      out[client] = (
        total: prev.total + 1,
        abiertos: prev.abiertos + (SupportCaseStatus.isOpen(sc.status) ? 1 : 0),
      );
    }
    return out;
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({
    required this.icon,
    required this.label,
    required this.value,
    this.compact = false,
  });

  final bool compact;
  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 3 : 5),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 5 : 6),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(icon, size: 14, color: colors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(color: colors.textPrimary, fontSize: 13)),
          ),
          Text(
            '$value',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
