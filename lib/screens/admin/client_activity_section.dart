import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../models/client_model.dart';
import '../../models/requirement_model.dart';
import '../../models/support_case_model.dart';
import '../../models/task_model.dart';
import '../../providers/catalog_provider.dart';
import '../home/widgets/task_detail_dialog.dart';
import '../../services/requirement_repository.dart';
import '../../services/support_case_repository.dart';
import '../../widgets/support_case_badges.dart';
import '../requirements/requirement_detail_view.dart';
import '../support_cases/support_case_detail_view.dart';

/// Casos de soporte y requerimientos de un cliente, para su ficha en
/// Clientes. Antes la ficha solo contaba tareas, así que para saber qué le
/// había pasado a un cliente había que buscarlo a mano en dos módulos.
///
/// Un caso o requerimiento es de este cliente si está enlazado a su registro
/// o, en los antiguos que nunca se enlazaron, si lleva su mismo nombre.
class ClientActivitySection extends StatelessWidget {
  const ClientActivitySection({
    super.key,
    required this.client,
    this.tareas = const [],
  });

  final ClientModel client;

  /// Las tareas del cliente, ya consultadas por quien abre la ficha para
  /// sus tres contadores. Se reciben hechas en vez de volver a pedirlas:
  /// serían dos consultas idénticas para la misma pantalla, y dos sitios
  /// donde se podría contar distinto.
  final List<TaskModel> tareas;

  static String _norm(String s) => s.trim().toLowerCase();

  bool _isMineCase(SupportCaseModel c) =>
      c.clientId == client.id ||
      (c.clientId == null && _norm(c.clientName) == _norm(client.name));

  bool _isMineRequirement(RequirementModel r) =>
      r.clientIds.contains(client.id) ||
      r.clientNames.any((n) => _norm(n) == _norm(client.name));

  @override
  Widget build(BuildContext context) {
    final caseRepo = context.read<SupportCaseRepository>();
    final reqRepo = context.read<RequirementRepository>();
    return StreamBuilder<List<SupportCaseModel>>(
      stream: caseRepo.watchAll(),
      builder: (context, casesSnap) {
        return StreamBuilder<List<RequirementModel>>(
          stream: reqRepo.watchAll(),
          builder: (context, reqSnap) {
            if (!casesSnap.hasData || !reqSnap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final cases = casesSnap.data!.where(_isMineCase).toList()
              ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
            final reqs = reqSnap.data!.where(_isMineRequirement).toList()
              ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
            final catalog = context.watch<CatalogProvider>();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Group(
                  title: 'Tareas',
                  emptyText: 'Sin tareas registradas.',
                  children: [
                    for (final t in tareas)
                      _Row(
                        code: catalog.taskTypeName(t.taskTypeId),
                        text: t.observations.trim().isEmpty
                            ? catalog.userName(t.assignedUserId)
                            : t.observations,
                        // La fecha para la que quedó la tarea y su hora:
                        // es lo que uno recuerda cuando pregunta por "lo de
                        // la vez pasada".
                        date: t.scheduledDateTime,
                        conHora: true,
                        trailing: Text(
                          catalog.statusName(t.statusId),
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () => showTaskDetailDialog(context, t),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _Group(
                  title: 'Casos de soporte',
                  emptyText: 'Sin casos de soporte.',
                  children: [
                    for (final c in cases)
                      _Row(
                        code: 'CS-${c.caseNumber.toString().padLeft(4, '0')}',
                        text: c.subject,
                        date: c.reportedAt,
                        trailing: StatusBadge(status: c.status, dense: true),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SupportCaseDetailView(caseId: c.id),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _Group(
                  title: 'Requerimientos',
                  emptyText: 'Sin requerimientos.',
                  children: [
                    for (final r in reqs)
                      _Row(
                        code: r.codigo,
                        text: r.description,
                        date: r.receivedAt,
                        trailing: Text(
                          r.status,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => Scaffold(
                              appBar: AppBar(title: Text(r.codigo)),
                              body: RequirementDetailView(requirementId: r.id),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.emptyText,
    required this.children,
  });

  final String title;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          children.isEmpty ? title : '$title (${children.length})',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        // Sin desplazamiento propio: la ventana que la contiene desplaza todo
        // el historial de una vez. Una lista con su propio scroll dentro de
        // otra obligaba a desplazar dos cosas distintas.
        if (children.isEmpty)
          Text(
            emptyText,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          )
        else
          ...children,
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.code,
    required this.text,
    required this.date,
    required this.trailing,
    required this.onTap,
    this.conHora = false,
  });

  final String code;
  final String text;
  final DateTime date;

  /// Las tareas llevan hora; un caso o un requerimiento, no — ahí se
  /// registra el día en que entró, y una hora inventada confundiría.
  final bool conHora;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text.trim().isEmpty ? '—' : text.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  ),
                  Text(
                    '$code · ${AppDateUtils.formatShortDate(date)}'
                    '${conHora ? ' · ${AppDateUtils.formatHour(date)}' : ''}',
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
            const SizedBox(width: 2),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
