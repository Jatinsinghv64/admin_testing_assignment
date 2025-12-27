import 'dart:async';
import 'dart:collection'; // For Queue
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../Screens/MainScreen.dart';
import '../main.dart'; // Imports UserScopeService

class OrderNotificationService with ChangeNotifier {
  static const String _soundKey = 'notification_sound_enabled';
  static const String _vibrateKey = 'notification_vibrate_enabled';

  final AudioPlayer _audioPlayer = AudioPlayer(); // Service-level player

  // ✅ ROBUSTNESS: Queue to handle high volume of incoming orders
  // Populated by both FCM (fast) and Firestore Listener (reliable backup)
  final Queue<String> _orderQueue = Queue<String>();
  StreamSubscription? _backupSubscription;

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

    // 1. 🚨 CRITICAL ROBUSTNESS: Listen to Firestore for missed orders/crash recovery
    if (scopeService.isLoaded) {
      _startBackupListener(scopeService);
    }
  }

  void _startBackupListener(UserScopeService scopeService) {
    _backupSubscription?.cancel();

    // Safety check for empty branch list
    if (scopeService.branchIds.isEmpty) return;

    // Query all pending orders for this branch
    _backupSubscription = FirebaseFirestore.instance
        .collection('Orders')
        .where('branchId', whereIn: scopeService.branchIds)
        .where('status', isEqualTo: 'pending')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          String orderId = change.doc.id;
          // Only add if not already in queue to avoid duplicates
          if (!_orderQueue.contains(orderId)) {
            debugPrint("📥 Backup Listener found pending order: $orderId");
            _orderQueue.add(orderId);
            _processOrderQueue(scopeService);
          }
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // ✅ LOGIC: QUEUE & PROCESS DIALOGS
  // --------------------------------------------------------------------------
  void handleFCMOrder(Map<String, dynamic> payload, UserScopeService scopeService) {
    if (!scopeService.isLoaded) return;

    final String? orderId = payload['orderId'];
    if (orderId == null) return;

    debugPrint("🔔 UI: Received Order Notification: $orderId");

    // Add to queue if not present (deduplication)
    if (!_orderQueue.contains(orderId)) {
      _orderQueue.add(orderId);
      _processOrderQueue(scopeService);
    }
  }

  void _processOrderQueue(UserScopeService scopeService) {
    // If a dialog is currently open or queue is empty, do nothing.
    if (_isDialogOpen || _orderQueue.isEmpty) return;

    final String nextOrderId = _orderQueue.removeFirst();
    _showRobustOrderDialog(nextOrderId, scopeService);
  }

  void _showRobustOrderDialog(String orderId, UserScopeService scopeService) {
    final context = _navigatorKey?.currentContext;

    if (context != null && context.mounted) {
      _isDialogOpen = true;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return NewOrderDialog(
            orderId: orderId,
            scopeService: scopeService,
            playSound: _playSound,
            vibrate: _vibrate,
            onClose: () {
              _isDialogOpen = false;
              // Small delay to allow UI to settle before next popup
              Future.delayed(const Duration(milliseconds: 300), () {
                _processOrderQueue(scopeService);
              });
            },
            // --- ACCEPT LOGIC ---
            onAccept: () async {
              // 4. 🛠️ ROBUSTNESS: Async Error Handling
              try {
                await FirebaseFirestore.instance.collection('Orders').doc(orderId).update({
                  'status': 'preparing',
                });

                // ✅ UX FIX: Removed _navigateToOrder(orderId).
                // The dialog will simply close via Navigator.pop in the widget.

              } catch (e) {
                debugPrint("❌ Failed to accept order: $e");
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error accepting order: $e"), backgroundColor: Colors.red),
                );
                // Rethrow so the UI knows not to close if it failed (optional)
                throw e;
              }
            },
            // --- REJECT LOGIC ---
            onReject: (reason) async {
              try {
                // 6. Security/Data Integrity
                String rejectedBy = scopeService.userEmail.isNotEmpty ? scopeService.userEmail : 'Admin';
                await FirebaseFirestore.instance.collection('Orders').doc(orderId).update({
                  'status': 'cancelled',
                  'rejectionReason': reason,
                  'rejectedBy': rejectedBy,
                  'rejectedAt': FieldValue.serverTimestamp(),
                });
              } catch (e) {
                debugPrint("❌ Failed to reject order: $e");
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error rejecting order: $e"), backgroundColor: Colors.red),
                );
              }
            },
            // --- AUTO-ACCEPT LOGIC ---
            onAutoAccept: () async {
              try {
                debugPrint("⏳ Timer expired. Auto-accepting order...");
                await FirebaseFirestore.instance.collection('Orders').doc(orderId).update({
                  'status': 'preparing',
                  'autoAccepted': true,
                });
                // Note: For auto-accept, we might still want to navigate or just notify.
                // Keeping it consistent with manual accept (just update status).
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Order Auto-Accepted"), backgroundColor: Colors.orange),
                );
              } catch (e) {
                debugPrint("❌ Failed to auto-accept order: $e");
              }
            },
          );
        },
      ).then((_) {
        // Ensure flag is reset when dialog closes
        _isDialogOpen = false;
        _processOrderQueue(scopeService);
      });
    }
  }

  // Helper used by other parts of the app, or kept for reference
  void _navigateToOrder(String orderId) {
    // This function is no longer called by onAccept to prevent dashboard redirection.
    // It can be removed if not used elsewhere.
  }
}

// -------------------------------------------------------------------
// NewOrderDialog UI (The Popup)
// -------------------------------------------------------------------

class NewOrderDialog extends StatefulWidget {
  final String orderId;
  final UserScopeService scopeService;
  final bool playSound;
  final bool vibrate;
  final Future<void> Function() onAccept; // Changed to Future for await
  final Function(String) onReject;
  final VoidCallback onAutoAccept;
  final VoidCallback onClose;

  const NewOrderDialog({
    Key? key,
    required this.orderId,
    required this.scopeService,
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
  // Data State
  Map<String, dynamic>? _orderData;
  bool _isLoading = true;
  String? _errorMessage;

  // Timer & Audio
  Timer? _timer;
  int _countdown = 60;
  bool _isStale = false; // New flag for stale orders

  final AudioPlayer _player = AudioPlayer();
  bool _isAudioPlaying = false;
  bool _isProcessing = false;

  // Safe Getters
  String get orderNumber => _orderData?['dailyOrderNumber']?.toString() ?? '---';
  String get customerName => _orderData?['customerName']?.toString() ?? 'Guest';
  String get orderType => _orderData?['Order_type']?.toString() ?? 'Delivery';

  String get address {
    try {
      if (_orderData?['deliveryAddress'] is Map) {
        return _orderData?['deliveryAddress']['street']?.toString() ?? 'No Address';
      }
    } catch(e) {}
    return 'N/A';
  }

  List<Map<String, dynamic>> get items {
    try {
      final list = _orderData?['items'];
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

  double get totalAmount => double.tryParse(_orderData?['totalAmount']?.toString() ?? '0') ?? 0.0;
  String get specialInstructions => _orderData?['specialInstructions']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchAndVerifyOrder();
  }

  Future<void> _fetchAndVerifyOrder() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('Orders').doc(widget.orderId).get();

      if (!doc.exists) {
        _handleError("Order not found.");
        return;
      }

      final data = doc.data();
      if (data == null) {
        _handleError("Order data is empty.");
        return;
      }

      data['orderId'] = widget.orderId;

      if (!_isUserAuthorized(data)) {
        debugPrint("⛔ ACCESS DENIED: User cannot view this order.");
        if (mounted) Navigator.of(context).pop();
        return;
      }

      if (mounted) {
        setState(() {
          _orderData = data;
          _isLoading = false;
        });

        _initializeCountdown();
        startTimer();
        _startAlarm();
      }

    } catch (e) {
      debugPrint("❌ Error fetching order: $e");
      _handleError("Failed to load order.");
    }
  }

  bool _isUserAuthorized(Map<String, dynamic> data) {
    if (widget.scopeService.isSuperAdmin) return true;

    String? orderBranchId = data['branchId'];
    if (orderBranchId == null && data['branchIds'] is List) {
      final list = data['branchIds'] as List;
      if (list.isNotEmpty) orderBranchId = list.first.toString();
    }

    if (orderBranchId != null) {
      return widget.scopeService.branchIds.contains(orderBranchId);
    }

    return false;
  }

  void _handleError(String msg) {
    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = msg;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  // 3. 🐛 LOGIC: Handle Stale Orders
  void _initializeCountdown() {
    if (_orderData == null) return;
    try {
      dynamic timestamp = _orderData!['timestamp'];
      DateTime? orderTime;

      if (timestamp is Timestamp) {
        orderTime = timestamp.toDate();
      } else if (timestamp is String) {
        orderTime = DateTime.tryParse(timestamp);
      } else if (timestamp is int) {
        orderTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      }

      if (orderTime != null) {
        final now = DateTime.now();
        final elapsedSeconds = now.difference(orderTime).inSeconds;

        // If order is older than 5 minutes (300 seconds), mark as stale and don't countdown
        if (elapsedSeconds > 300) {
          _isStale = true;
          _countdown = 0;
        } else {
          _isStale = false;
          final remaining = 60 - elapsedSeconds;
          _countdown = remaining > 0 ? remaining : 0;
        }
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

        if (_isStale) {
          // If stale, just stop the alarm but force manual action
          _stopAlarm();
        } else {
          // Only auto-accept if fresh
          _handleAutoAction();
        }
      } else {
        if (mounted) setState(() => _countdown--);
      }
    });
  }

  void _handleAutoAction() {
    _stopAlarm();
    widget.onAutoAccept();
    // No pop needed here as auto-accept usually keeps user informed via snackbar,
    // or you can add Navigator.pop if desired.
    if (mounted) Navigator.of(context).pop();
  }

  // 5. 🔊 Resource Leak: Dispose Audio Player
  @override
  void dispose() {
    _stopAlarm();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);

    // Dispose player to prevent leaks
    _player.dispose();

    // Call onClose so the Service knows this dialog is done
    widget.onClose();
    super.dispose();
  }

  Future<void> _handleRejectPress() async {
    await _stopAlarm();
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const RejectionReasonDialog(),
    );
    if (reason != null && mounted) {
      setState(() => _isProcessing = true);
      await widget.onReject(reason);
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ✅ UX FIX: Close Dialog on Accept
  Future<void> _handleAcceptPress() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    await _stopAlarm();
    try {
      // Wait for the service to perform the Firestore update
      await widget.onAccept();

      // Close the popup ONLY if successful
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _isProcessing = false);
    }
  }

  Color _getHeaderColor() {
    if (_orderData == null) return Colors.deepPurple;
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
        child: _isLoading
            ? Container(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text("Loading Order...", style: TextStyle(fontWeight: FontWeight.bold)),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10.0),
                  child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                )
            ],
          ),
        )
            : Column(
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
                    decoration: BoxDecoration(color: _isStale ? Colors.red : Colors.white24, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      _isStale ? 'LATE' : '$_countdown s',
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
  final FocusNode _otherFocusNode = FocusNode();

  final List<String> _reasons = [
    'Items Out of Stock',
    'Kitchen Too Busy',
    'Closing Soon / Closed',
    'Invalid Address',
    'Cannot Fulfill Special Request',
    'Other'
  ];

  @override
  void dispose() {
    _otherReasonController.dispose();
    _otherFocusNode.dispose();
    super.dispose();
  }

  void _onReasonSelected(String? value) {
    setState(() {
      _selectedReason = value;
    });

    if (value == 'Other') {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) FocusScope.of(context).requestFocus(_otherFocusNode);
      });
    } else {
      _otherFocusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isOther = _selectedReason == 'Other';
    final bool isValid = _selectedReason != null && (!isOther || _otherReasonController.text.trim().isNotEmpty);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 5,
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.report_problem_rounded, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  Text(
                    'Reject Order',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade900
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Please select a reason:",
                      style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),

                    ..._reasons.map((reason) {
                      final bool isSelected = _selectedReason == reason;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: InkWell(
                          onTap: () => _onReasonSelected(reason),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: isSelected ? Colors.red : Colors.grey.shade300,
                                  width: isSelected ? 2 : 1
                              ),
                              borderRadius: BorderRadius.circular(8),
                              color: isSelected ? Colors.red.shade50 : Colors.white,
                            ),
                            child: RadioListTile<String>(
                              title: Text(
                                reason,
                                style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? Colors.red.shade900 : Colors.black87
                                ),
                              ),
                              value: reason,
                              groupValue: _selectedReason,
                              onChanged: _onReasonSelected,
                              activeColor: Colors.red,
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      );
                    }).toList(),

                    AnimatedCrossFade(
                      firstChild: const SizedBox(width: double.infinity, height: 0),
                      secondChild: Padding(
                        padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                        child: TextField(
                          controller: _otherReasonController,
                          focusNode: _otherFocusNode,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Specify reason...',
                            hintText: 'e.g. Ingredient missing',
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.red, width: 2),
                            ),
                          ),
                          maxLines: 2,
                        ),
                      ),
                      crossFadeState: isOther ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 200),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        foregroundColor: Colors.grey.shade700,
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isValid ? () {
                        String finalReason = _selectedReason!;
                        if (finalReason == 'Other') {
                          finalReason = _otherReasonController.text.trim();
                        }
                        Navigator.of(context).pop(finalReason);
                      } : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        disabledBackgroundColor: Colors.red.shade100,
                      ),
                      child: const Text('Confirm Rejection'),
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