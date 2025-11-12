import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:vibration/vibration.dart';

import '../Screens/OrdersScreen.dart';
import '../main.dart';
import 'RiderAssignment.dart';

class OrderNotificationService with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AudioPlayer _audioPlayer = AudioPlayer();
  static const String _notificationSoundPath = 'notification.mp3';

  // ❌ REMOVED: StreamSubscription? _orderListener;
  bool _isDialogShowing = false;
  // ❌ REMOVED: final Set<String> _processedOrderIds = {};
  UserScopeService? _scopeService;

  // ✅ ADDED: StreamSubscription for the background service listener
  StreamSubscription<Map<String, dynamic>?>? _serviceListener;


  /// ✅ CRITICAL: This method must be called after login
  void init(UserScopeService scope, GlobalKey<NavigatorState> navigatorKey) {
    _scopeService = scope;

    // ❌ REMOVED: Old Firestore listener logic

    // ✅ ADDED: New listener for the background service
    final service = FlutterBackgroundService();

    // Cancel any existing listener before creating a new one
    _serviceListener?.cancel();

    // Listen for 'new_order' events from the background service
    _serviceListener = service.on('new_order').listen((event) {
      debugPrint(
          "🎯 OrderNotificationService: Received 'new_order' event from background.");

      final navContext = navigatorKey.currentContext;
      if (navContext != null && event != null && event is Map<String, dynamic>) {
        final data = event;
        final orderId = data['orderId'] as String?;

        if (orderId != null && !_isDialogShowing) {
          debugPrint('🎯 OrderNotificationService: Showing dialog for $orderId');
          // Show the in-app popup
          _showNewOrderPopup(navContext, orderId, data);
        } else {
          debugPrint(
              '🎯 OrderNotificationService: Dialog busy or orderId null, skipping popup.');
        }
      }
    });

    debugPrint(
        '✅ OrderNotificationService: Initialized and listening to BackgroundService.');
  }

  /// ❌ REMOVED: listenForNewOrders() function

  /// Triggers device vibration
  Future<void> _vibrate() async {
    try {
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [500, 1000]);
        debugPrint('📳 Device vibrated');
      }
    } catch (e) {
      debugPrint('Error vibrating: $e');
    }
  }

  /// Plays the notification sound from assets
  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource(_notificationSoundPath));
      debugPrint('🔊 OrderNotificationService: Playing sound');
    } catch (e) {
      debugPrint('Error playing notification sound: $e');
      debugPrint('Please ensure "assets/$_notificationSoundPath" is in your assets and pubspec.yaml');
    }
  }

  /// Shows the actual pop-up dialog.
  void _showNewOrderPopup(
      BuildContext context,
      String orderId,
      Map<String, dynamic> data,
      ) {
    if (_isDialogShowing) return;
    _isDialogShowing = true;

    debugPrint('🎯 Showing new order dialog for: $orderId');

    // Play sound and vibrate for the in-app dialog
    _playNotificationSound();
    _vibrate();

    // Extract details for the dialog
    final orderNumber = data['dailyOrderNumber']?.toString() ??
        orderId.substring(0, 6).toUpperCase();
    final customerName = data['customerName']?.toString() ?? 'N/A';
    final addressMap = data['deliveryAddress'] as Map<String, dynamic>?;
    final address = addressMap?['street']?.toString() ?? 'N/A';
    final itemsList = (data['items'] as List<dynamic>?) ?? [];
    final orderType = data['Order_type']?.toString() ?? 'Unknown';

    final items = itemsList.map((item) {
      // ✅ Added null check for item
      final itemMap = (item is Map) ? Map<String, dynamic>.from(item) : <String, dynamic>{};
      final itemName = itemMap['name']?.toString() ?? 'Unknown';
      final qty = itemMap['quantity']?.toString() ?? '1';
      return '$qty x $itemName';
    }).toList();
    final itemsString = items.join('\n');

    showDialog(
      context: context,
      barrierDismissible: false, // User must make a choice
      builder: (dialogContext) {
        return NewOrderDialog(
          orderNumber: orderNumber,
          customerName: customerName,
          address: address,
          itemsString: itemsString,
          orderType: orderType,
          onAccept: () {
            debugPrint('✅ Order accepted: $orderId');
            Navigator.of(dialogContext).pop();
            _handleOrderAcceptance(context, orderId);
          },
          onReject: () {
            debugPrint('❌ Order rejected: $orderId');
            Navigator.of(dialogContext).pop();
            _updateOrderStatus(orderId, 'cancelled');
          },
          onAutoAccept: () {
            debugPrint('🤖 Order auto-accepted: $orderId');
            Navigator.of(dialogContext).pop();
            _handleOrderAcceptance(context, orderId);
          },
        );
      },
    ).then((_) {
      // Ensure flag is reset when dialog is closed
      _isDialogShowing = false;
      // ❌ REMOVED: _processedOrderIds.remove(orderId);
      debugPrint('🎯 Dialog closed, isDialogShowing reset to: $_isDialogShowing');
    });
  }

  /// Runs the status update, printing, and rider assignment tasks in the background.
  Future<void> _handleOrderAcceptance(
      BuildContext context, String orderId) async {
    // Check if scope is available
    if (_scopeService == null || _scopeService!.branchId.isEmpty) {
      debugPrint("Error: UserScopeService not initialized or has no branchId. Cannot assign rider.");
      // Still update status
      await _updateOrderStatus(orderId, 'preparing');
      return;
    }

    final String branchId = _scopeService!.branchId;

    // 1. Update status
    await _updateOrderStatus(orderId, 'preparing');

    try {
      // 2. Fetch the full document
      final orderDoc = await _db.collection('Orders').doc(orderId).get();
      if (!orderDoc.exists) {
        debugPrint("Order $orderId not found for printing/assignment.");
        return;
      }

      // 3. Print receipt (using the main navigator context)
      if (context.mounted) {
        await printReceipt(context, orderDoc);
      }

      // 4. Auto-assign rider, passing the branchId
      await RiderAssignmentService.autoAssignRider(
        orderId: orderId,
        branchId: branchId,
      );
    } catch (e) {
      debugPrint("Error during print/auto-assign: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during print/auto-assign: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Updates an order's status in Firestore.
  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    try {
      final Map<String, dynamic> updateData = {'status': newStatus};

      if (newStatus == 'preparing') {
        updateData['timestamps.preparing'] = FieldValue.serverTimestamp();
      } else if (newStatus == 'cancelled') {
        updateData['timestamps.cancelled'] = FieldValue.serverTimestamp();
      }

      await _db.collection('Orders').doc(orderId).update(updateData);

      debugPrint('✅ OrderNotificationService: Order $orderId status updated to "$newStatus"');
    } catch (e) {
      debugPrint('❌ OrderNotificationService: Failed to update order $orderId: $e');
    }
  }

  /// Cleans up the listener when the service is disposed.
  @override
  void dispose() {
    _serviceListener?.cancel(); // ✅ Cancel the service listener
    _audioPlayer.dispose();
    RiderAssignmentService.dispose();
    debugPrint('🎯 OrderNotificationService: Disposed and service listener cancelled.');
    super.dispose();
  }
}

// ... (NewOrderDialog and NewOrderDialogState classes remain unchanged) ...
class NewOrderDialog extends StatefulWidget {
  final String orderNumber;
  final String customerName;
  final String address;
  final String itemsString;
  final String orderType;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onAutoAccept;

  const NewOrderDialog({
    Key? key,
    required this.orderNumber,
    required this.customerName,
    required this.address,
    required this.itemsString,
    required this.orderType,
    required this.onAccept,
    required this.onReject,
    required this.onAutoAccept,
  }) : super(key: key);

  @override
  NewOrderDialogState createState() => NewOrderDialogState();
}

class NewOrderDialogState extends State<NewOrderDialog> {
  Timer? _timer;
  int _countdown = 30;

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  void startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown == 0) {
        timer.cancel();
        if (mounted) {
          widget.onAutoAccept();
        }
      } else {
        if (mounted) {
          setState(() {
            _countdown--;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  IconData _getOrderTypeIcon(String orderType) {
    switch (orderType.toLowerCase()) {
      case 'delivery':
        return Icons.delivery_dining;
      case 'takeaway':
        return Icons.directions_car;
      case 'pickup':
        return Icons.shopping_bag;
      case 'dine_in':
        return Icons.restaurant;
      default:
        return Icons.receipt_long;
    }
  }

  String _formatOrderType(String orderType) {
    return orderType.replaceAll('_', ' ').toUpperCase();
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[700]),
          const SizedBox(width: 10),
          Text(
            '$label ',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
                fontSize: 15),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.notifications_active,
              color: Colors.deepPurple[600], size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'New Order! (#${widget.orderNumber})',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.deepPurple[800]),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Chip(
                avatar: Icon(_getOrderTypeIcon(widget.orderType),
                    color: Colors.white, size: 20),
                label: Text(
                  _formatOrderType(widget.orderType),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
                backgroundColor: Colors.deepPurple[400],
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
            const SizedBox(height: 20),
            _buildInfoRow(
                Icons.person_outline, 'Customer:', widget.customerName),
            if (widget.orderType.toLowerCase() == 'delivery')
              _buildInfoRow(
                  Icons.location_on_outlined, 'Address:', widget.address),
            const Divider(height: 24, thickness: 1),
            Text(
              'Items:',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.deepPurple[800]),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!)),
              child: Text(
                widget.itemsString.isEmpty
                    ? 'No items listed.'
                    : widget.itemsString,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ),
            const Divider(height: 24, thickness: 1),
            Center(
              child: Column(
                children: [
                  Text(
                    'Auto-accepting in',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_countdown',
                    style: TextStyle(
                      color: Colors.red[700],
                      fontWeight: FontWeight.bold,
                      fontSize: 32,
                    ),
                  ),
                  Text(
                    'seconds',
                    style: TextStyle(color: Colors.red[700], fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.close),
          onPressed: () {
            _timer?.cancel();
            widget.onReject();
          },
          style: TextButton.styleFrom(
              foregroundColor: Colors.red[700],
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          label: const Text('Reject',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check, size: 20),
          onPressed: () {
            _timer?.cancel();
            widget.onAccept();
          },
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
          label: const Text('Accept',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ],
    );
  }
}