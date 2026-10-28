import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';

/// Absenteeism report.
///
/// READ-ONLY: this screen performs exactly two Firestore `get()` calls
/// (one query on `users`, one collection `get()` on `deviations`) and
/// never writes, updates, or deletes anything. It cross-references:
///
///   • `users` where userRank == 'Rider'  -> the roster of who *should*
///     be showing up, keyed by userName (their clock-out identity).
///   • `deviations/{weekLabel}` -> `{ userName: { weekday: {...} } }`,
///     already written by the existing clock-out flow every time a
///     rider clocks out. A userName appearing under a weekday means
///     that rider clocked out that day, i.e. was present.
///
/// A rider counts as "absent" on a given day only if all of these hold:
///   - the day has already happened (never flags future days)
///   - the day is on/after the rider's account creation date
///   - the day isn't a Sunday for riders who aren't scheduled to work
///     Sundays (`isWorkingOnSunday == false`), mirroring the same rule
///     already enforced on the Clock In screen
///   - the rider is currently active (`isActive != false`) and not
///     soft-deleted (`isDeleted != true`)
class Absenteeism extends StatefulWidget {
  const Absenteeism({super.key});

  @override
  State<Absenteeism> createState() => _AbsenteeismState();
}

class _RiderInfo {
  final String uid;
  final String userName;
  final bool isWorkingOnSunday;
  final DateTime? createdAt;

  _RiderInfo({
    required this.uid,
    required this.userName,
    required this.isWorkingOnSunday,
    required this.createdAt,
  });
}

class _WeekData {
  final String label;
  final DateTime start; // Monday
  final DateTime end; // Sunday
  final Map<String, Set<String>> presentByDay; // weekday -> set of userNames

  _WeekData({
    required this.label,
    required this.start,
    required this.end,
    required this.presentByDay,
  });
}

class _AbsenteeismState extends State<Absenteeism> {
  static const List<String> _weekdayOrder = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  final _weekLabelDateFormat = DateFormat('dd MMM yyyy');

  bool _loading = true;
  String? _error;
  List<_WeekData> _weeks = [];
  List<_RiderInfo> _roster = [];
  int _duplicateNameCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Roster of current riders (read-only query, no writes).
      final usersSnap = await firestore
          .collection('users')
          .where('userRank', isEqualTo: 'Rider')
          .get();

      final Map<String, int> nameCounts = {};
      final List<_RiderInfo> roster = [];

      for (final doc in usersSnap.docs) {
        final data = doc.data();
        final isDeleted = data['isDeleted'] == true;
        final isActive = data['isActive'] != false; // default true if absent
        if (isDeleted || !isActive) continue;

        final userName = (data['userName'] ?? '').toString().trim();
        if (userName.isEmpty) continue;

        final createdAtTs = data['createdAt'];
        final createdAt = createdAtTs is Timestamp ? createdAtTs.toDate() : null;

        nameCounts[userName] = (nameCounts[userName] ?? 0) + 1;

        roster.add(_RiderInfo(
          uid: doc.id,
          userName: userName,
          isWorkingOnSunday: data['isWorkingOnSunday'] == true,
          createdAt: createdAt,
        ));
      }

      final duplicates = nameCounts.values.where((c) => c > 1).length;

      // 2. All weekly deviation records (read-only, existing collection).
      final deviationsSnap = await firestore.collection('deviations').get();

      final List<_WeekData> weeks = [];
      for (final doc in deviationsSnap.docs) {
        final range = _extractRange(doc.id);
        if (range == null) continue; // skip malformed/legacy labels safely

        final Map<String, Set<String>> presentByDay = {
          for (final d in _weekdayOrder) d: <String>{},
        };

        final data = doc.data();
        data.forEach((userName, weekdaysRaw) {
          if (weekdaysRaw is! Map) return;
          for (final weekday in weekdaysRaw.keys) {
            final key = weekday.toString();
            if (presentByDay.containsKey(key)) {
              presentByDay[key]!.add(userName.toString().trim());
            }
          }
        });

        weeks.add(_WeekData(
          label: doc.id,
          start: range.$1,
          end: range.$2,
          presentByDay: presentByDay,
        ));
      }

      weeks.sort((a, b) => b.start.compareTo(a.start)); // newest first

      if (!mounted) return;
      setState(() {
        _roster = roster;
        _weeks = weeks;
        _duplicateNameCount = duplicates;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load absenteeism data: $e';
        _loading = false;
      });
    }
  }

  /// Parses "Week N (dd MMM yyyy to dd MMM yyyy)" -> (start, end).
  (DateTime, DateTime)? _extractRange(String weekLabel) {
    final open = weekLabel.indexOf('(');
    final toIndex = weekLabel.indexOf(' to ');
    final close = weekLabel.lastIndexOf(')');
    if (open == -1 || toIndex == -1 || close == -1 || close < toIndex) {
      return null;
    }
    final startPart = weekLabel.substring(open + 1, toIndex).trim();
    final endPart = weekLabel.substring(toIndex + 4, close).trim();
    try {
      final start = _weekLabelDateFormat.parse(startPart);
      final end = _weekLabelDateFormat.parse(endPart);
      return (start, end);
    } catch (_) {
      return null;
    }
  }

  bool _isFutureDay(DateTime day) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    return day.isAfter(todayOnly);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Attendance Rota', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
          : _error != null
              ? _buildErrorState(theme)
              : _weeks.isEmpty
                  ? _buildEmptyState(theme)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        children: [
                          _buildHeaderCard(theme),
                          const SizedBox(height: 14),
                          ..._weeks.asMap().entries.map(
                                (e) => _buildWeekTile(e.value, theme, e.key == 0),
                              ),
                        ],
                      ),
                    ),
    );
  }

  // Plain summary: one line of fact, one line of how it is worked out.
  Widget _buildHeaderCard(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_roster.length} active rider${_roster.length == 1 ? '' : 's'} tracked',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Presence comes from clock-out records. Riders not scheduled '
            'for Sunday work are left out of Sunday absences.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (_duplicateNameCount > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: AppTheme.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_duplicateNameCount duplicate rider name(s) detected. '
                      'Attendance for those names may overlap.',
                      style: TextStyle(fontSize: 12, color: scheme.onSurface, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeekTile(_WeekData week, ThemeData theme, bool latest) {
    final scheme = theme.colorScheme;

    // Only count days that have already occurred.
    final relevantDays = _weekdayOrder
        .asMap()
        .entries
        .map((e) => week.start.add(Duration(days: e.key)))
        .where((day) => !_isFutureDay(day))
        .toList();

    // Rough week-level summary for the collapsed subtitle.
    int totalPresentMarks = 0;
    int totalAbsentMarks = 0;
    for (final day in relevantDays) {
      final weekday = _weekdayOrder[day.weekday - 1];
      final present = week.presentByDay[weekday] ?? <String>{};
      for (final rider in _roster) {
        if (!_riderApplicable(rider, day, weekday)) continue;
        if (present.contains(rider.userName)) {
          totalPresentMarks++;
        } else {
          totalAbsentMarks++;
        }
      }
    }
    final totalMarks = totalPresentMarks + totalAbsentMarks;

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
            Container(width: 4, color: latest ? scheme.primary : scheme.outlineVariant),
            Expanded(
              child: Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
                  childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 6),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: Text(
                    week.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _buildLegendDot(AppTheme.success, '$totalPresentMarks present'),
                            const SizedBox(width: 14),
                            _buildLegendDot(AppTheme.danger, '$totalAbsentMarks absent'),
                          ],
                        ),
                        if (totalMarks > 0) ...[
                          const SizedBox(height: 8),
                          // Thin proportion bar: present vs absent for the week
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: SizedBox(
                              height: 5,
                              child: Row(
                                children: [
                                  if (totalPresentMarks > 0)
                                    Expanded(
                                      flex: totalPresentMarks,
                                      child: Container(color: AppTheme.success),
                                    ),
                                  if (totalAbsentMarks > 0)
                                    Expanded(
                                      flex: totalAbsentMarks,
                                      child: Container(color: AppTheme.danger),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  children: relevantDays.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              'No days have occurred yet for this week.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ]
                      : relevantDays.map((day) => _buildDayTile(week, day, theme)).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _riderApplicable(_RiderInfo rider, DateTime day, String weekday) {
    // Skip Sunday for riders not scheduled to work Sundays.
    if (weekday == 'Sunday' && !rider.isWorkingOnSunday) return false;
    // Skip days before the rider even joined.
    if (rider.createdAt != null) {
      final joined = DateTime(rider.createdAt!.year, rider.createdAt!.month, rider.createdAt!.day);
      if (day.isBefore(joined)) return false;
    }
    return true;
  }

  // A day is a ruled row inside the week, not a box of its own.
  Widget _buildDayTile(_WeekData week, DateTime day, ThemeData theme) {
    final scheme = theme.colorScheme;
    final weekday = _weekdayOrder[day.weekday - 1];
    final present = week.presentByDay[weekday] ?? <String>{};

    final applicableRiders = _roster.where((r) => _riderApplicable(r, day, weekday)).toList();
    final presentRiders = applicableRiders.where((r) => present.contains(r.userName)).toList()
      ..sort((a, b) => a.userName.compareTo(b.userName));
    final absentRiders = applicableRiders.where((r) => !present.contains(r.userName)).toList()
      ..sort((a, b) => a.userName.compareTo(b.userName));

    final dateLabel = DateFormat('dd MMM').format(day);
    final isToday = _isSameDate(day, DateTime.now());

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7))),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          shape: const Border(),
          collapsedShape: const Border(),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  '$weekday, $dateLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'TODAY',
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${presentRiders.length} present',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                TextSpan(
                  text: '  ·  ',
                  style: TextStyle(color: scheme.outline),
                ),
                TextSpan(
                  text: '${absentRiders.length} absent',
                  style: TextStyle(
                    color: absentRiders.isEmpty ? scheme.onSurfaceVariant : AppTheme.danger,
                    fontWeight: absentRiders.isEmpty ? FontWeight.w400 : FontWeight.w700,
                  ),
                ),
              ],
            ),
            style: theme.textTheme.bodySmall,
          ),
          children: [
            if (applicableRiders.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No riders were scheduled for this day.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              )
            else ...[
              // Absentees first: they are what this report is for.
              _buildRiderGroup(
                theme: theme,
                title: 'Absent',
                color: AppTheme.danger,
                riders: absentRiders,
                emphasised: true,
              ),
              const SizedBox(height: 12),
              _buildRiderGroup(
                theme: theme,
                title: 'Present',
                color: AppTheme.success,
                riders: presentRiders,
                emphasised: false,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRiderGroup({
    required ThemeData theme,
    required String title,
    required Color color,
    required List<_RiderInfo> riders,
    required bool emphasised,
  }) {
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              '${title.toUpperCase()}  ${riders.length}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        riders.isEmpty
            ? Text(
                'None',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
              )
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: riders
                    .map(
                      (r) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          // Absentees get the tint; present riders stay neutral.
                          color: emphasised
                              ? color.withValues(alpha: 0.10)
                              : scheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: emphasised
                                ? color.withValues(alpha: 0.35)
                                : scheme.outlineVariant,
                          ),
                        ),
                        child: Text(
                          r.userName,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: emphasised ? FontWeight.w700 : FontWeight.w500,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
      ],
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildEmptyState(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available_rounded, size: 56, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              'No attendance data yet',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Absenteeism will populate automatically once riders start clocking out.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
