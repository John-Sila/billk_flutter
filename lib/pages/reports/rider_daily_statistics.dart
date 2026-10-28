import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class RiderDailyStatistics extends StatefulWidget {
  const RiderDailyStatistics({super.key});

  @override
  State<RiderDailyStatistics> createState() => _RiderDailyStatisticsState();
}

class _RiderDailyStatisticsState extends State<RiderDailyStatistics> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Map<String, Map<String, dynamic>> _usersClockouts = {};
  Map<String, String> _usernames = {};
  final Set<String> _fetchedUsers = {};
  bool _loadingUsers = true;

  // Ordered and filtered field labels - ONLY wanted fields
  final Map<String, String> fieldLabels = {
    'grossIncome': 'Gross Income',
    'netIncome': 'Net Income',
    'todaysInAppBalance': "Today's In-App Balance",
    'previousInAppBalance': 'Previous In-App Balance',
    'timeElapsed': 'Time Elapsed',
  };

  // Define the exact display order
  final List<String> displayOrder = [
    'grossIncome',
    'netIncome',
    'todaysInAppBalance',
    'previousInAppBalance',
    'timeElapsed',
  ];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    final usersSnapshot = await _firestore
      .collection('users')
      .where('userRank', isEqualTo: 'Rider')
      .get();

    final Map<String, String> finalUsernames = {};

    for (var doc in usersSnapshot.docs) {
      final data = doc.data();
      final clockouts = data['clockouts'] as Map<String, dynamic>? ?? {};

      if (clockouts.isNotEmpty) {
        finalUsernames[doc.id] = data['userName'] ?? doc.id;
      }
    }

    setState(() {
      _usernames = finalUsernames;
      _loadingUsers = false;
    });
  }

  Future<void> _fetchClockoutsForUser(String userId) async {
    if (_fetchedUsers.contains(userId)) return;

    final userDoc = await _firestore.collection('users').doc(userId).get();
    final data = userDoc.data();
    final clockouts = data?['clockouts'] as Map<String, dynamic>? ?? {};

    // This should never be empty because we filtered earlier.
    if (clockouts.isEmpty) {
      _fetchedUsers.add(userId);
      return;
    }

    final entriesWithDate = clockouts.entries.map((e) {
      final dayData = Map<String, dynamic>.from(e.value);
      final ts = dayData['posted_at'] as Timestamp?;
      final date = ts?.toDate() ?? DateTime(0);
      return MapEntry(e.key, {...dayData, 'dateTime': date});
    }).toList();

    entriesWithDate.sort(
        (a, b) => (b.value['dateTime'] as DateTime).compareTo(a.value['dateTime'] as DateTime));

    setState(() {
      _usersClockouts[userId] = Map.fromEntries(entriesWithDate);
      _fetchedUsers.add(userId);
    });
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    return DateFormat('dd MMM yyyy • HH:mm').format(ts.toDate());
  }

  String _formatValue(String value, String fieldKey) {
    if (value.isEmpty) return value;

    double? numValue = double.tryParse(value.replaceAll(',', ''));

    // Guard clause: Bail out if NaN or Infinity
    if (numValue == null || numValue.isNaN || numValue.isInfinite) {
      return value; // return raw string safely
    }

    // Currency fields
    return 'KSh ${_formatNumberWithCommas(numValue.toInt())}';
  }


  String _formatNumberWithCommas(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Rider Daily Statistics',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: theme.colorScheme.onSurface),
            onPressed: _fetchUsers,
          ),
        ],
      ),




body: _loadingUsers
    ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
    : _usernames.isEmpty
        ? _buildEmptyState(context)
        : Builder(
            builder: (context) {
              // Show all users initially, filter only those we've checked
              final filteredEntries = _usernames.entries.where((entry) {
                final userId = entry.key;
                final clockouts = _usersClockouts[userId];
                // Show: users with clockouts OR users not yet loaded
                return clockouts == null || clockouts.isNotEmpty;
              }).toList();

              if (filteredEntries.isEmpty) {
                return _buildEmptyState(context);
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                itemCount: filteredEntries.length,
                itemBuilder: (context, index) {
                  final userEntry = filteredEntries[index];
                  final userId = userEntry.key;
                  final username = userEntry.value;
                  final userClockouts = _usersClockouts[userId];

                  return _buildRiderCard(username, userId, userClockouts, theme);
                },
              );
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
            padding: const EdgeInsets.all(48),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.people_outline,
              size: 80,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'No Riders Found',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'No rider data available at the moment.',
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
  // Layout: a rider is a flat card; each shift is a "slip" - date on the left
  // margin, the two headline figures (gross / net) up top, then plain ledger
  // lines for everything else. No gradients, no stacked boxes.
  // ---------------------------------------------------------------------------

  Widget _buildRiderCard(String username, String userId, Map<String, dynamic>? clockouts, ThemeData theme) {
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: CircleAvatar(
            radius: 19,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              username.isEmpty ? '?' : username[0].toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          title: Text(
            username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            clockouts == null
                ? 'Tap to load shifts'
                : '${clockouts.length} ${clockouts.length == 1 ? 'shift' : 'shifts'}',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          onExpansionChanged: (expanded) {
            if (expanded) _fetchClockoutsForUser(userId);
          },
          children: clockouts == null || clockouts.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Loading shifts...',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ]
              : clockouts.entries
                  .map((dayEntry) => _buildDayCard(dayEntry, theme))
                  .toList(),
        ),
      ),
    );
  }

  Widget _buildDayCard(MapEntry<String, dynamic> dayEntry, ThemeData theme) {
    final scheme = theme.colorScheme;
    final day = dayEntry.key;
    final details = dayEntry.value as Map<String, dynamic>;
    final postedAt = _formatDate(details['posted_at'] as Timestamp?);

    final hasGross = details.containsKey('grossIncome');
    final hasNet = details.containsKey('netIncome');

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date line
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  day,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (postedAt.isNotEmpty)
                Text(
                  postedAt,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),

          // Headline figures
          if (hasGross || hasNet) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasGross)
                  Expanded(
                    child: _headline(
                      theme,
                      fieldLabels['grossIncome'] ?? 'Gross Income',
                      _formatValue(details['grossIncome'].toString(), 'grossIncome'),
                      scheme.onSurface,
                    ),
                  ),
                if (hasGross && hasNet) const SizedBox(width: 12),
                if (hasNet)
                  Expanded(
                    child: _headline(
                      theme,
                      fieldLabels['netIncome'] ?? 'Net Income',
                      _formatValue(details['netIncome'].toString(), 'netIncome'),
                      scheme.primary,
                    ),
                  ),
              ],
            ),
          ],

          // Remaining lines
          _buildMetricsList(details, theme),

          // Expenses
          if (details['expenses'] != null)
            _buildExpensesSection(details['expenses'] as Map<String, dynamic>, theme),
        ],
      ),
    );
  }

  Widget _headline(ThemeData theme, String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _ledgerLine(ThemeData theme, String label, String value) {
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsList(Map<String, dynamic> details, ThemeData theme) {
    // Gross / net are shown as headline figures above; the rest are ledger lines.
    final lines = displayOrder
        .where((k) => k != 'grossIncome' && k != 'netIncome' && details.containsKey(k))
        .toList();
    if (lines.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: lines
            .map((fieldKey) => _ledgerLine(
                  theme,
                  fieldLabels[fieldKey] ?? fieldKey,
                  _formatValue(details[fieldKey].toString(), fieldKey),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildExpensesSection(Map<String, dynamic> expenses, ThemeData theme) {
    final scheme = theme.colorScheme;
    if (expenses.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EXPENSES',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            ...expenses.entries.map(
              (expense) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        expense.key,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatValue(expense.value.toString(), 'expenses'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
