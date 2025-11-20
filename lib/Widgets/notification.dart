import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../Screens/MainScreen.dart';
import '../Screens/OrdersScreen.dart'; // Required for OrderSelectionService
import '../main.dart';

class OrderNotificationService with ChangeNotifier {
  static const String _soundKey = 'notification_sound_enabled';
  static const String _vibrateKey = 'notification_vibrate_enabled';

  bool _playSound = true;
  bool _vibrate = true;

  bool get playSound => _playSound;
  bool get vibrate => _vibrate;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final service = FlutterBackgroundService();
  GlobalKey<NavigatorState>? _navigatorKey;

  OrderNotificationService() {
    _loadPreferences();
  }

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

  void init(UserScopeService scopeService, GlobalKey<NavigatorState> key) {
    _navigatorKey = key;

    // Listen for 'new_order' events from the background service
    service.on('new_order').listen((payload) {
      if (payload != null) {
        final orderId = payload['orderId'] as String?;
        final title = payload['title'] as String?;
        final body = payload['body'] as String?;

        if (orderId != null && scopeService.isLoaded) {
          // Check if this order belongs to one of the admin's branches
          final branchIds = (payload['branchIds'] as List?)?.cast<String>() ?? [];
          final bool branchMatch = scopeService.isSuperAdmin ||
              branchIds.any((id) => scopeService.branchIds.contains(id));

          if (branchMatch) {
            // 1. Trigger Sound/Vibration (App is in foreground or this isolate is active)
            _triggerNotification(orderId, title, body);

            // 2. Show In-App Dialog if context is available
            final context = _navigatorKey?.currentContext;
            if (context != null) {
              // Define actions
              VoidCallback onAccept = () {
                FirebaseFirestore.instance
                    .collection('Orders')
                    .doc(orderId)
                    .update({'status': 'preparing'});
                Navigator.of(context).pop();
              };

              VoidCallback onReject = () {
                FirebaseFirestore.instance
                    .collection('Orders')
                    .doc(orderId)
                    .update({'status': 'cancelled'});
                Navigator.of(context).pop();
              };

              VoidCallback onAutoAccept = () {
                FirebaseFirestore.instance
                    .collection('Orders')
                    .doc(orderId)
                    .update({'status': 'preparing'});
                // Dialog usually closes itself via timer in onAutoAccept logic or stays open
              };

              // ✅ VITAL: Callback to View Order
              VoidCallback onViewOrder = () {
                Navigator.of(context).pop(); // Close dialog
                _navigateToOrder(orderId);   // Navigate
              };

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) => NewOrderDialog(
                  orderData: payload,
                  onAccept: onAccept,
                  onReject: onReject,
                  onAutoAccept: onAutoAccept,
                  onViewOrder: onViewOrder, // Pass the navigation callback
                ),
              );
            } else {
              debugPrint("❌ OrderNotificationService: Cannot show dialog, context is null.");
            }
          }
        }
      }
    });
  }

  Future<void> _triggerNotification(String orderId, String? title, String? body) async {
    if (_playSound) {
      final player = AudioPlayer();
      // Ensure you have 'assets/notification.mp3' in pubspec.yaml
      await player.play(AssetSource('notification.mp3'));
    }
    if (_vibrate) {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 500);
      }
    }
  }

  // ✅ ROBUST NAVIGATION: Sets the target order before switching screens
  void _navigateToOrder(String orderId) {
    debugPrint("🔔 Navigating to order: $orderId");

    // 1. Set the "Target" order in the static service
    OrderSelectionService.setSelectedOrder(
      orderId: orderId,
      orderType: null, // If unknown, OrdersScreen will try to find it or default
      status: 'pending', // Usually new orders are pending
    );

    // 2. Navigate to HomeScreen (which contains OrdersScreen)
    final context = _navigatorKey?.currentContext;
    if (context != null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
      );
    } else {
      debugPrint("❌ Cannot navigate! Navigator context is null.");
    }
  }
}

// -------------------------------------------------------------------
// ✅ NewOrderDialog: Enhanced with "View Order" functionality
// -------------------------------------------------------------------
class NewOrderDialog extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onAutoAccept;
  final VoidCallback onViewOrder; // Added callback

  const NewOrderDialog({
    Key? key,
    required this.orderData,
    required this.onAccept,
    required this.onReject,
    required this.onAutoAccept,
    required this.onViewOrder,
  }) : super(key: key);

  @override
  NewOrderDialogState createState() => NewOrderDialogState();
}

class NewOrderDialogState extends State<NewOrderDialog> {
  Timer? _timer;
  int _countdown = 30;
  bool _isExpanded = false;

  // Getters
  String get orderId => widget.orderData['orderId']?.toString() ?? 'N/A';
  String get orderNumber => widget.orderData['dailyOrderNumber']?.toString() ?? orderId.substring(0, 6).toUpperCase();
  String get customerName => widget.orderData['customerName']?.toString() ?? 'N/A';
  String get orderType => widget.orderData['Order_type']?.toString() ?? 'Unknown';
  String get address {
    final addressMap = widget.orderData['deliveryAddress'] as Map<String, dynamic>?;
    return addressMap?['street']?.toString() ?? 'N/A';
  }

  List<Map<String, dynamic>> get items {
    final itemsList = (widget.orderData['items'] as List<dynamic>?) ?? [];
    return itemsList.map((item) {
      final itemMap = (item is Map) ? Map<String, dynamic>.from(item) : <String, dynamic>{};
      final itemName = itemMap['name']?.toString() ?? 'Unknown';
      final qty = int.tryParse(itemMap['quantity']?.toString() ?? '1') ?? 1;
      final price = (itemMap['price'] as num?)?.toDouble() ?? 0.0;
      return {'name': itemName, 'qty': qty, 'price': price};
    }).toList();
  }

  double get totalAmount => (widget.orderData['totalAmount'] as num?)?.toDouble() ?? 0.0;

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  void startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown == 0) {
        timer.cancel();
        if (mounted) widget.onAutoAccept();
      } else {
        if (mounted) setState(() => _countdown--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Color _getOrderTypeColor(String orderType) {
    switch (orderType.toLowerCase()) {
      case 'delivery': return Colors.blue.shade700;
      case 'takeaway': return Colors.orange.shade700;
      case 'pickup': return Colors.green.shade700;
      case 'dine_in': return Colors.purple.shade700;
      default: return Colors.grey.shade700;
    }
  }

  IconData _getOrderTypeIcon(String orderType) {
    switch (orderType.toLowerCase()) {
      case 'delivery': return Icons.delivery_dining;
      case 'takeaway': return Icons.directions_car;
      case 'pickup': return Icons.shopping_bag;
      case 'dine_in': return Icons.restaurant;
      default: return Icons.receipt_long;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              decoration: BoxDecoration(
                color: _getOrderTypeColor(orderType),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Icon(_getOrderTypeIcon(orderType), color: Colors.white, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'New ${orderType.toUpperCase()} Order',
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text('#$orderNumber', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16, fontWeight: FontWeight.w500)),
                ],
              ),
            ),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(Icons.person_outline, 'Customer:', customerName),
                    if (orderType.toLowerCase() == 'delivery')
                      Padding(padding: const EdgeInsets.only(top: 8.0), child: _buildInfoRow(Icons.location_on_outlined, 'Address:', address)),
                    const Divider(height: 24),
                    Text('Items (${items.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    ...items.take(3).map((i) => Text("${i['qty']}x ${i['name']}")),
                    if (items.length > 3) Text("...and ${items.length - 3} more"),
                    const SizedBox(height: 16),
                    Text("Total: QAR ${totalAmount.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.deepPurple)),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.timer, size: 16, color: Colors.red),
                      const SizedBox(width: 4),
                      Text("Auto-accepting in $_countdown s", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton(onPressed: widget.onReject, child: const Text("Reject"))),
                      const SizedBox(width: 12),
                      Expanded(child: ElevatedButton(onPressed: widget.onAccept, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), child: const Text("Accept"))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      icon: const Icon(Icons.visibility),
                      label: const Text("View Full Order Details"),
                      onPressed: widget.onViewOrder,
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.black87, fontSize: 15),
              children: [
                TextSpan(text: "$label ", style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}