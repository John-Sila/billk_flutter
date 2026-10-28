import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Branded launcher screen. Used at cold start, while the session is
/// restored, and while the app version is checked, so the user never sees a
/// blank frame. Fixed brand colours (not theme-dependent) so it looks the
/// same in light and dark mode and matches the logo.
class SplashScreen extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const SplashScreen({super.key, this.message, this.onRetry});

  static const Color _top = Color(0xFF0E5F57);
  static const Color _bottom = Color(0xFF06302C);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bottom,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_top, _bottom],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 5),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 112,
                      height: 112,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 112,
                        height: 112,
                        color: Colors.white.withValues(alpha: 0.12),
                        child: const Icon(Icons.electric_bike_rounded,
                            color: Colors.white, size: 56),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                const Text(
                  'BILLK MOTOLINK',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'LTD',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 4,
                  ),
                ),
                const Spacer(flex: 4),
                if (onRetry != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      message ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    label: const Text('Retry', style: TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message ?? 'Starting up...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
