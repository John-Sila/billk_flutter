import 'package:billkmotolinkltd/services/toast_service.dart';
import 'package:billkmotolinkltd/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class Profiles extends StatefulWidget {
  const Profiles({super.key});

  @override
  State<Profiles> createState() => _ProfilesState();
}

class _ProfilesState extends State<Profiles> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream;

  @override
  void initState() {
    super.initState();
    _usersStream = FirebaseFirestore.instance
        .collection('users')
        .orderBy('userName')
        .snapshots();
  }

  Future<void> _updateField(String uid, String field, dynamic value) async {
    final now = Timestamp.now();
    final notificationId =
        DateTime.now().millisecondsSinceEpoch.toString();
        
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({
        field: value,
        'updatedAt': FieldValue.serverTimestamp(),
        'notifications.$notificationId': {
          'isRead': false,
          'message': 'Your account has been altered by an admin.',
          'time': now,
        },
        "numberOfNotifications": FieldValue.increment(1),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update $field: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _settlePendingAmounts() async {
    final theme = Theme.of(context);
    final confirmed = await _showConfirmDialog(
      title: 'Settle All Pending Amounts',
      content: 'This will clear all pending amounts and add them to company income. This action cannot be undone.',
      action: 'Proceed',
    );

    if (!confirmed) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final usersSnapshot = await firestore.collection('users').get();
      
      int totalPending = 0;
      final batch = firestore.batch();

      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final pending = _safeNum(data['pendingAmount'], 0).toInt();
        
        if (pending > 0) {
          totalPending += pending;
          batch.update(doc.reference, {'pendingAmount': 0});
        }
      }

      if (totalPending > 0) {
        batch.update(
          firestore.collection('general').doc('general_variables'),
          {'companyIncome': FieldValue.increment(totalPending)},
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No pending amounts to settle.'),
              backgroundColor: theme.colorScheme.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: theme.colorScheme.onPrimary),
                const SizedBox(width: 12),
                Text('Settlement completed: KSh $totalPending'),
              ],
            ),
            backgroundColor: theme.colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Settlement failed: $e'),
            backgroundColor: theme.colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatKenyanPhone(String phone) {
    if (phone == 'No phone') return phone;

    // Remove all non‑digits
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');

    // Normalize to Kenyan E.164-like
    String kenyaDigits;
    if (digits.length == 10 && digits.startsWith('0')) {
      // 0712345678 → 254712345678
      kenyaDigits = '254${digits.substring(1)}';
    } else if (digits.length == 9) {
      // 712345678 → 254712345678
      kenyaDigits = '254$digits';
    } else if (digits.length == 12 && digits.startsWith('254')) {
      kenyaDigits = digits;
    } else {
      return phone; // can't normalize
    }

    // Now format: +254730 234 778
    // Split: 730 (6‑chars group), 234 (3), 778 (3)
    if (kenyaDigits.length == 12) {
      final code = kenyaDigits.substring(0, 6);   // 254730
      final group1 = kenyaDigits.substring(6, 9);  // 234
      final group2 = kenyaDigits.substring(9, 12); // 778
      return '+$code $group1 $group2';
    }

    return phone; // fallback
  }

  // 1. Double-check that this line is added to the top of your _ProfilesState class:
  final Set<String> _expandedUserIds = {};

  String _money(num n) => NumberFormat('#,##0').format(n);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Workforce & Persons',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              icon: const Icon(Icons.account_balance_wallet_rounded, size: 17),
              label: const Text('Settle All'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: const Size(0, 36),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _settlePendingAmounts,
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _usersStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState(context);
          }

          final visibleUsers = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final rank = _safeToString(data['userRank'], '').toLowerCase();
            return rank != 'ceoo' && rank != 'systems, itt';
          }).toList();

          if (visibleUsers.isEmpty) {
            return _buildNoEligibleUsers(context);
          }

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(12, 4, 12, MediaQuery.paddingOf(context).bottom + 24),
            itemCount: visibleUsers.length,
            itemBuilder: (_, index) {
              final doc = visibleUsers[index];
              final uid = doc.id;
              final user = doc.data() as Map<String, dynamic>;
              final isExpanded = _expandedUserIds.contains(uid);

              return _buildUserCard(
                uid,
                user,
                theme,
                isExpanded: isExpanded,
                onToggleExpand: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedUserIds.remove(uid);
                    } else {
                      _expandedUserIds.add(uid);
                    }
                  });
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// Hairline-ruled group of rows inside a user card.
  Widget _ruled(ThemeData theme, List<Widget> rows) {
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.7)),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _contactLine(ThemeData theme, IconData icon, String text, {VoidCallback? onTap, Color? color}) {
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 16, color: scheme.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color ?? scheme.onSurfaceVariant,
                  fontWeight: onTap != null ? FontWeight.w600 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(
    String uid,
    Map<String, dynamic> user,
    ThemeData theme, {
    required bool isExpanded,
    required VoidCallback onToggleExpand,
  }) {
    final scheme = theme.colorScheme;

    final String userRank = _safeToString(user['userRank'], 'Unknown').trim().toUpperCase();
    final bool isPrivileged = {'CEO', 'SYSTEMS, IT', 'MANAGER'}.contains(userRank);
    final bool isActive = _toBool(user['isActive']);

    final String rawPhone = _safeToString(user['phoneNumber'], 'No phone');
    final String formatted = _formatKenyanPhone(rawPhone);

    final bool canCall = formatted.isNotEmpty && formatted != 'No phone';
    final String dialNumber = canCall ? 'tel:$formatted' : '';

    final Color accent = isPrivileged ? scheme.tertiary : scheme.primary;
    final Color spine = !isActive ? scheme.error : accent;
    final Color nameColor = isActive ? scheme.onSurface : scheme.error;

    final num pending = _safeNum(user['pendingAmount'], 0);

    // The expanded part of the card, built once and animated in/out below.
    final Widget expandedBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Divider(height: 1, color: scheme.outlineVariant),
        const SizedBox(height: 8),

        // Contact - always shown, "Not set" when missing
        _contactLine(
          theme,
          Icons.email_outlined,
          _safeToString(user['email'], '').isEmpty
              ? 'No email'
              : _safeToString(user['email'], 'No email'),
        ),
        _contactLine(
          theme,
          Icons.phone_outlined,
          formatted,
          color: canCall ? accent : null,
          onTap: canCall
              ? () async {
                  final Uri uri = Uri.parse(dialNumber);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  } else {
                    ToastService.error('Could not launch dialer');
                  }
                }
              : null,
        ),
        // The user's document ID (uid) - tap to copy.
        _contactLine(
          theme,
          Icons.fingerprint_rounded,
          uid,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: uid));
            ToastService.success('UID copied');
          },
        ),

        if (!isPrivileged) ...[
          _sectionLabel(theme, 'Targets & money'),
          _ruled(theme, [
            _EditableNumberField(
              label: 'Daily Target',
              value: _safeNum(user['dailyTarget'], 0).toInt(),
              isSet: user['dailyTarget'] != null,
              icon: Icons.flag_rounded,
              onUpdate: (v) => _updateField(uid, 'dailyTarget', v),
            ),
            _EditableNumberField(
              label: 'Sunday Target',
              value: _safeNum(user['sundayTarget'], 0).toInt(),
              isSet: user['sundayTarget'] != null,
              icon: Icons.calendar_today_rounded,
              onUpdate: (v) => _updateField(uid, 'sundayTarget', v),
            ),
            _PendingAmountField(
              label: 'Pending Amount',
              value: _safeNum(user['pendingAmount'], 0).toInt(),
              isSet: user['pendingAmount'] != null,
              icon: Icons.payments_rounded,
              uid: uid,
              onValueUpdated: (v) => {},
            ),
            _EditableNumberField(
              label: 'In-App Balance',
              value: _safeNum(user['currentInAppBalance'], 0).toInt(),
              isSet: user['currentInAppBalance'] != null,
              icon: Icons.account_balance_wallet_rounded,
              onUpdate: (v) => _updateField(uid, 'currentInAppBalance', v),
            ),
          ]),

          _sectionLabel(theme, 'Account'),
          _ruled(theme, [
            _EditableBoolField(
              label: 'Active',
              value: isActive,
              isSet: user['isActive'] != null,
              icon: Icons.power_settings_new_rounded,
              onUpdate: (v) => _updateField(uid, 'isActive', v),
            ),
            _EditableBoolField(
              label: 'Verified',
              value: _toBool(user['isVerified']),
              isSet: user['isVerified'] != null,
              icon: Icons.verified_rounded,
              onUpdate: (v) => _updateField(uid, 'isVerified', v),
            ),
            // Clocked In is set by the clock-in / clock-out flow,
            // so it is shown read-only here.
            _EditableBoolField(
              label: 'Clocked In',
              value: _toBool(user['isClockedIn']),
              isSet: user['isClockedIn'] != null,
              icon: Icons.login_rounded,
              readOnly: true,
              onUpdate: (v) => {},
            ),
            _EditableBoolField(
              label: 'Working on Sunday',
              value: _toBool(user['isWorkingOnSunday']),
              isSet: user['isWorkingOnSunday'] != null,
              icon: Icons.calendar_month_rounded,
              onUpdate: (v) => _updateField(uid, 'isWorkingOnSunday', v),
            ),
          ]),
        ],
      ],
    );

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
            Container(width: 4, color: spine),
            Expanded(
              child: InkWell(
                onTap: onToggleExpand,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header (always visible)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 19,
                            backgroundColor: accent.withValues(alpha: 0.14),
                            child: Text(
                              _safeToString(user['userName'], '?').isEmpty
                                  ? '?'
                                  : _safeToString(user['userName'], '?')[0].toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _safeToString(user['userName'], 'Unnamed User'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: nameColor,
                                        ),
                                      ),
                                    ),
                                    if (isPrivileged) ...[
                                      const SizedBox(width: 6),
                                      _tag(theme, 'ADMIN', scheme.tertiary),
                                    ],
                                    if (!isActive) ...[
                                      const SizedBox(width: 6),
                                      _tag(theme, 'INACTIVE', scheme.error),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: _safeToString(user['userRank'], 'Unknown'),
                                        style: TextStyle(
                                          color: accent,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (!isPrivileged && pending > 0)
                                        TextSpan(
                                          text: '   Pending KSh ${_money(pending)}',
                                          style: TextStyle(
                                            color: scheme.error,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                    ],
                                  ),
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          AnimatedRotation(
                            turns: isExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeInOutCubic,
                            child: Icon(Icons.keyboard_arrow_down_rounded, color: scheme.outline),
                          ),
                        ],
                      ),

                      // Expanded body: height and opacity animate together in
                      // both directions, so the content stays visible (and fades)
                      // while the card contracts instead of vanishing first.
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(end: isExpanded ? 1.0 : 0.0),
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeInOutCubic,
                        child: expandedBody,
                        builder: (context, t, child) {
                          if (t == 0) {
                            return const SizedBox(width: double.infinity);
                          }
                          return ClipRect(
                            child: Align(
                              alignment: Alignment.topCenter,
                              heightFactor: t,
                              child: Opacity(
                                opacity: t.clamp(0.0, 1.0),
                                child: child,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(ThemeData theme, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline_rounded, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'No users found',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Users will appear here when added',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoEligibleUsers(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.admin_panel_settings_outlined, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'No eligible users',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Only non-admin users are shown',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String content,
    required String action,
  }) async {
    final theme = Theme.of(context);
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Text(content, style: theme.textTheme.bodyMedium),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ?? false;
  }
}

// ── Row widgets ────────────────────────────────────────────────────────────
// Each is a plain ruled row: icon, label, value, and an affordance on the
// right showing whether it can be edited.

class _RowShell extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget value;
  final Widget trailing;
  final VoidCallback? onTap;

  const _RowShell({
    required this.icon,
    required this.label,
    required this.value,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            value,
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}

Widget _numberValue(BuildContext context, int value, bool isSet) {
  final scheme = Theme.of(context).colorScheme;
  if (!isSet) {
    return Text(
      'Not set',
      style: TextStyle(
        fontSize: 13,
        fontStyle: FontStyle.italic,
        color: scheme.outline,
      ),
    );
  }
  return Text(
    NumberFormat('#,##0').format(value),
    style: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: scheme.onSurface,
    ),
  );
}

class _PendingAmountField extends StatefulWidget {
  final String label;
  final int value;
  final bool isSet;
  final IconData icon;
  final String uid; // Firestore document ID of user
  final Function(int) onValueUpdated; // optional callback if you need it higher up

  const _PendingAmountField({
    required this.label,
    required this.value,
    required this.isSet,
    required this.icon,
    required this.uid,
    required this.onValueUpdated,
  });

  @override
  State<_PendingAmountField> createState() => _PendingAmountFieldState();
}

class _PendingAmountFieldState extends State<_PendingAmountField> {
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(covariant _PendingAmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  Future<void> _showApproveDialog() async {
    final theme = Theme.of(context);
    final controller = TextEditingController(text: _value.toString());

    final int? newValue = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(widget.label, style: theme.textTheme.titleMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the amount you want to approve:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.colorScheme.primary),
                ),
                hintText: '0',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: theme.textTheme.bodyMedium),
          ),
          ElevatedButton(
            onPressed: () {
              final input = int.tryParse(controller.text.trim());
              if (input == null || input <= 0) {
                ToastService.error('Enter a valid positive number to approve');
                return;
              }

              // Ensure we don't go below zero
              final int newPending = (_value - input).clamp(0, _value);

              Navigator.pop(context, newPending);
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (newValue != null && newValue != _value) {
      // Update Firestore
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.uid)
            .update({
          'pendingAmount': newValue,
        });

        // Update UI
        setState(() {
          _value = newValue;
        });

        // Propagate to parent if needed
        widget.onValueUpdated(newValue);
      } catch (e) {
        ToastService.error('Failed to update pending amount: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _RowShell(
      icon: widget.icon,
      label: widget.label,
      onTap: _showApproveDialog,
      value: _value > 0
          ? Text(
              NumberFormat('#,##0').format(_value),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: scheme.error,
              ),
            )
          : _numberValue(context, _value, widget.isSet),
      // Pending is cleared by approving an amount, not typed freely
      trailing: Icon(Icons.price_check_rounded, size: 18, color: scheme.outline),
    );
  }
}

class _EditableNumberField extends StatelessWidget {
  final String label;
  final int value;
  final bool isSet;
  final IconData icon;
  final Function(int) onUpdate;

  const _EditableNumberField({
    required this.label,
    required this.value,
    required this.isSet,
    required this.icon,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _RowShell(
      icon: icon,
      label: label,
      onTap: () => _showEditDialog(context),
      value: _numberValue(context, value, isSet),
      trailing: Icon(Icons.edit_outlined, size: 18, color: scheme.outline),
    );
  }

  void _showEditDialog(BuildContext context) {
    final theme = Theme.of(context);
    final controller = TextEditingController(text: value.toString());
    showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(label, style: theme.textTheme.titleMedium),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.colorScheme.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: theme.textTheme.bodyMedium),
          ),
          ElevatedButton(
            onPressed: () {
              final newValue = int.tryParse(controller.text) ?? value;
              Navigator.pop(context, newValue);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    ).then((newValue) {
      if (newValue != null && newValue != value) {
        onUpdate(newValue);
      }
    });
  }
}

class _EditableBoolField extends StatelessWidget {
  final String label;
  final bool value;
  final bool isSet;
  final IconData icon;
  final bool readOnly;
  final Function(bool) onUpdate;

  const _EditableBoolField({
    required this.label,
    required this.value,
    required this.isSet,
    required this.icon,
    required this.onUpdate,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Auto-managed flag: a status readout with an AUTO tag, not a control.
    if (readOnly) {
      final tone = value ? AppTheme.success : scheme.onSurfaceVariant;
      return _RowShell(
        icon: icon,
        label: label,
        value: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              !isSet ? 'Not set' : (value ? 'Yes' : 'No'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: !isSet ? scheme.outline : tone,
              ),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'AUTO',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return _RowShell(
      icon: icon,
      label: label,
      onTap: () => onUpdate(!value),
      value: Text(
        !isSet ? 'Not set' : (value ? 'On' : 'Off'),
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          fontStyle: isSet ? FontStyle.normal : FontStyle.italic,
          color: !isSet
              ? scheme.outline
              : (value ? AppTheme.success : scheme.onSurfaceVariant),
        ),
      ),
      trailing: SizedBox(
        height: 24,
        child: FittedBox(
          child: Switch(
            value: value,
            onChanged: onUpdate,
          ),
        ),
      ),
    );
  }
}

// Safe conversion helpers (unchanged)
String _safeToString(dynamic value, [String defaultValue = '']) {
  return value?.toString() ?? defaultValue;
}

num _safeNum(dynamic value, [num defaultValue = 0]) {
  if (value == null) return defaultValue;
  return value is num ? value : num.tryParse(value.toString()) ?? defaultValue;
}

bool _toBool(dynamic value) {
  if (value == null) return false;
  return value is bool ? value : value.toString().toLowerCase() == 'true';
}
