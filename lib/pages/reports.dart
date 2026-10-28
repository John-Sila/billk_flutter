import 'package:billkmotolinkltd/pages/reports/non_variable_docs.dart';
import 'package:billkmotolinkltd/pages/reports/wage_evaluator.dart';
import 'package:billkmotolinkltd/pages/reports/absenteeism.dart';
import 'package:flutter/material.dart';
import 'package:billkmotolinkltd/pages/reports/this_week_as_is.dart';
import 'package:billkmotolinkltd/pages/reports/general_as_is_state.dart';
import 'package:billkmotolinkltd/pages/reports/human_resource_report.dart';
import 'package:billkmotolinkltd/pages/reports/rider_daily_statistics.dart';
import 'package:billkmotolinkltd/pages/reports/weekly_analysis_report.dart';

class Reports extends StatelessWidget {
  const Reports({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget tile({
      required IconData icon,
      required String title,
      required String subtitle,
      required Widget page,
    }) {
      return _ReportTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => page),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reports Center',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Analytics, financial summaries and performance metrics.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        tile(
          icon: Icons.receipt_long_rounded,
          title: 'Weekly Analysis Report',
          subtitle: 'View total rider revenue trends for the week.',
          page: const WeeklyAnalysisReport(),
        ),
        tile(
          icon: Icons.people_alt_rounded,
          title: 'Rider Daily Statistics',
          subtitle: 'View rider engagement insights.',
          page: const RiderDailyStatistics(),
        ),
        tile(
          icon: Icons.assignment_late_rounded,
          title: 'Human Resource',
          subtitle: 'See reports that await action.',
          page: const HumanResourceReports(),
        ),
        tile(
          icon: Icons.pie_chart_rounded,
          title: 'This Week As-Is State',
          subtitle: 'See how the company is doing this week.',
          page: const ThisWeekStateReport(),
        ),
        tile(
          icon: Icons.bar_chart_rounded,
          title: 'General As-Is State',
          subtitle: 'See how the company has been doing over the weeks.',
          page: const GeneralStateReport(),
        ),
        tile(
          icon: Icons.event_busy_rounded,
          title: 'Attendance Rota',
          subtitle: 'See which riders clocked out each day, by week.',
          page: const Absenteeism(),
        ),
        tile(
          icon: Icons.payments_rounded,
          title: 'Wage Evaluator',
          subtitle: 'Analyze and evaluate employee wages.',
          page: const WageEvaluatorScreen(),
        ),

        // non variable docs
        // Card(
        //   elevation: 2,
        //   child: ListTile(
        //     leading: const Icon(Icons.attach_money_rounded, color: Colors.teal),
        //     title: const Text('Non Variable Documents'),
        //     subtitle: const Text('Reproduce contractual documents for employees.'),
        //     onTap: () {
        //       Navigator.push(
        //         context,
        //         MaterialPageRoute(builder: (_) => const NonVariableDocuments()),
        //       );
        //     },
        //   ),
        // ),
      ],
    );
  }
}

class _ReportTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ReportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
