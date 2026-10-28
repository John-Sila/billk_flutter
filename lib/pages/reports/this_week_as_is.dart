import 'package:billkmotolinkltd/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class ThisWeekStateReport extends StatefulWidget {
  const ThisWeekStateReport({super.key});

  @override
  State<ThisWeekStateReport> createState() => _ThisWeekStateReportState();
}

class _ThisWeekStateReportState extends State<ThisWeekStateReport> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _loading = true;
  
  // This week's data only
  Map<String, dynamic>? _thisWeekData;
  String? _currentWeekLabel;
  
  // Track selected metric for detailed view
  String? _selectedMetric;
  String? _selectedDay;

  @override
  void initState() {
    super.initState();
    _fetchThisWeek();
  }

  String getWeekLabel(DateTime date) {
    int dayOfYear = int.parse(DateFormat("D").format(date));
    int weekNumber = ((dayOfYear - date.weekday + 10) / 7).floor();
    final firstDayOfWeek = date.subtract(Duration(days: date.weekday - 1));
    final lastDayOfWeek = firstDayOfWeek.add(const Duration(days: 6));
    final formatter = DateFormat("dd MMM yyyy");
    return "Week $weekNumber (${formatter.format(firstDayOfWeek)} to ${formatter.format(lastDayOfWeek)})";
  }

  String weekdayName() {
    return DateFormat("EEEE", "en_US").format(DateTime.now());
  }

  Future<void> _fetchThisWeek() async {
    try {
      final now = DateTime.now();
      final weekLabel = getWeekLabel(now);
      
      setState(() {
        _currentWeekLabel = weekLabel;
        _loading = true;
      });

      final doc = await _firestore.collection('deviations').doc(weekLabel).get();
      
      if (mounted) {
        setState(() {
          _thisWeekData = doc.data();
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

  String _normalizePhoneNumber(String phone) {
  // Remove all non-digits
  final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
  
  switch (digits.length) {
    case 9:
      // 9 digits → Add Kenya country code
      return '+254$digits';
    
    case 10:
      // 10 digits → Omit first letter (0), add +254
      if (digits.startsWith('0')) {
        return '+254${digits.substring(1)}';
      }
      return '+254$digits';
    
    case 12:
      // 12 digits → Already has country code, use as-is
      return digits;
    
    default:
      // Anything else → Return as-is (might already be correct)
      return phone;
  }
}

  Map<String, double> _calculateTotals() {
    if (_thisWeekData == null) return {'gross': 0, 'net': 0, 'expense': 0};
    
    double gross = 0, net = 0;
    
    for (final userEntry in _thisWeekData!.entries) {
      final userDays = userEntry.value as Map<String, dynamic>;
      for (final dayEntry in userDays.entries) {
        final day = dayEntry.value as Map<String, dynamic>;
        gross += _safeDouble(day['grossIncome']);
        net += _safeDouble(day['netIncome']);
        // ✅ EXPENSE = GROSS - NET (calculated, not from field)
      }
    }
    
    final expense = gross - net; // ✅ Fixed calculation
    
    return {'gross': gross, 'net': net, 'expense': expense};
  }

  List<FlSpot> _buildDailyTrend(String metric) {
    if (_thisWeekData == null) return [];
    
    final List<FlSpot> spots = [];
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    double x = 0;
    
    for (final userEntry in _thisWeekData!.entries) {
      final userDays = userEntry.value as Map<String, dynamic>;
      for (int i = 0; i < weekdays.length; i++) {
        final dayName = weekdays[i];
        final dayData = userDays[dayName];
        if (dayData != null) {
          double value = 0;
          switch (metric) {
            case 'gross':
              value = _safeDouble(dayData['grossIncome']);
              break;
            case 'net':
              value = _safeDouble(dayData['netIncome']);
              break;
            case 'expense':
              // ✅ EXPENSE = GROSS - NET (calculated per day per user)
              final gross = _safeDouble(dayData['grossIncome']);
              final netIncome = _safeDouble(dayData['netIncome']);
              value = gross - netIncome;
              break;
          }
          spots.add(FlSpot(x, value));
        }
        x++;
      }
    }
    
    return spots;
  }

  Map<String, Map<String, double>> _getDayUserContributions(String dayName, String metric) {
    if (_thisWeekData == null) return {};
    
    final Map<String, Map<String, double>> contributions = {};
    
    for (final userEntry in _thisWeekData!.entries) {
      final userName = userEntry.key;
      final userDays = userEntry.value as Map<String, dynamic>;
      final dayData = userDays[dayName];
      
      if (dayData != null) {
        double value = 0;
        switch (metric) {
          case 'gross':
            value = _safeDouble(dayData['grossIncome']);
            break;
          case 'net':
            value = _safeDouble(dayData['netIncome']);
            break;
          case 'expense':
            // ✅ EXPENSE = GROSS - NET (calculated per user per day)
            final gross = _safeDouble(dayData['grossIncome']);
            final netIncome = _safeDouble(dayData['netIncome']);
            value = gross - netIncome;
            break;
        }
        
        if (value > 0) {
          contributions[userName] = {
            'amount': value,
            'percentage': 0,
          };
        }
      }
    }
    
    // Sort by amount descending
    return Map.fromEntries(
      contributions.entries.toList()
        ..sort((a, b) => b.value['amount']!.compareTo(a.value['amount']!))
    );
  }

  Future<void> _contactRider(String riderName, String action, double amount) async {
    final metricName = _selectedMetric![0].toUpperCase() + _selectedMetric!.substring(1);
      final hour = DateTime.now().hour;
      String greeting;
      if (hour < 12) {
        greeting = 'Good morning';
      } else if (hour < 17) {
        greeting = 'Good afternoon';
      } else {
        greeting = 'Good evening';
      }
    final message = '$greeting $riderName, '
        'Your $metricName on $_selectedDay: KSh ${_formatCurrency(amount)}\n';
    
    try {
      // query users/UIDs where userName matches riderName
      final querySnapshot = await _firestore
          .collection('users')
          .where('userName', isEqualTo: riderName)
          .limit(1)
          .get();
      
      if (querySnapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('User "$riderName" not found')),
          );
        }
        return;
      }
      
      // get first matching document
      final userDoc = querySnapshot.docs.first;
      final phone = _normalizePhoneNumber(userDoc.data()['phoneNumber']!.toString());
      
      switch (action) {
        case 'whatsapp':
          await _launchWhatsApp(phone, message);
          break;
        case 'call':
          await _launchPhoneCall(phone);
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error contacting $riderName: $e')),
        );
      }
    }
  }

  Future<void> _launchWhatsApp(String phone, String message) async {
    final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri, 
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('WhatsApp is not installed'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('WhatsApp launch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open WhatsApp: $e')),
        );
      }
    }
  }

  Future<void> _launchPhoneCall(String phone) async {
    final uri = Uri.parse('tel:$phone');
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot make calls from this device'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Phone call error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to make call: $e')),
        );
      }
    }
  }

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  // Series colours come from the theme so they follow light/dark mode.
  Color _metricColor(String metric, ColorScheme s) {
    switch (metric) {
      case 'gross':
        return s.primary;
      case 'net':
        return s.tertiary;
      default:
        return AppTheme.warning;
    }
  }

  String _metricName(String metric) {
    switch (metric) {
      case 'gross':
        return 'Gross income';
      case 'net':
        return 'Net income';
      default:
        return 'Expenses';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totals = _calculateTotals();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          _currentWeekLabel ?? 'This Week',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchThisWeek,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: scheme.primary))
          : _thisWeekData == null || _thisWeekData!.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.analytics_outlined, size: 56, color: scheme.outline),
                      const SizedBox(height: 12),
                      Text(
                        'No data for this week',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : _selectedMetric != null && _selectedDay != null
                  ? _buildUserContributionsView(totals, theme)
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTotalsSection(totals, theme),
                          const SizedBox(height: 22),
                          _buildTrendCharts(totals, theme),
                        ],
                      ),
                    ),
    );
  }

  // Week totals: one flat card, three tappable ledger lines.
  Widget _buildTotalsSection(Map<String, double> totals, ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Text(
                  'WEEK TOTALS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  'Tap a line for the daily breakdown',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ],
            ),
          ),
          _buildClickableMetric('Total gross', totals['gross']!, theme, 'gross', first: true),
          _buildClickableMetric('Total net', totals['net']!, theme, 'net'),
          _buildClickableMetric('Total expenses', totals['expense']!, theme, 'expense'),
        ],
      ),
    );
  }

  Widget _buildClickableMetric(String label, double value, ThemeData theme, String metric, {bool first = false}) {
    final scheme = theme.colorScheme;
    final color = _metricColor(metric, scheme);
    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => _buildDaySelectorModal(metric, theme),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: scheme.outline, size: 20),
          ],
        ),
      ),
    );
  }

  double _getDayTotal(String dayName, String metric) {
    if (_thisWeekData == null) return 0;

    double total = 0;

    for (final userEntry in _thisWeekData!.entries) {
      final userDays = userEntry.value as Map<String, dynamic>;
      final dayData = userDays[dayName];

      if (dayData != null) {
        switch (metric) {
          case 'gross':
            total += _safeDouble(dayData['grossIncome']);
            break;
          case 'net':
            total += _safeDouble(dayData['netIncome']);
            break;
          case 'expense':
            final gross = _safeDouble(dayData['grossIncome']);
            final netIncome = _safeDouble(dayData['netIncome']);
            total += (gross - netIncome);
            break;
        }
      }
    }

    return total;
  }

  Widget _buildDaySelectorModal(String metric, ThemeData theme) {
    final scheme = theme.colorScheme;
    final metricColor = _metricColor(metric, scheme);
    final metricName = _metricName(metric);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metricName.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: metricColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'KSh ${_formatCurrency(_calculateTotals()[metric]!)}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Tap a day for riders',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                itemCount: _weekdays.length,
                itemBuilder: (context, index) {
                  final day = _weekdays[index];
                  final dayTotal = _getDayTotal(day, metric);
                  final hasData = dayTotal > 0;

                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: hasData
                        ? () {
                            Navigator.pop(context);
                            setState(() {
                              _selectedMetric = metric;
                              _selectedDay = day;
                            });
                          }
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: index == 0
                                ? scheme.outlineVariant
                                : scheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              day,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: hasData ? scheme.onSurface : scheme.outline,
                              ),
                            ),
                          ),
                          Text(
                            hasData ? 'KSh ${_formatCurrency(dayTotal)}' : 'No data',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: hasData ? FontWeight.w800 : FontWeight.w500,
                              color: hasData ? scheme.onSurface : scheme.outline,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: hasData ? scheme.outline : Colors.transparent,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserContributionsView(Map<String, double> totals, ThemeData theme) {
    final scheme = theme.colorScheme;
    final contributions = _getDayUserContributions(_selectedDay!, _selectedMetric!);
    final metricColor = _metricColor(_selectedMetric!, scheme);
    final dayTotal = _getDayTotal(_selectedDay!, _selectedMetric!);

    return Column(
      children: [
        // Slim header in place of the old second app bar
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() {
                  _selectedMetric = null;
                  _selectedDay = null;
                }),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_selectedDay  ·  ${_metricName(_selectedMetric!)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'KSh ${_formatCurrency(dayTotal)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: metricColor,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _fetchThisWeek,
              ),
            ],
          ),
        ),
        Expanded(
          child: contributions.isEmpty
              ? Center(
                  child: Text(
                    'No contributions for this day',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: contributions.length,
                  itemBuilder: (context, index) {
                    final userEntry = contributions.entries.elementAt(index);
                    final user = userEntry.key;
                    final data = userEntry.value;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: scheme.primaryContainer,
                            child: Text(
                              user.isEmpty ? '?' : user[0].toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'KSh ${_formatCurrency(data['amount']!)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: metricColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _contactButton(
                            icon: Icons.chat_outlined,
                            color: AppTheme.success,
                            tooltip: 'WhatsApp',
                            onTap: () => _contactRider(user, 'whatsapp', data['amount']!),
                          ),
                          _contactButton(
                            icon: Icons.call_outlined,
                            color: scheme.primary,
                            tooltip: 'Call',
                            onTap: () => _contactRider(user, 'call', data['amount']!),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _contactButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
      ),
    );
  }

  Widget _buildTrendCharts(Map<String, double> totals, ThemeData theme) {
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'DAILY TRENDS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildChartSection('Gross income', _buildDailyTrend('gross'), theme, _metricColor('gross', scheme)),
              const SizedBox(height: 18),
              _buildChartSection('Net income', _buildDailyTrend('net'), theme, _metricColor('net', scheme)),
              const SizedBox(height: 18),
              _buildChartSection('Expenses', _buildDailyTrend('expense'), theme, _metricColor('expense', scheme)),
            ],
          ),
        ),
      ],
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