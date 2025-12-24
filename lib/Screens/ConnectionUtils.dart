import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Utility class to check for actual internet access
class ConnectionUtils {
  static final Connectivity _connectivity = Connectivity();

  /// Checks if there is actual internet access by pinging a reliable server.
  static Future<bool> hasInternetConnection() async {
    try {
      // Lookup google.com to verify DNS and internet access
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    } catch (e) {
      debugPrint('Connection check error: $e');
      return false;
    }
  }

  /// Monitors the connectivity state (Wifi/Mobile) and verifies internet access.
  static Stream<bool> get connectionStream async* {
    // Check initial state
    yield await hasInternetConnection();

    // Listen to network interface changes
    await for (final _ in _connectivity.onConnectivityChanged) {
      // Wait a moment for the network to stabilize before pinging
      await Future.delayed(const Duration(seconds: 2));
      yield await hasInternetConnection();
    }
  }
}

/// A wrapper widget that displays a red banner when offline.
/// Wrap your MaterialApp's `builder` or `home` with this.
class OfflineBanner extends StatefulWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _isOnline = true;
  Timer? _timer;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _startMonitoring();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  void _startMonitoring() {
    // 1. Initial check
    _checkConnection();

    // 2. Periodic check (every 30 seconds) to detect "connected but no internet" scenarios
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkConnection();
    });

    // 3. Listen to network changes (Wifi <-> Mobile <-> None)
    _subscription = Connectivity().onConnectivityChanged.listen((_) async {
      // Debounce slightly to allow network to settle
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _checkConnection();
    });
  }

  Future<void> _checkConnection() async {
    final isOnline = await ConnectionUtils.hasInternetConnection();
    if (mounted && isOnline != _isOnline) {
      setState(() {
        _isOnline = isOnline;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: widget.child),
        // Animate the offline banner in/out
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: _isOnline ? 0 : 40,
          color: Colors.red,
          child: _isOnline
              ? null
              : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              const Text(
                'No Internet Connection',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 16),
              SizedBox(
                height: 24,
                child: TextButton(
                  onPressed: _checkConnection,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('RETRY', style: TextStyle(fontSize: 12)),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }
}