import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui' show FontFeature;

import 'package:billkmotolinkltd/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class WeeklyAnalysisReport extends StatefulWidget {
  const WeeklyAnalysisReport({super.key});

  @override
  State<WeeklyAnalysisReport> createState() => _WeeklyAnalysisReportState();
}

class _WeeklyAnalysisReportState extends State<WeeklyAnalysisReport> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, dynamic> _weeksData = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchWeeks();
    _cleanupOldWeeks();
  }

  Future<void> _cleanupOldWeeks() async {
    try {
      final fourMonthsAgo = DateTime.now().subtract(const Duration(days: 120));
      
      final snapshot = await FirebaseFirestore.instance
          .collection('deviations')
          .get();
      
      final batch = FirebaseFirestore.instance.batch();
      int deletedCount = 0;
      
      for (var doc in snapshot.docs) {
        final weekLabel = doc.id;
        final startDate = _extractStartDate(weekLabel); // ✅ Reuse exactly!
        
        if (startDate.isBefore(fourMonthsAgo)) {
          batch.delete(doc.reference);
          deletedCount++;
        }
      }
      
      if (deletedCount > 0) {
        await batch.commit();
        debugPrint('✅ Deleted $deletedCount old weeks');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cleaned $deletedCount old weeks')),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Cleanup error: $e');
    }
  }


  Future<void> _fetchWeeks() async {
    try {
      final snapshot = await _firestore.collection('deviations').get();
      Map<String, dynamic> weeks = {};
      for (var doc in snapshot.docs) {
        weeks[doc.id] = doc.data();
      }
      if (mounted) {
        setState(() {
          _weeksData = weeks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  final _weekLabelFormat = DateFormat('dd MMM yyyy');

  DateTime _extractStartDate(String weekLabel) {
    // Extract text between "(" and "to"
    final open = weekLabel.indexOf('(');
    final toIndex = weekLabel.indexOf('to');
    if (open == -1 || toIndex == -1) {
      // Fallback: very old / invalid label -> treat as minimal date
      return DateTime(1970);
    }
    final startPart = weekLabel.substring(open + 1, toIndex).trim(); // "08 Dec 2025"
    try {
      return _weekLabelFormat.parse(startPart);
    } catch (_) {
      return DateTime(1970);
    }
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '-';
    final numValue = double.tryParse(value.toString()) ?? 0.0;
    return NumberFormat('#,##0.00').format(numValue);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final sortedWeeks = _weeksData.entries.toList()
      ..sort((a, b) {
        final da = _extractStartDate(a.key);
        final db = _extractStartDate(b.key);
        // Newest first
        return db.compareTo(da);
      });
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Weekly Analysis',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchWeeks,
          ),
        ],
      ),
      body: _isLoading
    ? const Center(child: CircularProgressIndicator())
    : sortedWeeks.isEmpty
        ? _buildEmptyState(context)
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            itemCount: sortedWeeks.length,
            itemBuilder: (context, weekIndex) {
              final weekEntry = sortedWeeks[weekIndex];  // ✅ Direct index access
              final weekName = weekEntry.key;
              final usersMap = weekEntry.value as Map<String, dynamic>;
              
              return _buildWeekSection(weekName, usersMap);
            },
          ),

    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.analytics_outlined,
              size: 80,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'No Weekly Data Available',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64),
            child: Text(
              'Weekly deviation analysis will appear here when data is available.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Layout: each week is a flat card with a thin teal spine. Riders are plain
  // rows (initial + name + two figures). Opening a rider reveals a ledger:
  // hairline-ruled rows, right-aligned figures, deviations tinted by sign.
  // ---------------------------------------------------------------------------

  Widget _buildWeekSection(String weekName, Map<String, dynamic> usersMap) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dayCount = usersMap.values.expand((user) => (user as Map).values).length;

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
            Container(width: 4, color: scheme.primary),
            Expanded(
              child: Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
                  childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${usersMap.length} riders  ·  $dayCount days logged',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  children: usersMap.entries.map(_buildUserCard).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(MapEntry<String, dynamic> userEntry) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final userName = userEntry.key;
    final daysMap = userEntry.value as Map<String, dynamic>;

    double totalGross = 0, totalNet = 0, totalGrossDev = 0, totalNetGrossDiff = 0;
    for (final dayEntry in daysMap.entries) {
      final dayData = dayEntry.value as Map<String, dynamic>;
      totalGross += (dayData['grossIncome'] ?? 0).toDouble();
      totalNet += (dayData['netIncome'] ?? 0).toDouble();
      totalGrossDev += (dayData['grossDeviation'] ?? 0).toDouble();
      totalNetGrossDiff += (dayData['netGrossDifference'] ?? 0).toDouble();
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: CircleAvatar(
            radius: 15,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              userName.isEmpty ? '?' : userName[0].toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          title: Text(
            userName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Gross ',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  TextSpan(
                    text: _formatNumber(totalGross),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: '   Net ',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  TextSpan(
                    text: _formatNumber(totalNet),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          children: [
            _buildUserDataTable(daysMap, totalGross, totalNet, totalGrossDev, totalNetGrossDiff),
          ],
        ),
      ),
    );
  }

  Widget _buildUserDataTable(
    Map<String, dynamic> daysMap,
    double totalGross,
    double totalNet,
    double totalGrossDev,
    double totalNetGrossDiff,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final List<String> dayOrder = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    final sortedEntries = daysMap.entries.toList()
      ..sort((a, b) {
        final ia = dayOrder.indexOf(a.key);
        final ib = dayOrder.indexOf(b.key);
        if (ia == -1 && ib == -1) return 0;
        if (ia == -1) return 1;
        if (ib == -1) return -1;
        return ia.compareTo(ib);
      });

    // Column weights: day label gets a bit more room, figures share the rest.
    const flexes = [26, 24, 24, 21, 21];

    Widget cell(int i, Widget child, {Alignment align = Alignment.centerRight}) {
      return Expanded(
        flex: flexes[i],
        child: Align(
          alignment: align,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: align,
            child: child,
          ),
        ),
      );
    }

    Widget headCell(int i, String t) => cell(
          i,
          Text(
            t.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          align: i == 0 ? Alignment.centerLeft : Alignment.centerRight,
        );

    // Deviation / difference: tinted by sign so shortfalls stand out.
    Color signColor(double v) {
      if (v < 0) return AppTheme.danger;
      if (v > 0) return AppTheme.success;
      return scheme.onSurfaceVariant;
    }

    Widget figure(int i, double v, {bool bold = false, bool tinted = false}) {
      return cell(
        i,
        Text(
          _formatNumber(v),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: tinted ? signColor(v) : scheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
    }

    final hairline = BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7));

    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 6),
        child: Row(
          children: [
            headCell(0, 'Day'),
            headCell(1, 'Gross'),
            headCell(2, 'Net'),
            headCell(3, 'Dev'),
            headCell(4, 'Diff'),
          ],
        ),
      ),
    ];

    for (final dayEntry in sortedEntries) {
      final mapData = dayEntry.value as Map<String, dynamic>;
      final gross = (mapData['grossIncome'] ?? 0).toDouble();
      final net = (mapData['netIncome'] ?? 0).toDouble();
      final grossDev = (mapData['grossDeviation'] ?? 0).toDouble();
      final netGrossDiff = (mapData['netGrossDifference'] ?? 0).toDouble();

      rows.add(
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: Border(top: hairline)),
          child: Row(
            children: [
              cell(
                0,
                Text(
                  dayEntry.key,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                align: Alignment.centerLeft,
              ),
              figure(1, gross),
              figure(2, net),
              figure(3, grossDev, tinted: true),
              figure(4, netGrossDiff, tinted: true),
            ],
          ),
        ),
      );
    }

    rows.add(
      Container(
        padding: const EdgeInsets.only(top: 9, bottom: 2),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.onSurface.withValues(alpha: 0.55), width: 1.2)),
        ),
        child: Row(
          children: [
            cell(
              0,
              const Text(
                'Total',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
              align: Alignment.centerLeft,
            ),
            figure(1, totalGross, bold: true),
            figure(2, totalNet, bold: true),
            figure(3, totalGrossDev, bold: true, tinted: true),
            figure(4, totalNetGrossDiff, bold: true, tinted: true),
          ],
        ),
      ),
    );

    return Column(children: rows);
  }
}
