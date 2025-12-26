import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../Screens/MainScreen.dart';
import '../main.dart'; // For UserScopeService reference if needed
import 'RiderAssignment.dart';

class OrderNotificationService with ChangeNotifier {
  static const String _soundKey = 'notification_sound_enabled';
  static const String _vibrateKey = 'notification_vibrate_enabled';

  final AudioPlayer _audioPlayer = AudioPlayer();
  final service = FlutterBackgroundService();
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _isDialogOpen = false;

  // Preferences
  bool _playSound = true;
  bool _vibrate = true;

  bool get playSound => _playSound;
  bool get vibrate => _vibrate;

  OrderNotificationService() {
    _loadPreferences();
  }

  // --- Preferences Management (Required for SettingsScreen) ---

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _playSound = prefs.getBool(_soundKey) ?? true;
    _vibrate = prefs.getBool(_vibrateKey) ?? true;
    notifyListeners();
  }

  Future<void> setPlaySound(bool value) async {
    _playSound = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundKey, value);
    notifyListeners();
  }

  Future<void> setVibrate(bool value) async {
    _vibrate = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vibrateKey, value);
    notifyListeners();
  }

  // --- Initialization & Listener Logic ---

  void init(UserScopeService scopeService, GlobalKey<NavigatorState> key) {
    _navigatorKey = key;

    // Listen to the "invoke" from BackgroundOrderService
    service.on('new_order').listen((payload) {
      if (payload != null) {
        debugPrint("🔔 UI: Received new_order event from Background Service");

        final orderId = payload['orderId'] as String?;
        if (orderId != null && scopeService.isLoaded) {

          // ✅ CRITICAL FIX: Robust parsing of branchIds
          // This prevents the "type 'String' is not a subtype of 'List'" crash
          List<String> incomingBranchIds = [];
          final rawBranchIds = payload['branchIds'];

          if (rawBranchIds is List) {
            incomingBranchIds = rawBranchIds.map((e) => e.toString()).toList();
          } else if (rawBranchIds is String) {
            // Handle case where it might be a JSON string like "[id1, id2]"
            try {
              // Simple strip and split if it looks like a list
              incomingBranchIds = rawBranchIds
                  .replaceAll('[', '')
                  .replaceAll(']', '')
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
            } catch (e) {
              debugPrint("⚠️ Error parsing string branchIds: $e");
            }
          }

          // Check if this order belongs to one of the user's managed branches
          final bool branchMatch = scopeService.isSuperAdmin ||
              incomingBranchIds.any((id) => scopeService.branchIds.contains(id));

          if (branchMatch) {
            _showRobustOrderDialog(payload, scopeService.userEmail);
          } else {
            debugPrint("⚠️ Ignoring order from unmanaged branch: $incomingBranchIds");
          }
        }
      }
    });
  }

  // --- Dialog Logic ---

  void _showRobustOrderDialog(Map<String, dynamic> orderData, String adminEmail) {
    final context = _navigatorKey?.currentContext;

    // Only show if we have a context and dialog isn't already open
    if (context != null && !_isDialogOpen) {
      _isDialogOpen = true;

      showDialog(
        context: context,
        barrierDismissible: false, // User must Accept/Reject
        builder: (context) {
          return NewOrderDialog(
            orderData: orderData,
            playSound: _playSound,
            vibrate: _vibrate,
            onClose: () => _isDialogOpen = false,
            onAccept: () => _navigateToOrder(orderData['orderId']),
            onReject: (reason) async {
              // Reject Logic: Update Firestore
              await FirebaseFirestore.instance.collection('Orders').doc(orderData['orderId']).update({
                'status': 'cancelled',
                'rejectionReason': reason,
                'rejectedBy': adminEmail,
                'rejectedAt': FieldValue.serverTimestamp(),
              });
            },
            onAutoAccept: () async {
              // Auto-Accept Logic (Timeout): Update Firestore
              // Note: You might want to auto-reject instead depending on business logic
              await FirebaseFirestore.instance.collection('Orders').doc(orderData['orderId']).update({
                'status': 'preparing',
                'autoAccepted': true,
              });
              _navigateToOrder(orderData['orderId']);
            },
          );
        },
      ).then((_) => _isDialogOpen = false);
    }
  }

  void _navigateToOrder(String orderId) {
    final context = _navigatorKey?.currentContext;
    if (context != null) {
      // Navigate to Home Screen (which usually lists orders)
      // Ideally, you'd pass the orderId to highlight it or open details
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
      );
    }
  }
}

// -------------------------------------------------------------------
// NewOrderDialog UI (The Popup)
// -------------------------------------------------------------------

class NewOrderDialog extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final bool playSound;
  final bool vibrate;
  final VoidCallback onAccept;
  final Function(String) onReject;
  final VoidCallback onAutoAccept;
  final VoidCallback onClose;

  const NewOrderDialog({
    super.key,
    required this.orderData,
    required this.playSound,
    required this.vibrate,
    required this.onAccept,
    required this.onReject,
    required this.onAutoAccept,
    required this.onClose,
  });

  @override
  State<NewOrderDialog> createState() => _NewOrderDialogState();
}

class _NewOrderDialogState extends State<NewOrderDialog> with WidgetsBindingObserver {
  Timer? _timer;
  int _countdown = 60; // 60 Seconds to respond
  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAlarm();

    // Countdown Timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 0) {
        timer.cancel();
        _stopAlarm();
        widget.onAutoAccept(); // Timeout action
        if (mounted) Navigator.of(context).pop();
      } else {
        if (mounted) setState(() => _countdown--);
      }
    });
  }

  Future<void> _startAlarm() async {
    if (widget.playSound) {
      await _player.setReleaseMode(ReleaseMode.loop); // Loop sound
      // Ensure 'notification.mp3' exists in your assets!
      await _player.play(AssetSource('notification.mp3'));
    }
    if (widget.vibrate) {
      // Continuous vibration pattern
      Vibration.vibrate(pattern: [500, 1000, 500, 1000], repeat: 0);
    }
  }

  Future<void> _stopAlarm() async {
    await _player.stop();
    Vibration.cancel();
  }

  @override
  void dispose() {
    _stopAlarm();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.onClose(); // Notify service that dialog is closed
    super.dispose();
  }

  // Handle App Lifecycle to stop sound if app goes background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _stopAlarm();
    } else if (state == AppLifecycleState.resumed) {
      // Optional: Restart alarm if you want strict alerts
      // _startAlarm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderNum = widget.orderData['dailyOrderNumber']?.toString() ?? '---';
    final customer = widget.orderData['customerName'] ?? 'Guest';
    final price = widget.orderData['totalAmount']?.toString() ?? '0.00';

    return WillPopScope(
      onWillPop: () async => false, // Prevent back button closing
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 20,
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              const Icon(Icons.restaurant_menu, color: Colors.deepPurple, size: 40),
              const SizedBox(height: 10),
              const Text("New Order Received!",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
              const Divider(height: 30),

              // Details
              _buildDetailRow("Order #", orderNum, isBold: true),
              _buildDetailRow("Customer", customer),
              _buildDetailRow("Amount", "\$$price"),

              const SizedBox(height: 20),

              // Countdown
              Text("Auto-accept in $_countdown s",
                  style: const TextStyle(fontSize: 14, color: Colors.red, fontStyle: FontStyle.italic)),
              const SizedBox(height: 20),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[50],
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () async {
                        await _stopAlarm();
                        widget.onReject("Kitchen Busy");
                        if (mounted) Navigator.pop(context);
                      },
                      child: const Text("Reject"),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 5,
                      ),
                      onPressed: () async {
                        await _stopAlarm();
                        widget.onAccept();
                        if (mounted) Navigator.pop(context);
                      },
                      child: const Text("Accept Order"),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: isBold ? 18 : 16,
              color: Colors.black87
          )),
        ],
      ),
    );
  }
}