import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import 'widgets/groups_report_tab.dart';
import 'widgets/performance_report_tab.dart';
import 'widgets/status_report_tab.dart';
import 'widgets/streak_report_tab.dart';
import 'widgets/tasks_report_tab.dart';
import 'widgets/top_clients_report_tab.dart';

/// Admin-only "Reportes" tab: 6 reports over a configurable date range.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late DateTimeRange _range;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 30)),
      end: DateTime(now.year, now.month, now.day),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: InkWell(
              onTap: _pickRange,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.calendarRange, color: colors.primary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${AppDateUtils.formatShortDate(_range.start)} - '
                        '${AppDateUtils.formatShortDate(_range.end)}',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(LucideIcons.chevronDown, color: colors.textSecondary, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: colors.primary,
            unselectedLabelColor: colors.textSecondary,
            indicatorColor: colors.primary,
            tabs: const [
              Tab(text: 'Tareas'),
              Tab(text: 'Estados'),
              Tab(text: 'Usuarios'),
              Tab(text: 'Grupos'),
              Tab(text: 'Racha'),
              Tab(text: 'Clientes'),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                TasksReportTab(range: _range),
                StatusReportTab(range: _range),
                PerformanceReportTab(range: _range),
                GroupsReportTab(range: _range),
                const StreakReportTab(),
                TopClientsReportTab(range: _range),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
