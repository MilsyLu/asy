import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/support_case_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../models/support_case_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/support_case_repository.dart';
import '../../widgets/support_case_badges.dart';

/// Tablet/desktop-only alternate view: one column per [SupportCaseStatus],
/// dragging a card to another column calls `updateStatus` (already logs the
/// change in the timeline, no changes needed there). Table view (the
/// default) is Michel's own reference screenshot's layout; this is the
/// "kanban" alternative he also asked for.
class SupportCaseKanbanView extends StatelessWidget {
  const SupportCaseKanbanView({
    super.key,
    required this.cases,
    required this.onTap,
  });

  final List<SupportCaseModel> cases;
  final void Function(String caseId) onTap;

  static const double _columnWidth = 260;
  static const double _gap = 8;
  static const double _horizontalPadding = 16;

  @override
  Widget build(BuildContext context) {
    final columnCount = SupportCaseStatus.all.length;

    Widget columnFor(String status, {bool flexible = false}) {
      final column = _KanbanColumn(
        status: status,
        cases: cases.where((c) => c.status == status).toList(),
        onTap: onTap,
      );
      return flexible
          ? Expanded(child: column)
          : SizedBox(width: _columnWidth, child: column);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final neededWidth =
            _columnWidth * columnCount +
            _gap * (columnCount - 1) +
            _horizontalPadding * 2;
        // Room for all 5 columns without scrolling — stretch them to fill
        // the width instead of leaving space unused on the right.
        if (constraints.maxWidth >= neededWidth) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              _horizontalPadding,
              0,
              _horizontalPadding,
              16,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < columnCount; i++) ...[
                  columnFor(SupportCaseStatus.all[i], flexible: true),
                  if (i < columnCount - 1) const SizedBox(width: _gap),
                ],
              ],
            ),
          );
        }

        // Not enough room — fixed-width columns that scroll horizontally,
        // with a visible scrollbar so it's obvious there's more to the
        // right instead of the last column just looking cut off.
        return Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              _horizontalPadding,
              0,
              _horizontalPadding,
              20,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < columnCount; i++) ...[
                  columnFor(SupportCaseStatus.all[i]),
                  if (i < columnCount - 1) const SizedBox(width: _gap),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.status,
    required this.cases,
    required this.onTap,
  });

  final String status;
  final List<SupportCaseModel> cases;
  final void Function(String caseId) onTap;

  Future<void> _moveTo(BuildContext context, SupportCaseModel dragged) async {
    if (dragged.status == status) return;
    final user = context.read<AuthProvider>().appUser;
    if (user == null) return;
    await context.read<SupportCaseRepository>().updateStatus(
      dragged.id,
      status,
      authorId: user.id,
      authorName: user.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = SupportCaseStatus.colorFor(status);
    return DragTarget<SupportCaseModel>(
      onWillAcceptWithDetails: (details) => details.data.status != status,
      onAcceptWithDetails: (details) => _moveTo(context, details.data),
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: highlighted ? color.withValues(alpha: 0.08) : colors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: highlighted ? color : colors.divider),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '${cases.length}',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: cases.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Sin casos',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: cases.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _KanbanCard(
                          caseModel: cases[i],
                          onTap: () => onTap(cases[i].id),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KanbanCard extends StatelessWidget {
  const _KanbanCard({required this.caseModel, required this.onTap});

  final SupportCaseModel caseModel;
  final VoidCallback onTap;

  Widget _content(BuildContext context) {
    final colors = context.colors;
    final c = caseModel;
    final priorityColor = SupportCasePriority.colorFor(c.priority);
    final isResolved = !SupportCaseStatus.isOpen(c.status);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: priorityColor, width: 3),
          top: BorderSide(color: colors.divider),
          right: BorderSide(color: colors.divider),
          bottom: BorderSide(color: colors.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'CS-${c.caseNumber.toString().padLeft(4, '0')}',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            c.clientName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          Text(
            c.subject,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              PriorityBadge(priority: c.priority, dense: true),
              const Spacer(),
              DaysOpenBadge(
                days: c.daysOpen(),
                resolved: isResolved,
                dense: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<SupportCaseModel>(
      data: caseModel,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 260, child: _content(context)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _content(context)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: _content(context),
      ),
    );
  }
}
