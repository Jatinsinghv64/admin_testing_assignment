import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

// ❌ REMOVED: import '../Screens/OrdersScreen.dart'; // No longer needed for navigation
import '../Screens/MainScreen.dart';
import '../Screens/OrdersScreen.dart';
import '../main.dart';
import 'RiderAssignment.dart';

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
    // Load preferences when service is created
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
    // Listen for messages from the background service
    service.on('new_order').listen((payload) {
      if (payload != null) {
        final orderId = payload['orderId'] as String?;
        final title = payload['title'] as String?;
        final body = payload['body'] as String?;

        if (orderId != null && scopeService.isLoaded) {
          // Check if the order belongs to this admin's branch(es)
          final branchIds = (payload['branchIds'] as List?)?.cast<String>() ?? [];
          final bool branchMatch = scopeService.isSuperAdmin ||
              branchIds.any((id) => scopeService.branchIds.contains(id));

          if (branchMatch) {
            _triggerNotification(orderId, title, body);
          }
        }
      }
    });
  }

  Future<void> _triggerNotification(String orderId, String? title, String? body) async {
    if (_playSound) {
      // Re-initialize player to avoid issues
      final player = AudioPlayer();
      await player.play(AssetSource('notification.mp3'));
    }
    if (_vibrate) {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 500);
      }
    }

    // ✅ **MOVED _navigateToOrder HERE**
    void _navigateToOrder(String orderId) {
      final context = _navigatorKey?.currentContext;
      if (context != null) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => HomeScreen()),
              (route) => false,
        );
        debugPrint("Navigating to order: $orderId");
      } else {
        debugPrint("❌ Cannot navigate! Navigator context is null.");
      }
    }

    void showInAppOrderDialog(BuildContext context, String orderId, String? title, String? body) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title ?? 'New Order!'),
          content: Text(body ?? 'You have a new pending order.'),
          actions: [
            TextButton(
              child: const Text('Dismiss'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('View Order'),
              onPressed: () {
                Navigator.of(context).pop();
                _navigateToOrder(orderId); // ✅ **FIX:** This now calls the method inside this class
              },
            ),
          ],
        ),
      );
    }
  }}

//
// -------------------------------------------------------------------
// ✅ --- NewOrderDialog: REDESIGNED ---
// -------------------------------------------------------------------
//
class NewOrderDialog extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onAutoAccept;

  const NewOrderDialog({
    Key? key,
    required this.orderData,
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
  bool _isExpanded = false;

  // --- Getters to safely parse data ---
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

  // Getters for expanded details
  double get subtotal => (widget.orderData['subtotal'] as num?)?.toDouble() ?? 0.0;
  double get deliveryFee => (widget.orderData['deliveryFee'] as num?)?.toDouble() ?? 0.0;
  double get totalAmount => (widget.orderData['totalAmount'] as num?)?.toDouble() ?? 0.0;
  String get specialInstructions => widget.orderData['specialInstructions']?.toString() ?? '';
  // --- End of Getters ---


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

  // --- Redesign Helper Functions ---

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

  // ✅ NEW: Helper to get a color for the header
  Color _getOrderTypeColor(String orderType) {
    switch (orderType.toLowerCase()) {
      case 'delivery':
        return Colors.blue.shade700;
      case 'takeaway':
        return Colors.orange.shade700;
      case 'pickup':
        return Colors.green.shade700;
      case 'dine_in':
        return Colors.purple.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[700]),
          const SizedBox(width: 12),
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

  Widget _buildSummaryRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text('QAR ${amount.toStringAsFixed(2)}', style: TextStyle(fontSize: 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  // ✅ NEW: Redesigned item list
  Widget _buildItemsList() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${item['qty']} x ${item['name']}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
                Text(
                  'QAR ${(item['price'] * (item['qty'] as int)).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 15, color: Colors.black87),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildExpandedDetails() {
    return Container(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Summary:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple[800]),
          ),
          const SizedBox(height: 8),
          _buildSummaryRow('Subtotal', subtotal),
          if (deliveryFee > 0)
            _buildSummaryRow('Delivery Fee', deliveryFee),
          const Divider(height: 16),
          _buildSummaryRow('Total Amount', totalAmount, isTotal: true),

          if (specialInstructions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Special Instructions:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple[800]),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.yellow[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.yellow[200]!)
              ),
              child: Text(
                specialInstructions,
                style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.black87),
              ),
            ),
          ]
        ],
      ),
    );
  }

  // ✅ NEW: Professional Dialog Header
  Widget _buildDialogHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: BoxDecoration(
        color: _getOrderTypeColor(orderType),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Icon(_getOrderTypeIcon(orderType), color: Colors.white, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'New ${(_formatOrderType(orderType))} Order',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            '#$orderNumber',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ✅ NEW: Professional Actions Footer
  Widget _buildDialogActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04), // Light grey footer
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Countdown Timer
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.av_timer, color: Colors.grey[700], size: 18),
              const SizedBox(width: 8),
              Text(
                'Auto-accepting in',
                style: TextStyle(color: Colors.grey[700], fontSize: 14),
              ),
              const SizedBox(width: 4),
              Text(
                '$_countdown s',
                style: TextStyle(
                  color: Colors.red[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Action Buttons
          Row(
            children: [
              // Reject Button
              Expanded(
                flex: 1,
                child: TextButton(
                  onPressed: () {
                    _timer?.cancel();
                    widget.onReject();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red[700],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(width: 12),
              // Accept Button
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 20),
                  label: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  onPressed: () {
                    _timer?.cancel();
                    widget.onAccept();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // View Details Button (Full Width)
          OutlinedButton.icon(
            icon: Icon(_isExpanded ? Icons.unfold_less : Icons.unfold_more, size: 20),
            label: Text(_isExpanded ? 'Hide Details' : 'Show Full Details'),
            onPressed: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.blue[700],
              side: BorderSide(color: Colors.blue[200]!),
              minimumSize: const Size(double.infinity, 44), // Full width
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    // ✅ NEW: Replaced AlertDialog with Dialog and custom layout
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.all(16), // Padding from screen edges
      child: ConstrainedBox(
        // Limits the height on small screens to prevent overflow
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Header (The Highlight)
            _buildDialogHeader(),

            // 2. Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(
                        Icons.person_outline, 'Customer:', customerName),
                    if (orderType.toLowerCase() == 'delivery')
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: _buildInfoRow(
                            Icons.location_on_outlined, 'Address:', address),
                      ),
                    const Divider(height: 24, thickness: 1),
                    Text(
                      'Items:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    _buildItemsList(), // Use new item list builder

                    // Animated switcher for the expanded details
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: _isExpanded
                          ? _buildExpandedDetails()
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
            ),

            // 3. Actions Footer
            _buildDialogActions(),
          ],
        ),
      ),
    );
  }
}