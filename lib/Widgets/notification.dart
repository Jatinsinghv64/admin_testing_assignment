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
    Key? key,
    required this.orderData,
    required this.playSound,
    required this.vibrate,
    required this.onAccept,
    required this.onReject,
    required this.onAutoAccept,
    required this.onClose,
  }) : super(key: key);

  @override
  NewOrderDialogState createState() => NewOrderDialogState();
}

class NewOrderDialogState extends State<NewOrderDialog> with WidgetsBindingObserver {
  Timer? _timer;
  int _countdown = 60;
  final AudioPlayer _player = AudioPlayer();
  bool _isAudioPlaying = false;
  bool _isProcessing = false;

  String get orderId => widget.orderData['orderId']?.toString() ?? 'N/A';
  String get orderNumber => widget.orderData['dailyOrderNumber']?.toString() ?? '---';
  String get customerName => widget.orderData['customerName']?.toString() ?? 'Guest';
  String get orderType => widget.orderData['Order_type']?.toString() ?? 'Delivery';

  String get address {
    try {
      if (widget.orderData['deliveryAddress'] is Map) {
        return widget.orderData['deliveryAddress']['street']?.toString() ?? 'No Address';
      }
    } catch(e) {}
    return 'N/A';
  }

  List<Map<String, dynamic>> get items {
    try {
      final list = widget.orderData['items'];
      if (list is List) {
        return list.map((item) {
          final itemMap = Map<String, dynamic>.from(item as Map);
          return {
            'name': itemMap['name']?.toString() ?? 'Item',
            'qty': int.tryParse(itemMap['quantity']?.toString() ?? '1') ?? 1,
            'price': double.tryParse(itemMap['price']?.toString() ?? '0') ?? 0.0,
          };
        }).toList();
      }
    } catch (e) {
      debugPrint("Error parsing items: $e");
    }
    return [];
  }

  double get totalAmount => double.tryParse(widget.orderData['totalAmount']?.toString() ?? '0') ?? 0.0;
  String get specialInstructions => widget.orderData['specialInstructions']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Calculate countdown from order timestamp
    _initializeCountdown();

    startTimer();
    _startAlarm();
  }

  void _initializeCountdown() {
    try {
      dynamic timestamp = widget.orderData['timestamp'];
      DateTime? orderTime;

      if (timestamp is Timestamp) {
        orderTime = timestamp.toDate();
      } else if (timestamp is String) {
        orderTime = DateTime.tryParse(timestamp);
      } else if (timestamp is int) {
        orderTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is Map && timestamp.containsKey('seconds')) {
        final seconds = timestamp['seconds'];
        if (seconds is int) {
          orderTime = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
        }
      }

      if (orderTime != null) {
        final now = DateTime.now();
        final elapsedSeconds = now.difference(orderTime).inSeconds;
        final remaining = 60 - elapsedSeconds;
        _countdown = remaining > 0 ? remaining : 0;
      }
    } catch (e) {
      debugPrint("Error initializing countdown: $e");
    }
  }

  Future<void> _startAlarm() async {
    if (widget.playSound) {
      try {
        await _player.setReleaseMode(ReleaseMode.loop);
        await _player.play(AssetSource('notification.mp3'));
        _isAudioPlaying = true;
      } catch (e) {
        debugPrint("Audio Error: $e");
      }
    }

    if (widget.vibrate) {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(pattern: [500, 1000, 500, 1000], repeat: 0);
      }
    }
  }

  Future<void> _stopAlarm() async {
    try {
      if (_isAudioPlaying) {
        await _player.stop();
        await _player.release();
        _isAudioPlaying = false;
      }
      Vibration.cancel();
    } catch (e) {
      debugPrint("Stop Audio Error: $e");
    }
  }

  void startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 0) {
        timer.cancel();
        _handleAutoAction();
      } else {
        if (mounted) setState(() => _countdown--);
      }
    });
  }

  // ✅ UPDATED: Calls the auto-accept callback
  void _handleAutoAction() {
    _stopAlarm();
    widget.onAutoAccept();
    if(mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _stopAlarm();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.onClose();
    super.dispose();
  }

  Future<void> _handleRejectPress() async {
    await _stopAlarm();

    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return const RejectionReasonDialog();
      },
    );

    if (reason != null && mounted) {
      setState(() {
        _isProcessing = true;
      });

      await widget.onReject(reason);

      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _handleAcceptPress() async {
    await _stopAlarm();
    widget.onAccept();
    if(mounted) Navigator.of(context).pop();
  }

  Color _getHeaderColor() {
    switch (orderType.toLowerCase()) {
      case 'delivery': return Colors.blue.shade800;
      case 'takeaway': return Colors.orange.shade800;
      case 'pickup': return Colors.green.shade800;
      case 'dine_in': return Colors.purple.shade800;
      default: return Colors.deepPurple;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 10,
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // HEADER
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: _getHeaderColor(),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  if (_isProcessing)
                    const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    )
                  else
                    const Icon(Icons.notifications_active, color: Colors.white, size: 28),

                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NEW ${orderType.toUpperCase()}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        Text(
                          'Order #$orderNumber',
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      '$_countdown s',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  )
                ],
              ),
            ),

            // BODY
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person, color: Colors.grey, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(customerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                      ],
                    ),
                    if (orderType.toLowerCase() == 'delivery') ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on, color: Colors.grey, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(address, style: const TextStyle(fontSize: 14, color: Colors.black87), maxLines: 2)),
                        ],
                      ),
                    ],

                    const Divider(height: 24),

                    ...items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(4)
                            ),
                            child: Text('${item['qty']}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(item['name'], style: const TextStyle(fontSize: 15))),
                          Text('QAR ${item['price']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )).toList(),

                    if (specialInstructions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.yellow[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.yellow[200]!)),
                        child: Text("Note: $specialInstructions", style: const TextStyle(color: Colors.brown, fontStyle: FontStyle.italic)),
                      )
                    ],

                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Total Amount", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text("QAR ${totalAmount.toStringAsFixed(2)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ACTIONS
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isProcessing ? null : _handleRejectPress,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text("REJECT"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _handleAcceptPress,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 5,
                      ),
                      child: const Text("ACCEPT ORDER", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RejectionReasonDialog extends StatefulWidget {
  const RejectionReasonDialog({Key? key}) : super(key: key);

  @override
  State<RejectionReasonDialog> createState() => _RejectionReasonDialogState();
}

class _RejectionReasonDialogState extends State<RejectionReasonDialog> {
  String? _selectedReason;
  final TextEditingController _otherReasonController = TextEditingController();

  final List<String> _reasons = [
    'Items Out of Stock',
    'Kitchen Too Busy',
    'Closing Soon / Closed',
    'Invalid Address',
    'Cannot Fulfill Special Request',
    'Other'
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reason for Rejection'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._reasons.map((reason) => RadioListTile<String>(
              title: Text(reason),
              value: reason,
              groupValue: _selectedReason,
              onChanged: (value) {
                setState(() {
                  _selectedReason = value;
                });
              },
              contentPadding: EdgeInsets.zero,
              activeColor: Colors.red,
            )),
            if (_selectedReason == 'Other')
              TextField(
                controller: _otherReasonController,
                decoration: const InputDecoration(
                  labelText: 'Please specify reason',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _selectedReason == null ? null : () {
            String finalReason = _selectedReason!;
            if (finalReason == 'Other') {
              finalReason = _otherReasonController.text.trim();
              if (finalReason.isEmpty) return;
            }
            Navigator.of(context).pop(finalReason);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
          ),
          child: const Text('Confirm Rejection', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}