import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:billkmotolinkltd/services/notifier.dart';
import 'package:billkmotolinkltd/theme/app_theme.dart';
import 'package:billkmotolinkltd/services/toast_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  DocumentSnapshot<Map<String, dynamic>>? _userDoc;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _events = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _polls = [];
  bool _loading = true;
  String? _error;
  final NotificationService _notificationService = NotificationService();
  final _auth = FirebaseAuth.instance;
  String? _appVersion;
  String? differentialRank;
  double _commissionPercentage = 0.0;
  bool _isEditingCommission = false;
  final TextEditingController _commissionController = TextEditingController();

  bool _showMemoOverlay = false;
  Map<String, dynamic>? _currentMemo;
  Timer? _expiredEventsTimer;

  static const Color _heroTop = Color(0xFF0E5F57);
  static const Color _heroBottom = Color(0xFF06302C);
  static const double _heroExpanded = 250;



  @override
  void initState() {
    super.initState();
    _loadAll();

    // Prompt, automatic cleanup of expired events: runs immediately and
    // then on a recurring timer so events disappear as soon as they
    // expire, without needing a manual refresh or full dashboard reload.
    _cleanupExpiredEvents();
    _expiredEventsTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _cleanupExpiredEvents(),
    );

    // Listen to auth state changes
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        // User logged in - start notification listeners
        _notificationService.onUserLoggedIn();
        uploadDeviceDataToFirestore(user.uid);
      } else {
        // User logged out - stop notification listeners
        _notificationService.onUserLoggedOut();
      }
    });

  }

  Future<void> _updateCommission() async {
    if (!_isEditingCommission) return;

    final newCommission = double.tryParse(_commissionController.text) ?? 0.0;
    
    try {
      await FirebaseFirestore.instance
          .collection('general')
          .doc('general_variables')
          .update({'commissionPercentage': newCommission});
      
      setState(() {
        _commissionPercentage = newCommission;
        _isEditingCommission = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Commission updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating commission: $e')),
        );
      }
    }
  }

  /// Lightweight, read-mostly cleanup that only touches the `events`
  /// collection: deletes anything whose `event_time` has already
  /// passed and refreshes the visible list. Safe to call frequently
  /// (e.g. from a periodic timer) since it does not touch users,
  /// polls, memos, or any other collection, and never writes new
  /// documents — it only deletes documents that are already expired.
  Future<void> _cleanupExpiredEvents() async {
    if (!mounted) return;
    try {
      final now = DateTime.now();
      final eventsSnap = await FirebaseFirestore.instance
          .collection('events')
          .orderBy('event_time', descending: true)
          .get();

      final validEvents = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

      for (final doc in eventsSnap.docs) {
        final data = doc.data();
        final ts = data['event_time'] as Timestamp?;
        if (ts == null) continue;

        if (ts.toDate().isBefore(now)) {
          await doc.reference.delete().catchError((e) {});
        } else {
          validEvents.add(doc);
        }
      }

      if (mounted) {
        setState(() {
          _events = validEvents;
        });
      }
    } catch (e) {
      // Silent: this is a background convenience cleanup, the full
      // _loadAll() call already surfaces errors to the user.
    }
  }

  Future<void> _loadAll() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      final uid = user.uid;

      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!userSnap.exists || !mounted) {
        setState(() => _loading = false);
        return;
      }

      final now = DateTime.now();

      final eventsSnap = await FirebaseFirestore.instance
          .collection('events')
          .orderBy('event_time', descending: true)
          .get();

      final validEvents = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

      for (final doc in eventsSnap.docs) {
        final data = doc.data();
        final ts = data['event_time'] as Timestamp?;

        if (ts == null) continue;

        if (ts.toDate().isBefore(now)) {
          // Expired: remove promptly instead of lingering for a week.
          await doc.reference.delete().catchError((e) {});
        } else {
          validEvents.add(doc);
        }
      }

      final memoRef = FirebaseFirestore.instance.collection('memo').doc('latest');
      final memoSnap = await memoRef.get();
      Map<String, dynamic>? memoData;

      if (memoSnap.exists) {
        final data = memoSnap.data() ?? {};
        final expiresAt = data['expiresAt'] as Timestamp?;

        if (expiresAt != null && expiresAt.toDate().isBefore(now)) {
          await memoRef.delete().catchError((e) {});
        } else {
          memoData = data;
        }
      }

      final userData = userSnap.data() ?? {};
      final userRank = userData['userRank']?.toString() ?? '';

      List<QueryDocumentSnapshot<Map<String, dynamic>>> polls = [];
      if (userRank.isNotEmpty) {
        try {
          final pollsSnap = await FirebaseFirestore.instance
              .collection('polls')
              .orderBy('deadline')
              .get();
          polls = pollsSnap.docs;
        } catch (e) {
          // Ignore poll errors
        }
      }

      final generalSnap = await FirebaseFirestore.instance
          .collection('general')
          .doc('general_variables')
          .get();

      if (generalSnap.exists) {
        final generalData = generalSnap.data() ?? {};
        final commission = (generalData['commissionPercentage'] ?? 0.0) as num;
        _commissionPercentage = commission.toDouble();
        _commissionController.text = _commissionPercentage.toStringAsFixed(1);
      }

      final version = await getCurrentAppVersion();
      _appVersion = version;

      if (mounted) {
        setState(() {
          _userDoc = userSnap;
          _events = validEvents;
          _polls = polls;
          differentialRank = userRank;
          _loading = false;
        });

        if (memoData != null) {
          final readBy = (memoData['readBy'] as List? ?? <String>[]).cast<String>();
          if (!readBy.contains(uid)) {
            setState(() {
              _currentMemo = memoData;
              _showMemoOverlay = true;
            });
          }
        }
      }

      await _notificationService.checkNotificationsManually();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load dashboard: $e';
        });
      }
    }
  }
    
  Future<void> uploadDeviceDataToFirestore(String uid) async {
    try {
      // Check authentication first
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null || uid != user.uid) {
        throw Exception('User not authenticated or UID mismatch');
      }

      // Initialize device info
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      Battery battery = Battery();
      Connectivity connectivity = Connectivity();

      Map<String, dynamic> deviceData = {
        'lastUploadTimestamp': FieldValue.serverTimestamp(),
        'uid': uid,
        'userEmail': user.email,
      };

      // Device hardware/software info - CORRECTED PROPERTIES
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceData.addAll({
          'platform': 'android',
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'brand': androidInfo.brand,
          'deviceId': androidInfo.id,
          'product': androidInfo.product,
          'hardware': androidInfo.hardware,
          'display': androidInfo.display,
          'host': androidInfo.host,
          'osVersion': androidInfo.version.release,
          'apiLevel': androidInfo.version.sdkInt,
          'isPhysicalDevice': androidInfo.isPhysicalDevice,
          'supportedAbis': androidInfo.supportedAbis,
        });
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceData.addAll({
          'platform': 'ios',
          'model': iosInfo.model,
          'name': iosInfo.name,
          'systemName': iosInfo.systemName,
          'systemVersion': iosInfo.systemVersion,
          'localizedModel': iosInfo.localizedModel,
          'utsnameMachine': iosInfo.utsname.machine,
          'isPhysicalDevice': iosInfo.isPhysicalDevice,
        });
      }

      // Battery information
      try {
        deviceData['batteryLevel'] = await battery.batteryLevel;
        BatteryState state = await battery.batteryState;
        // Convert enum to readable string
        switch (state) {
          case BatteryState.full:
            deviceData['batteryState'] = 'Full';
            break;
          case BatteryState.charging:
            deviceData['batteryState'] = 'Charging';
            break;
          case BatteryState.discharging:
            deviceData['batteryState'] = 'Discharging';
            break;
          case BatteryState.unknown:
            deviceData['batteryState'] = 'Unknown';
            break;
          case BatteryState.connectedNotCharging:
            deviceData['batteryState'] = 'Connected (Not Charging)';
            break;
        }
      } catch (e) {
        deviceData['batteryLevel'] = null;
        deviceData['batteryState'] = 'Error';
        deviceData['batteryError'] = e.toString();
      }


      // Network connectivity - FIXED for new connectivity_plus API
      try {
        List<ConnectivityResult> results = await connectivity.checkConnectivity();
        
        // Take first result or prioritize (WiFi > Mobile > Other)
        ConnectivityResult primaryResult = ConnectivityResult.none;
        if (results.contains(ConnectivityResult.wifi)) {
          primaryResult = ConnectivityResult.wifi;
        } else if (results.contains(ConnectivityResult.mobile)) {
          primaryResult = ConnectivityResult.mobile;
        } else if (results.isNotEmpty) {
          primaryResult = results.first;
        }
        
        // Convert to readable string
        switch (primaryResult) {
          case ConnectivityResult.wifi:
            deviceData['networkType'] = 'WiFi';
            break;
          case ConnectivityResult.mobile:
            deviceData['networkType'] = 'Mobile Data';
            break;
          case ConnectivityResult.ethernet:
            deviceData['networkType'] = 'Ethernet';
            break;
          case ConnectivityResult.vpn:
            deviceData['networkType'] = 'VPN';
            break;
          case ConnectivityResult.bluetooth:
            deviceData['networkType'] = 'Bluetooth';
            break;
          case ConnectivityResult.other:
            deviceData['networkType'] = 'Other';
            break;
          case ConnectivityResult.none:
            deviceData['networkType'] = 'Offline';
            break;
        }
      } catch (e) {
        deviceData['networkType'] = 'Unknown';
      }

      // Screen information (Flutter 3+ compatible)
      final window = WidgetsBinding.instance.window;
      final mediaQuery = MediaQueryData.fromView(window);
      deviceData.addAll({
        'screenWidth': mediaQuery.size.width,
        'screenHeight': mediaQuery.size.height,
        'pixelRatio': mediaQuery.devicePixelRatio,
        'screenPadding': {
          'top': mediaQuery.padding.top,
          'bottom': mediaQuery.padding.bottom,
          'left': mediaQuery.padding.left,
          'right': mediaQuery.padding.right,
        },
      });

      // Update as a map in users/{uid}/device_info document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
            'device_info': deviceData,
            'appVersion': _appVersion,
          }, SetOptions(merge: true));

    } catch (e) {
      rethrow;
    }
  }

  Future<String> getCurrentAppVersion() async {
    WidgetsFlutterBinding.ensureInitialized(); // Required before runApp()
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version; // e.g., "1.0.1"
  }

  Future<void> _markAsRead(String uid) async {
    try {
      await FirebaseFirestore.instance
          .collection('memo')
          .doc('latest')
          .update({
        'readBy': FieldValue.arrayUnion([uid]),
      });
      
      setState(() {
        _showMemoOverlay = false;
        _currentMemo = null;
      });
      
      ToastService.success("Memo marked as read!");
    } catch (e) {
      ToastService.error("Failed to mark memo as read: $e");
    }
  }

  Widget _buildMemoOverlay(ThemeData theme, Map<String, dynamic> memoData) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final department = (memoData['department'] ?? '').toString();
    final to = (memoData['to'] ?? 'All Staff').toString();
    final from = (memoData['from'] ?? 'Unknown').toString();
    final title = (memoData['title'] ?? '').toString();
    final body = (memoData['body'] ?? '').toString();

    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() {
                _showMemoOverlay = false;
                _currentMemo = null;
              }),
              child: const SizedBox.expand(),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700, maxHeight: 760),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 40,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Container(
                              height: 8,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    theme.colorScheme.primary,
                                    theme.colorScheme.secondary,
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      Icons.campaign_rounded,
                                      color: theme.colorScheme.primary,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Memo',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          to,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => setState(() {
                                      _showMemoOverlay = false;
                                      _currentMemo = null;
                                    }),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (department.isNotEmpty) ...[
                                      _pill(theme, department, theme.colorScheme.primary),
                                      const SizedBox(height: 16),
                                    ],
                                    Text(
                                      title,
                                      style: theme.textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: Text(
                                        body,
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          height: 1.7,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.person_2_rounded,
                                          size: 18,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            from,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: theme.colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 22),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 54,
                                      child: FilledButton.icon(
                                        onPressed: () => _markAsRead(uid),
                                        icon: const Icon(Icons.mark_chat_read_rounded),
                                        label: const Text('Mark as Read'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(ThemeData theme, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(
          child: CircularProgressIndicator(
            color: theme.colorScheme.primary,
            strokeWidth: 3,
            backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red.withValues(alpha: 0.1), Colors.red.withValues(alpha: 0.05)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.3),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.error_outline_rounded,
                    color: Colors.red[600],
                    size: 64,
                    shadows: const [
                      Shadow(color: Colors.red, offset: Offset(0, 4), blurRadius: 8),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _error!,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _loadAll,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                    shadowColor: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Safe user data access
    final userData = _userDoc?.data() ?? {};
    final userName = userData['userName']?.toString() ?? 'User';
    final userRank = userData['userRank']?.toString() ?? 'User';

    final now = DateTime.now();
    final hour = now.hour;
    String greeting = _getGreeting(hour);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadAll,
            color: theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surface,
            child: CustomScrollView(
              slivers: [
                // Hero: flat brand gradient, greeting + name, collapses to a slim bar
                SliverAppBar(
                  expandedHeight: _heroExpanded,
                  floating: true,
                  snap: true,
                  pinned: true,
                  collapsedHeight: kToolbarHeight,
                  automaticallyImplyLeading: false,
                  backgroundColor: _heroBottom,
                  surfaceTintColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  flexibleSpace: LayoutBuilder(
                    builder: (context, constraints) {
                      final t = ((_heroExpanded - constraints.maxHeight) /
                              (_heroExpanded - kToolbarHeight))
                          .clamp(0.0, 1.0);
                      final expandedOpacity = (1 - t * 1.8).clamp(0.0, 1.0);
                      final collapsedOpacity = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
                      final verified = _toBool(userData['isVerified']);

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [_heroTop, _heroBottom],
                              ),
                            ),
                          ),
                          Positioned(
                            top: -50,
                            right: -40,
                            child: Container(
                              width: 190,
                              height: 190,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.05 * expandedOpacity),
                              ),
                            ),
                          ),

                          // Expanded content
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 32,
                            child: Opacity(
                              opacity: expandedOpacity,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Hero(
                                    tag: 'user_avatar',
                                    child: Container(
                                      width: 76,
                                      height: 76,
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withValues(alpha: 0.22),
                                      ),
                                      child: CircleAvatar(
                                        backgroundColor: theme.colorScheme.primaryContainer,
                                        child: Text(
                                          userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                                          style: TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w800,
                                            color: theme.colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    greeting,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.72),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            userName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 24,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Icon(
                                          verified ? Icons.verified_rounded : Icons.warning_amber_rounded,
                                          size: 19,
                                          color: verified ? const Color(0xFF7CE7C8) : const Color(0xFFFFC857),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      userRank.toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Collapsed: just the name
                          Positioned(
                            left: 20,
                            right: 20,
                            top: 0,
                            height: kToolbarHeight,
                            child: Opacity(
                              opacity: collapsedOpacity,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '$greeting, ${userName.split(' ').first}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Rounded lip into the page
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: -1,
                            child: Opacity(
                              opacity: 1 - t,
                              child: Container(
                                height: 22,
                                decoration: BoxDecoration(
                                  color: theme.scaffoldBackgroundColor,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // CONTENT
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    child: Column(
                      children: [
                        // Events Section
                        if (_events.isNotEmpty) ...[
                          _buildEventsSection(theme),
                          const SizedBox(height: 20),
                        ],

                        // Polls Section
                        if (_polls.isNotEmpty) ...[
                          _buildPollsSection(theme),
                          const SizedBox(height: 20),
                        ],

                        // Stats Cards
                        _buildStatsCards(theme, userData),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_showMemoOverlay && _currentMemo != null)
            Positioned.fill(
              child: _buildMemoOverlay(theme, _currentMemo!),
            ),
        ],
      ),
    );


  }

  // HELPER
  String _getGreeting(int hour) {
    if (hour >= 5 && hour < 12) return 'Good Morning';
    if (hour >= 12 && hour < 17) return 'Good Afternoon';
    if (hour >= 17 && hour < 21) return 'Good Evening';
    return 'Good Night';
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// Flat card that stacks rows separated by hairlines.
  Widget _ruledCard(ThemeData theme, List<Widget> rows) {
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
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

  Widget _buildEventsSection(ThemeData theme) {
    final scheme = theme.colorScheme;
    final rows = <Widget>[];

    for (final doc in _events) {
      final data = doc.data();
      final ts = data['event_time'] as Timestamp?;
      if (ts == null) continue;

      final dt = ts.toDate();
      final isFuture = dt.isAfter(DateTime.now());
      final accent = isFuture ? scheme.primary : scheme.outline;

      rows.add(
        InkWell(
          onTap: () => _showEventDetails(context, doc, theme),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Date block
                SizedBox(
                  width: 44,
                  child: Column(
                    children: [
                      Text(
                        DateFormat('dd').format(dt),
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                          color: accent,
                        ),
                      ),
                      Text(
                        DateFormat('MMM').format(dt).toUpperCase(),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: scheme.outlineVariant,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['title']?.toString() ?? 'No Title',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data['description']?.toString() ?? 'No description',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      DateFormat('HH:mm').format(dt),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(theme, 'Upcoming events (${_events.length})'),
        _ruledCard(theme, rows),
      ],
    );
  }

  // Add this method to your _DashboardState class
  void _showEventDetails(BuildContext context, QueryDocumentSnapshot doc, ThemeData theme) {
    final data = doc.data() as Map<String, dynamic>;
    final ts = data['event_time'] as Timestamp?;
    final dt = ts?.toDate() ?? DateTime.now();
    final isFuture = dt.isAfter(DateTime.now());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isFuture ? AppTheme.success : theme.colorScheme.outline,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isFuture ? Icons.schedule : Icons.history,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                data['title']?.toString() ?? 'Event Details',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Date/Time
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('EEEE, dd MMMM yyyy').format(dt),
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          DateFormat('HH:mm').format(dt),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              // Full Description
              Text(
                'Description',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                data['description']?.toString() ?? 'No description available',
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildPollsSection(ThemeData theme) {
    final scheme = theme.colorScheme;
    final rows = <Widget>[];

    for (final doc in _polls) {
      final data = doc.data();
      final deadlineTs = data['deadline'] as Timestamp?;
      if (deadlineTs == null) continue;

      final deadline = deadlineTs.toDate();
      final expired = deadline.isBefore(DateTime.now());
      final tone = expired ? scheme.error : AppTheme.success;

      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['title']?.toString() ?? 'No Title',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Deadline: ${DateFormat('dd MMM yyyy').format(deadline)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  expired ? 'CLOSED' : 'OPEN',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: tone,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(theme, 'Polls (${_polls.length})'),
        _ruledCard(theme, rows),
      ],
    );
  }

  String _formatHours(Map<String, dynamic> user) {
    final isClockedIn = _toBool(user['isClockedIn']);
    if (!isClockedIn) return 'Unavailable';
    
    final clockInTime = user['clockInTime'] as Timestamp?;
    if (clockInTime == null) return 'Unavailable';
    
    final now = DateTime.now();
    final clockInDate = clockInTime.toDate();
    final hours = now.difference(clockInDate).inHours;
    final minutes = now.difference(clockInDate).inMinutes.remainder(60);
    
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  Widget _buildStatsCards(ThemeData theme, Map<String, dynamic> user) {
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    final String rank = user['userRank']?.toString() ?? '';

    // 2. Admin Check
    if (rank == 'CEO' || rank == 'Systems, IT' || rank == 'Manager') {
      return _buildAdminDashboard(theme);
    }

    final pending = user['pendingAmount'];
    final pendingNum = pending is num ? pending : num.tryParse('${pending ?? 0}') ?? 0;

    // (label, value, optional emphasis colour)
    final List<List<dynamic>> figures = [
      ['Daily Target', _formatNumber(user['dailyTarget']), null],
      ['Sunday Target', _formatNumber(user['sundayTarget']), null],
      ['Pending Amount', _formatNumber(user['pendingAmount']), pendingNum > 0 ? scheme.error : null],
      ['In-App Balance', _formatNumber(user['currentInAppBalance']), scheme.primary],
      ['Bike', (user['currentBike'] ?? 'N/A').toString(), null],
      ['Hours', _formatHours(user), null],
    ];

    Widget cell(List<dynamic> f, {required bool right}) {
      final Color? emphasis = f[2] as Color?;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            border: right
                ? Border(left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                f[0] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  f[1] as String,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: emphasis ?? scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final figureRows = <Widget>[
      for (int i = 0; i < figures.length; i += 2)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cell(figures[i], right: false),
              cell(figures[i + 1], right: true),
            ],
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAssignedBikeBanner(theme, user, isDark),
        const SizedBox(height: 20),

        _sectionLabel(theme, 'Your numbers'),
        _ruledCard(theme, figureRows),
        const SizedBox(height: 20),

        _sectionLabel(theme, 'Status'),
        _buildStatusRow(theme, user, isDark),
      ],
    );
  }

  Widget _buildAssignedBikeBanner(ThemeData theme, Map<String, dynamic> user, bool isDark) {
    final scheme = theme.colorScheme;
    final String? bikeName = (user['assignedBikeName'] as String?)?.trim().isEmpty ?? true
        ? null
        : user['assignedBikeName'] as String;
    final bool hasBike = bikeName != null;

    // 'day' | 'night' | null (not set - e.g. assigned before shifts existed)
    final String? rawShift = (user['assignedShift'] as String?)?.trim().toLowerCase();
    final String? shift = (rawShift == 'day' || rawShift == 'night') ? rawShift : null;

    final Color spine = hasBike ? scheme.primary : scheme.error;

    return Container(
      width: double.infinity,
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasBike ? 'YOUR ASSIGNED BIKE' : 'NO BIKE ASSIGNED',
                            style: TextStyle(
                              color: hasBike ? scheme.primary : scheme.error,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            bikeName ?? 'Contact your admin to get a bike assigned',
                            style: (hasBike
                                    ? theme.textTheme.headlineSmall
                                    : theme.textTheme.titleMedium)
                                ?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (hasBike) ...[
                            const SizedBox(height: 10),
                            _buildShiftPill(shift, theme, isDark),
                            const SizedBox(height: 8),
                            Text(
                              shift == null
                                  ? 'Ask your admin to set your shift'
                                  : 'Use this bike when you clock in',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: spine.withValues(alpha: isDark ? 0.18 : 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        hasBike ? Icons.electric_bike_rounded : Icons.report_gmailerrorred_rounded,
                        color: spine,
                        size: 28,
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

  Widget _buildShiftPill(String? shift, ThemeData theme, bool isDark) {
    final scheme = theme.colorScheme;
    final bool isSet = shift != null;
    final bool isNight = shift == 'night';

    final Color tone = !isSet
        ? scheme.outline
        : (isNight ? scheme.tertiary : AppTheme.warning);
    final IconData icon = !isSet
        ? Icons.help_outline_rounded
        : (isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded);
    final String label = !isSet ? 'SHIFT NOT SET' : (isNight ? 'NIGHT SHIFT' : 'DAY SHIFT');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: tone,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminDashboard(ThemeData theme) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('general')
          .doc('general_variables')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        return SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPerformanceSection(data['monthly_incomes'] ?? {}, theme, true),
              const SizedBox(height: 12),
              _buildPerformanceSection(data['annual_incomes'] ?? {}, theme, false),
              const SizedBox(height: 12),
              _buildSystemOverview(data, theme),
            ],
          ),
        );
      },
    );
  }

  DateTime _getLatestDate(Map<String, dynamic> riderGroup) {
    DateTime latest = DateTime(2000);
    riderGroup.forEach((_, data) {
      final stamp = data['dateAppended'];
      if (stamp is Timestamp) {
        final date = stamp.toDate();
        if (date.isAfter(latest)) latest = date;
      }
    });
    return latest;
  }

  List<MapEntry<String, Map<String, dynamic>>> _sortIncomeData(Map<String, dynamic> source) {
    final sortedKeys = source.keys.toList()
      ..sort((a, b) {
        final dataA = source[a] as Map<String, dynamic>;
        final dataB = source[b] as Map<String, dynamic>;
        final dateA = _getLatestDate(dataA);
        final dateB = _getLatestDate(dataB);
        return dateB.compareTo(dateA);
      });
    return sortedKeys.map((key) => MapEntry(key, source[key] as Map<String, dynamic>)).toList();
  }

  Widget _buildPerformanceSection(
    Map<String, dynamic> source,
    ThemeData theme,
    bool isMonthly,
  ) {
    if (source.isEmpty) {
      return _buildEmptyState(
        isMonthly ? 'No monthly data' : 'No annual data',
        Icons.analytics_outlined,
      );
    }

    final sortedEntries = _sortIncomeData(source);
    
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCompactSectionHeader(
              title: isMonthly ? 'Monthly Income' : 'Annual Income',
              subtitle: isMonthly ? 'Chronological monthly performance' : 'Yearly performance',
              icon: isMonthly ? Icons.calendar_month : Icons.assessment,
              accentColor: isMonthly ? Colors.blue : Colors.deepPurple,
              theme: theme,
            ),
            const SizedBox(height: 8),
            ...sortedEntries.map((entry) => _buildIncomeExpansionTile(entry, theme)),
          ],
        ),
      ),
    );
  }

  Totals _calculateRiderTotals(Map<String, dynamic> ridersMap) {
    double totalGross = 0, totalNet = 0, totalExp = 0;
    ridersMap.forEach((_, riderData) {
      totalGross += (riderData['gross'] ?? 0).toDouble();
      totalNet += (riderData['net'] ?? 0).toDouble();
      totalExp += (riderData['expenses'] ?? 0).toDouble();
    });
    return Totals(totalGross, totalNet, totalExp);
  }

  Widget _buildIncomeExpansionTile(MapEntry<String, Map<String, dynamic>> entry, ThemeData theme) {
    final ridersMap = entry.value;
    final totals = _calculateRiderTotals(ridersMap);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  entry.key.replaceAll('_', ' ').trim(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              _buildCompactChip(totals.totalGross, Colors.green),
              const SizedBox(width: 6),
              _buildCompactChip(totals.totalNet, Colors.blue),
            ],
          ),
          children: [
            ...ridersMap.entries.map((riderEntry) => _buildCompactRiderTile(riderEntry, theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactRiderTile(MapEntry<String, dynamic> riderEntry, ThemeData theme) {
    final riderData = riderEntry.value as Map<String, dynamic>;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 2),
        minLeadingWidth: 40,
        leading: CircleAvatar(
          radius: 16, // Smaller avatar
          backgroundColor: theme.primaryColor.withValues(alpha: 0.2),
          child: Text(
            riderEntry.key.substring(0, 1).toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          riderEntry.key,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          "Exp: ${_formatNumber(riderData['expenses'])}",
          style: theme.textTheme.bodySmall,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "G: ${_formatNumber(riderData['gross'])}",
              style: TextStyle(
                color: Colors.green[600],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              "N: ${_formatNumber(riderData['net'])}",
              style: TextStyle(
                color: Colors.blue[600],
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemOverview(Map<String, dynamic> data, ThemeData theme) {
    final bikes = data['bikes'] as Map<String, dynamic>? ?? {};
    
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCompactSectionHeader(
              title: 'System Overview',
              subtitle: 'General app stats and controls',
              icon: Icons.settings_suggest,
              accentColor: Colors.teal,
              theme: theme,
            ),
            const SizedBox(height: 10),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.of(context).size.width > 700 ? 2 : 1,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.6,
              children: [
                _buildCompactMetricCard(
                  'Bikes',
                  bikes.length.toString(),
                  Icons.pedal_bike,
                  Colors.indigo,
                ),
                _buildCompactCommissionCard(theme),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            _buildCompactSectionHeader(
              title: 'Bike Status',
              subtitle: 'Current condition and availability',
              icon: Icons.directions_bike,
              accentColor: Colors.green,
              theme: theme,
            ),
            const SizedBox(height: 12),

            ...bikes.entries.map((bikeEntry) => _buildCompactBikeTile(bikeEntry, theme)),
          ]
        ),
      ),
    );
  }

  Widget _buildCompactCommissionCard(ThemeData theme) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isEditingCommission ? theme.primaryColor : theme.dividerColor,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _isEditingCommission ? null : () => setState(() => _isEditingCommission = true),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.percent, color: Colors.green[600], size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Commission',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (_isEditingCommission)
                        SizedBox(
                          width: double.infinity,
                          child: TextField(
                            controller: _commissionController,
                            keyboardType: TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              hintText: '0.0%',
                              hintStyle: const TextStyle(fontSize: 16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: theme.primaryColor.withValues(alpha: 0.3)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.left,
                            onSubmitted: (_) => _updateCommission(),
                          ),
                        )
                      else
                        Text(
                          '${_commissionPercentage.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_isEditingCommission) ...[
                  IconButton(
                    onPressed: _updateCommission,
                    icon: const Icon(Icons.check, color: Colors.green, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isEditingCommission = false;
                        _commissionController.text = _commissionPercentage.toStringAsFixed(1);
                      });
                    },
                    icon: const Icon(Icons.close, color: Colors.red, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ] else
                  Icon(Icons.edit, 
                  size: 18, 
                  color: theme.brightness == Brightness.dark 
                      ? Colors.white70 
                      : theme.primaryColor)
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactMetricCard(String label, String value, IconData icon, Color color) {
    return Card(
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  /// One bike, two shift slots (day / night). Each slot shows its rider and
  /// can be dropped on its own by tapping it.
  Widget _buildCompactBikeTile(MapEntry<String, dynamic> bikeEntry, ThemeData theme) {
    final bikeId = bikeEntry.key;
    final bikeInfo = bikeEntry.value is Map
        ? Map<String, dynamic>.from(bikeEntry.value as Map)
        : <String, dynamic>{};

    // Read each shift slot: bikes.<bike>.day / bikes.<bike>.night
    bool slotAssigned(String shift) {
      final slot = bikeInfo[shift];
      return slot is Map && slot['isAssigned'] == true;
    }

    String slotRider(String shift) {
      final slot = bikeInfo[shift];
      if (slot is! Map) return 'None';
      final rider = slot['assignedRider']?.toString();
      return (rider == null || rider.isEmpty) ? 'None' : rider;
    }

    final int assignedCount =
        ['day', 'night'].where((s) => slotAssigned(s)).length;

    // green = both shifts staffed, orange = one, red = none
    final Color tint = assignedCount == 2
        ? Colors.green
        : (assignedCount == 1 ? Colors.orange : Colors.red);

    Widget shiftRow(String shift) {
      final isAssigned = slotAssigned(shift);
      final riderName = slotRider(shift);
      final isNight = shift == 'night';

      return InkWell(
        onTap: isAssigned
            ? () => _showDropBikeDialog(context, bikeId, riderName, shift)
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isAssigned ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                size: 14,
                color: isNight ? Colors.indigo[400] : Colors.amber[800],
              ),
              const SizedBox(width: 6),
              Text(
                isNight ? 'Night' : 'Day',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  riderName,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: tint.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bikeId,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 4),
          shiftRow('day'),
          shiftRow('night'),
        ],
      ),
    );
  }
    
  void _showDropBikeDialog(BuildContext context, String bikeId, String riderName, String shift) {
    final shiftLabel = shift == 'night' ? 'Night' : 'Day';
    final localTheme = Theme.of(context);
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: Icon(
            Icons.bike_scooter,
            color: localTheme.colorScheme.error,
            size: 48,
          ),
          title: Text(
            'Drop this bike?',
            style: localTheme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Are you sure you want to unassign',
                style: localTheme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                bikeId,
                style: localTheme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: localTheme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'from $riderName ($shiftLabel shift)?',
                style: localTheme.textTheme.bodyMedium,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancel',
                style: localTheme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: localTheme.colorScheme.error,
                backgroundColor: localTheme.colorScheme.errorContainer.withOpacity(0.1),
              ),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                
                try {
                  await FirebaseFirestore.instance
                      .collection('general')
                      .doc('general_variables')
                      .update({
                    'bikes.$bikeId.$shift.isAssigned': false,
                    'bikes.$bikeId.$shift.assignedRider': 'None',
                  });

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Bike $bikeId ($shiftLabel shift) successfully dropped.'),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to drop bike: $e'),
                        backgroundColor: localTheme.colorScheme.error,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: localTheme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Confirm',
                    style: localTheme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          actionsPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }

  Widget _buildCompactSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required ThemeData theme,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactChip(double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _formatNumber(amount),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(icon, size: 32, color: Colors.grey),
            const SizedBox(width: 16),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 14, color: Colors.grey))),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(ThemeData theme, Map<String, dynamic> user, bool isDark) {
    final scheme = theme.colorScheme;
    final statuses = [
      {'label': 'Clocked In', 'value': _toBool(user['isClockedIn']), 'icon': Icons.access_time_filled},
      {'label': 'Charging', 'value': _toBool(user['isCharging']), 'icon': Icons.battery_charging_full_rounded},
      {'label': 'Active', 'value': _toBool(user['isActive']), 'icon': Icons.power_settings_new_rounded},
      {'label': 'Verified', 'value': _toBool(user['isVerified']), 'icon': Icons.verified_rounded},
      {'label': 'Sunday', 'value': _toBool(user['isWorkingOnSunday']), 'icon': Icons.calendar_month_rounded},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: statuses.map((status) {
        final isActive = status['value'] as bool;
        final Color tone = isActive ? scheme.primary : scheme.onSurfaceVariant;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isActive
                ? scheme.primary.withValues(alpha: isDark ? 0.18 : 0.10)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? scheme.primary.withValues(alpha: 0.35) : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(status['icon'] as IconData, size: 15, color: tone),
              const SizedBox(width: 7),
              Text(
                status['label'] as String,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: tone,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  bool _toBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    return value.toString().toLowerCase() == 'true';
  }

  String _formatNumber(dynamic value) {
    if (value == null) return 'KSh 0';
    final numValue = value is num ? value : num.tryParse(value.toString()) ?? 0;
    
    if (numValue >= 1000000) {
      return 'KSh ${(numValue / 1000000).toStringAsFixed(1)}M';
    }
    
    // ✅ ALWAYS show full number with commas - no K rounding
    final formatter = NumberFormat('#,##0');
    return 'KSh ${formatter.format(numValue.toInt())}';
  }

  @override
  void dispose() {
    _expiredEventsTimer?.cancel();
    _notificationService.dispose();
    _commissionController.dispose();
    super.dispose();
  }
}

class Totals {
  final double totalGross;
  final double totalNet;
  final double totalExpenses;
  Totals(this.totalGross, this.totalNet, this.totalExpenses);
}