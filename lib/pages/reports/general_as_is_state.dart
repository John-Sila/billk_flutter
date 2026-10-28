import 'package:billkmotolinkltd/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class GeneralStateReport extends StatefulWidget {
  const GeneralStateReport({super.key});

  @override
  State<GeneralStateReport> createState() => _GeneralStateReportState();
}

class _GeneralStateReportState extends State<GeneralStateReport> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _loading = true;

  // weekName → aggregated {gross, net, expense, chartData}
  List<MapEntry<String, Map<String, dynamic>>> _sortedWeeklyTotals = [];

  @override
  void initState() {
    super.initState();
    _fetchWeeks();
  }

  Future<void> _fetchWeeks() async {
    try {
      final snapshot = await _firestore.collection('deviations').get();

      final Map<String, Map<String, dynamic>> results = {};

      for (var doc in snapshot.docs) {
        final weekName = doc.id;
        final weekData = doc.data();

        double weekGross = 0;
        double weekNet = 0;
        double weekExpense = 0;

        final List<FlSpot> grossSpots = [];
        final List<FlSpot> netSpots = [];
        final List<FlSpot> expenseSpots = [];

        double x = 0;

        for (final userEntry in weekData.entries) {
          final userDays = userEntry.value as Map<String, dynamic>;

          for (final dayEntry in userDays.entries) {
            final day = dayEntry.value as Map<String, dynamic>;

            final gross = _safeDouble(day['grossIncome']);
            final net = _safeDouble(day['netIncome']);
            final exp = gross - net;

            weekGross += gross;
            weekNet += net;
            weekExpense += exp;

            grossSpots.add(FlSpot(x, gross));
            netSpots.add(FlSpot(x, net));
            expenseSpots.add(FlSpot(x, exp));

            x++;
          }
        }

        results[weekName] = {
          'gross': weekGross,
          'net': weekNet,
          'expense': weekExpense,
          'grossChart': grossSpots,
          'netChart': netSpots,
          'expenseChart': expenseSpots,
        };
      }

      // SORT WEEKS by week number (descending - latest first)
      DateTime? _parseWeekDate(String weekKey) {
        try {
          // Extract "12 Jan 2026" from "Week 3 (12 Jan 2026 to 18 Jan 2026)"
          final match = RegExp(r'\((\d{1,2})\s+(\w{3})\s+(\d{4})').firstMatch(weekKey);
          
          if (match == null) return null;
          
          final day = int.tryParse(match.group(1) ?? '0');
          final monthStr = (match.group(2) ?? '').toLowerCase();
          final year = int.tryParse(match.group(3) ?? '0');
          
          if (day == null || year == null) return null;
          
          const months = {
            'jan': DateTime.january, 'feb': DateTime.february, 'mar': DateTime.march,
            'apr': DateTime.april, 'may': DateTime.may, 'jun': DateTime.june,
            'jul': DateTime.july, 'aug': DateTime.august, 'sep': DateTime.september,
            'oct': DateTime.october, 'nov': DateTime.november, 'dec': DateTime.december,
          };
          
          final month = months[monthStr] ?? DateTime.january;
          return DateTime(year, month, day);
        } catch (e) {
          return null;
        }
      }

      final sortedEntries = results.entries.toList()
        ..sort((a, b) {
          final dateA = _parseWeekDate(a.key);
          final dateB = _parseWeekDate(b.key);
          
          // ✅ NULL-SAFE COMPARE
          if (dateA == null && dateB == null) return 0;
          if (dateA == null) return 1; // Put nulls at end
          if (dateB == null) return -1;
          
          return dateB.compareTo(dateA); // ✅ Safe now!
        });

      

      if (mounted) {
        setState(() {
          _sortedWeeklyTotals = sortedEntries;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  double _safeDouble(dynamic n) {
    if (n == null) return 0;
    if (n is num) return n.toDouble();
    final parsed = double.tryParse(n.toString());
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return 0;
    return parsed;
  }

  String _formatCurrency(double value) {
    return NumberFormat('#,###', 'en_KE').format(value);
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'General As-Is State',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchWeeks,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: scheme.primary))
          : _sortedWeeklyTotals.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.analytics_outlined, size: 56, color: scheme.outline),
                      const SizedBox(height: 12),
                      Text(
                        'No weekly data available',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: _sortedWeeklyTotals.length,
                  itemBuilder: (context, index) {
                    final entry = _sortedWeeklyTotals[index];
                    return _buildWeekCard(entry.key, entry.value, theme, index);
                  },
                ),
    );
  }

  // Series colours come from the theme so they follow light/dark mode.
  Color _grossColor(ColorScheme s) => s.primary;
  Color _netColor(ColorScheme s) => s.tertiary;
  Color _expenseColor(ColorScheme s) => AppTheme.warning;

  // A week is a flat card with a thin spine. Open it for the figures
  // (a plain ledger, no tiles) followed by three quiet trend lines.
  Widget _buildWeekCard(String weekName, Map<String, dynamic> totals, ThemeData theme, int index) {
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: index == 0 ? scheme.primary : scheme.outlineVariant),
            Expanded(
              child: Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: Text(
                    weekName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Gross ',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          TextSpan(
                            text: 'KSh ${_formatCurrency(totals['gross'])}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (index == 0)
                            TextSpan(
                              text: '   Latest',
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  children: [
                    _buildTotalsSection(totals, theme),
                    const SizedBox(height: 18),
                    _buildChartSection('Gross income', totals['grossChart'], theme, _grossColor(scheme)),
                    const SizedBox(height: 14),
                    _buildChartSection('Net income', totals['netChart'], theme, _netColor(scheme)),
                    const SizedBox(height: 14),
                    _buildChartSection('Expenses', totals['expenseChart'], theme, _expenseColor(scheme)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsSection(Map<String, dynamic> totals, ThemeData theme) {
    final scheme = theme.colorScheme;

    return Column(
      children: [
        _metricRow('Total gross', totals['gross'], theme, _grossColor(scheme), first: true),
        _metricRow('Total net', totals['net'], theme, _netColor(scheme)),
        _metricRow('Total expenses', totals['expense'], theme, _expenseColor(scheme)),
      ],
    );
  }

  // One ledger line: colour key, label, figure on the right.
  Widget _metricRow(String label, double value, ThemeData theme, Color color, {bool first = false}) {
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: first ? Colors.transparent : scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            'KSh ${_formatCurrency(value)}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection(String title, List<FlSpot> spots, ThemeData theme, Color lineColor) {
    final scheme = theme.colorScheme;

    if (spots.isEmpty) {
      return Text(
        'No data for ${title.toLowerCase()}',
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      );
    }

    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: lineColor,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: null,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: scheme.outlineVariant.withValues(alpha: 0.8),
                  strokeWidth: 1,
                ),
              ),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  curveSmoothness: 0.25,
                  spots: spots,
                  barWidth: 2,
                  color: lineColor,
                  // Dots only when there are few points; many points read as noise.
                  dotData: FlDotData(
                    show: spots.length <= 8,
                    getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                      radius: 3,
                      color: lineColor,
                      strokeWidth: 1.5,
                      strokeColor: isDark ? scheme.surface : Colors.white,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        lineColor.withValues(alpha: isDark ? 0.22 : 0.16),
                        lineColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}