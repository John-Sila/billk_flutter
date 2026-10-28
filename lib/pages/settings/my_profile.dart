import 'package:billkmotolinkltd/services/toast_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/firebase_global.dart';
import 'package:intl/intl.dart';

class MyProfile extends StatelessWidget {
  const MyProfile({super.key});

  Future<void> applyLeave() async {
    ToastService.warning("Leave application feature is under maintenance...");
  }

  Future<void> changeProfilePhoto() async {
    ToastService.warning("Profile photo change feature is under maintenance...");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: FutureBuilder<Map<String, dynamic>?>(
        future: FirebaseService.fetchUserData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingView();
          }

          if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
            return _ErrorView(error: snapshot.error?.toString());
          }

          final userData = snapshot.data!;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            // The hero is always dark, so keep status-bar icons light while
            // this page is open.
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: Colors.transparent,
            ),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                _ProfileAppBar(userData: userData),
                SliverToBoxAdapter(
                  child: _ProfileBody(
                    userData: userData,
                    onChangePhoto: changeProfilePhoto,
                    onApplyLeave: applyLeave,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Role helpers shared by the hero and the body.
bool _isCeo(Map<String, dynamic> d) =>
    d['userRank']?.toString().toLowerCase() == 'ceo';
bool _isRider(Map<String, dynamic> d) =>
    d['userRank']?.toString().toLowerCase() == 'rider';

// ── Loading ─────────────────────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(strokeWidth: 2.5, color: scheme.primary),
          const SizedBox(height: 16),
          Text(
            'Loading profile...',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error ───────────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String? error;
  const _ErrorView({this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person_off_rounded, size: 36, color: scheme.error),
              ),
              const SizedBox(height: 20),
              Text(
                'Could not load profile',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                error ?? 'No data available',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero (runs edge-to-edge under the status bar) ────────────────────────────
class _ProfileAppBar extends StatelessWidget {
  final Map<String, dynamic> userData;
  const _ProfileAppBar({required this.userData});

  static const Color _heroTop = Color(0xFF0E5F57);
  static const Color _heroBottom = Color(0xFF06302C);

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final profilePic = userData['pfp_url'] ??
        'https://img.icons8.com/liquid-glass-color/1200/user-male-circle.jpg';
    final isActive = userData['isActive'] ?? false;
    final name = (userData['userName'] ?? 'Profile').toString();
    final rank = (userData['userRank'] ?? '').toString();

    const collapsedBody = kToolbarHeight;
    final expandedHeight = topInset + 270;

    return SliverAppBar(
      pinned: true,
      expandedHeight: expandedHeight,
      backgroundColor: _heroBottom,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final minExtent = topInset + collapsedBody;
          final t = ((expandedHeight - constraints.maxHeight) /
                  (expandedHeight - minExtent))
              .clamp(0.0, 1.0);
          final expandedOpacity = (1 - t * 1.8).clamp(0.0, 1.0);
          final collapsedOpacity = ((t - 0.6) / 0.4).clamp(0.0, 1.0);

          return Stack(
            fit: StackFit.expand,
            children: [
              // Brand gradient, reaching all the way up behind the status bar
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_heroTop, _heroBottom],
                  ),
                ),
              ),

              // Soft decorative rings
              Positioned(
                top: -60,
                right: -50,
                child: _Ring(size: 220, opacity: 0.06 * expandedOpacity),
              ),
              Positioned(
                top: topInset + 70,
                left: -70,
                child: _Ring(size: 160, opacity: 0.05 * expandedOpacity),
              ),

              // Expanded: avatar, name, rank
              Positioned(
                left: 0,
                right: 0,
                bottom: 34,
                child: Opacity(
                  opacity: expandedOpacity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Avatar(profilePic: profilePic, isActive: isActive),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      if (rank.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            rank.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Collapsed: compact name in the pinned bar
              Positioned(
                left: 56,
                right: 16,
                top: topInset,
                height: collapsedBody,
                child: Opacity(
                  opacity: collapsedOpacity,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              ),

              // Rounded lip where the hero meets the page
              Positioned(
                left: 0,
                right: 0,
                bottom: -1,
                child: Opacity(
                  opacity: 1 - t,
                  child: Container(
                    height: 24,
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final double size;
  final double opacity;
  const _Ring({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String profilePic;
  final bool isActive;
  const _Avatar({required this.profilePic, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        children: [
          Container(
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.network(
                profilePic,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.white24,
                  child: const Icon(Icons.person_rounded, color: Colors.white, size: 44),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 3,
            right: 3,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF22C55E) : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: _ProfileAppBar._heroBottom, width: 3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────
class _ProfileBody extends StatelessWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onChangePhoto;
  final VoidCallback onApplyLeave;

  const _ProfileBody({
    required this.userData,
    required this.onChangePhoto,
    required this.onApplyLeave,
  });

  String _str(dynamic v, [String fallback = 'N/A']) =>
      v == null ? fallback : v.toString();

  String _formatNumber(dynamic value) {
    if (value == null) return 'KSh 0';
    final n = value is num ? value : num.tryParse(value.toString()) ?? 0;
    if (n >= 1000000) return 'KSh ${(n / 1000000).toStringAsFixed(1)}M';
    return 'KSh ${NumberFormat('#,##0').format(n.toInt())}';
  }

  String _formatCurrency(dynamic value) {
    if (value == null) return 'Ksh 0';
    final n = value is num ? value : double.tryParse(value.toString()) ?? 0.0;
    return 'Ksh ${NumberFormat('#,##0').format(n.toInt())}';
  }

  @override
  Widget build(BuildContext context) {
    final isCeo = _isCeo(userData);
    final isRider = _isRider(userData);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        4,
        12,
        28 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rider-only: targets and last result
          if (isRider) ...[
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Daily Target',
                    value: _formatNumber(userData['dailyTarget']),
                    icon: Icons.flag_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    label: 'Previous Net',
                    value: _formatNumber(userData['netClockedLastly']),
                    icon: Icons.trending_up_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Actions: leave does not apply to the CEO
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Change Photo',
                  icon: Icons.photo_camera_rounded,
                  onTap: onChangePhoto,
                ),
              ),
              if (!isCeo) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    label: 'Apply Leave',
                    icon: Icons.event_busy_rounded,
                    onTap: onApplyLeave,
                    filled: true,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 24),
          const _SectionHeader(title: 'Profile Details'),
          _InfoGroup(
            items: [
              _InfoRow(icon: Icons.person_rounded, label: 'Name', value: _str(userData['userName'])),
              _InfoRow(icon: Icons.badge_rounded, label: 'Role', value: _str(userData['userRank'])),
              _InfoRow(icon: Icons.phone_rounded, label: 'Phone', value: _str(userData['phoneNumber'])),
              _InfoRow(icon: Icons.email_rounded, label: 'Email', value: _str(userData['email'])),
              _InfoRow(icon: Icons.credit_card_rounded, label: 'ID Number', value: _str(userData['idNumber'])),
              _InfoRow(icon: Icons.wc_rounded, label: 'Gender', value: _str(userData['gender'])),
            ],
          ),

          // Rider-only work details
          if (isRider) ...[
            const SizedBox(height: 22),
            const _SectionHeader(title: 'Work'),
            _InfoGroup(
              items: [
                _InfoRow(icon: Icons.directions_bike_rounded, label: 'Current Bike', value: _str(userData['currentBike'], 'None')),
                _InfoRow(icon: Icons.account_balance_wallet_rounded, label: 'Balance', value: _formatCurrency(userData['currentInAppBalance'])),
                _InfoRow(icon: Icons.notifications_rounded, label: 'Notifications', value: _str(userData['numberOfNotifications'], '0')),
              ],
            ),
          ] else ...[
            const SizedBox(height: 22),
            const _SectionHeader(title: 'Account'),
            _InfoGroup(
              items: [
                _InfoRow(icon: Icons.notifications_rounded, label: 'Notifications', value: _str(userData['numberOfNotifications'], '0')),
              ],
            ),
          ],

          const SizedBox(height: 22),
          const _SectionHeader(title: 'Status'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(label: 'Verified', active: userData['isVerified'] ?? false, icon: Icons.verified_rounded),
              _StatusChip(label: 'Active', active: userData['isActive'] ?? false, icon: Icons.circle),
              // Shift and charging state only mean something for riders
              if (isRider) ...[
                _StatusChip(label: 'Clocked In', active: userData['isClockedIn'] ?? false, icon: Icons.access_time_rounded),
                _StatusChip(label: 'Charging', active: userData['isCharging'] ?? false, icon: Icons.battery_charging_full_rounded),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _InfoRow {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});
}

class _InfoGroup extends StatelessWidget {
  final List<_InfoRow> items;
  const _InfoGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: List.generate(items.length, (i) {
          final item = items[i];
          final isLast = i == items.length - 1;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(item.icon, color: scheme.primary, size: 19),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 84,
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.value,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 47,
                  color: scheme.outlineVariant.withValues(alpha: 0.7),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.primary, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Leave is a quieter destructive-ish action: tinted red, not shouting.
    final color = filled ? scheme.error : scheme.primary;
    return Material(
      color: color.withValues(alpha: filled ? 0.10 : 0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool active;
  final IconData icon;

  const _StatusChip({required this.label, required this.active, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? const Color(0xFF16A34A) : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class StatsItem {
  final String title;
  final String value;
  const StatsItem(this.title, this.value);
}

class StatusItem {
  final String title;
  final bool isActive;
  final IconData icon;
  const StatusItem(this.title, this.isActive, this.icon);
}
