import 'dart:async';
import 'dart:collection'; // For Queue
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../Screens/MainScreen.dart';
import '../main.dart'; // Imports UserScopeService
import 'RiderAssignment.dart';

class OrderNotificationService with ChangeNotifier {
  static const String _soundKey = 'notification_sound_enabled';
  static const String _vibrateKey = 'notification_vibrate_enabled';

  final AudioPlayer _audioPlayer = AudioPlayer();

  // Queue to handle high volume of incoming orders
  final Queue<String> _orderQueue = Queue<String>();
  StreamSubscription? _backupSubscription;

  GlobalKey<NavigatorState>? _navigatorKey;
  bool _isDialogOpen = false;
  String? _currentOrderId;

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
    if (scopeService.isLoaded) {
      _startBackupListener(scopeService);
    }
  }

  void _startBackupListener(UserScopeService scopeService) {
    _backupSubscription?.cancel();

    if (scopeService.branchIds.isEmpty) return;

    debugPrint("🎧 Starting Backup Listener for branches: ${scopeService.branchIds}");

    _backupSubscription = FirebaseFirestore.instance
        .collection('Orders')
        .where('branchIds', arrayContainsAny: scopeService.branchIds)
        .where('status', isEqualTo: 'pending')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          String orderId = change.doc.id;

          try {
            final Timestamp? ts = change.doc['timestamp'] as Timestamp?;
            if (ts != null) {
              final DateTime orderTime = ts.toDate();
              final Duration diff = DateTime.now().difference(orderTime);

              if (diff.inHours > 12) {
                debugPrint("👻 Ignoring GHOST ORDER (Too Old): $orderId (${diff.inHours} hours ago)");
                continue;
              }
            }
          } catch (e) {
            debugPrint("⚠️ Date parsing error in listener: $e");
          }

          if (orderId != _currentOrderId && !_orderQueue.contains(orderId)) {
            debugPrint("📥 Backup Listener found pending order: $orderId");
            _orderQueue.add(orderId);
            _processOrderQueue(scopeService);
          }
        }
      }
    });
  }

  void handleFCMOrder(Map<String, dynamic> payload, UserScopeService scopeService) {
    if (!scopeService.isLoaded) return;

    final String? orderId = payload['orderId'];
    if (orderId == null) return;

    debugPrint("🔔 UI: Received Order Notification: $orderId");

    if (orderId != _currentOrderId && !_orderQueue.contains(orderId)) {
      _orderQueue.add(orderId);
      _processOrderQueue(scopeService);
    }
  }

  void _processOrderQueue(UserScopeService scopeService) {
    if (_isDialogOpen || _orderQueue.isEmpty) return;

    final String nextOrderId = _orderQueue.removeFirst();
    _showRobustOrderDialog(nextOrderId, scopeService);
  }

  void _showRobustOrderDialog(String orderId, UserScopeService scopeService) {
    final context = _navigatorKey?.currentContext;

    if (context != null && context.mounted) {
      _isDialogOpen = true;
      _currentOrderId = orderId;

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
              _currentOrderId = null;
              Future.delayed(const Duration(milliseconds: 300), () {
                _processOrderQueue(scopeService);
              });
            },
            onAccept: () async {
              try {
                String acceptedBy = scopeService.userEmail.isNotEmpty ? scopeService.userEmail : 'Admin';
                final docRef = FirebaseFirestore.instance.collection('Orders').doc(orderId);

                await FirebaseFirestore.instance.runTransaction((transaction) async {
                  final snapshot = await transaction.get(docRef);

                  if (!snapshot.exists) throw Exception("Order no longer exists!");
                  final status = snapshot.get('status');
                  if (status != 'pending') throw Exception("Order was already accepted by someone else.");

                  transaction.update(docRef, {
                    'status': 'preparing',
                    'acceptedBy': acceptedBy,
                    'acceptedAt': FieldValue.serverTimestamp(),
                  });
                });

              } catch (e) {
                debugPrint("❌ Failed to accept order: $e");
                if (context.mounted) {
                  String msg = e.toString().replaceAll("Exception:", "").trim();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(msg), backgroundColor: Colors.red),
                  );
                }
                rethrow;
              }
            },
            onReject: (reason) async {
              try {
                await RiderAssignmentService.cancelAutoAssignment(orderId);
                String rejectedBy = scopeService.userEmail.isNotEmpty ? scopeService.userEmail : 'Admin';
                await FirebaseFirestore.instance.collection('Orders').doc(orderId).update({
                  'status': 'cancelled',
                  'cancellationReason': reason,
                  'rejectedBy': rejectedBy,
                  'rejectedAt': FieldValue.serverTimestamp(),
                });
              } catch (e) {
                debugPrint("❌ Failed to reject order: $e");
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error rejecting order: $e"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            // ✅ CRITICAL UPDATE: AUTO-ACCEPT LOGIC
            onAutoAccept: () async {
              try {
                debugPrint("⏳ Timer expired. Attempting to Auto-Accept...");

                // ✅ SAFE AUTO-ACCEPT: Use Transaction to check status first
                final docRef = FirebaseFirestore.instance.collection('Orders').doc(orderId);
                
                await FirebaseFirestore.instance.runTransaction((transaction) async {
                  final snapshot = await transaction.get(docRef);
                  
                  if (!snapshot.exists) throw Exception("Order no longer exists!");
                  
                  final currentStatus = snapshot.get('status');
                  
                  // 🛑 CRITICAL CHECK: Only auto-accept if STILL PENDING
                  if (currentStatus != 'pending') {
                    debugPrint("⚠️ Order $orderId was already handled (Status: $currentStatus). Aborting Auto-Accept.");
                    return; // Do nothing, let the listener dismiss the dialog
                  }

                  transaction.update(docRef, {
                    'status': 'preparing',
                    'autoAccepted': true, 
                    'acceptedBy': 'Auto-Accept System',
                    'acceptedAt': FieldValue.serverTimestamp(),
                  });
                });

                if (context.mounted) {
                   // Only show snackbar if we actually did something? 
                   // Ideally we can't easily know if transaction aborted cleanly or updated inside here
                   // without returning a value. 
                   // But safely assuming if no specific error thrown, it went through OR was skipped.
                   // We will let the StreamListener dismiss the UI.
                }

              } catch (e) {
                debugPrint("❌ Auto-accept transaction failed: $e");
              }
            },
          );
        },
      ).then((_) {
        _isDialogOpen = false;
        _currentOrderId = null;
        _processOrderQueue(scopeService);
      });
    }
  }
}

class NewOrderDialog extends StatefulWidget {
  final String orderId;
  final UserScopeService scopeService;
  final bool playSound;
  final bool vibrate;
  final Future<void> Function() onAccept;
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
  Map<String, dynamic>? _orderData;
  bool _isLoading = true;
  String? _errorMessage;

  Timer? _timer;
  int _countdown = 60;
  bool _isStale = false;

  final AudioPlayer _player = AudioPlayer();
  bool _isAudioPlaying = false;
  bool _isProcessing = false;

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

  // Duplicate initState removed
  StreamSubscription? _orderSubscription;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startListeningToOrder();
  }

  void _startListeningToOrder() {
    _orderSubscription = FirebaseFirestore.instance
        .collection('Orders')
        .doc(widget.orderId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) {
        _handleError("Order not found or deleted.");
        return;
      }

      final data = snapshot.data();
      if (data == null) return;
      data['orderId'] = widget.orderId;

      // Access Control
      if (!_isUserAuthorized(data)) {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      // Live Status Check
      final status = data['status'];
      if (status != 'pending') {
        if (mounted) {
           // If accepted by someone else, close silently or with toast
           // But check who accepted it?
           final acceptedBy = data['acceptedBy'] ?? 'another user';
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Order handled by $acceptedBy'), backgroundColor: Colors.blue),
           );
           Navigator.of(context).pop(); 
        }
        return;
      }

      if (mounted) {
        setState(() {
          _orderData = data;
          _isLoading = false;
        });
        
        // Initialize countdown only once or on changes? 
        // We only need to start once.
        if (_timer == null) {
           _initializeCountdown();
           startTimer();
           _startAlarm();
        }
      }
    }, onError: (e) {
      debugPrint("❌ Error listening to order: $e");
      _handleError("Connection Error");
    });
  }

  bool _isUserAuthorized(Map<String, dynamic> data) {
    if (widget.scopeService.isSuperAdmin) return true;

    List<dynamic> orderBranchIds = [];
    if (data['branchIds'] is List) {
      orderBranchIds = data['branchIds'];
    } else if (data['branchId'] != null) {
      orderBranchIds = [data['branchId']];
    }

    if (orderBranchIds.isNotEmpty) {
      return orderBranchIds.any((id) => widget.scopeService.branchIds.contains(id.toString()));
    }

    return false;
  }

  void _handleError(String msg) {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = msg;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

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

        // ✅ LOGIC UPDATE: Even if stale, we stop alarm but assume admin sees it.
        // However, user specifically asked for "No action after 60s -> Auto Accept"
        // So we trigger _handleAutoAction() in both cases or just non-stale?
        // Usually, stale orders shouldn't be auto-accepted blindly,
        // BUT to fulfill the request "no action after 60s time will auto accept":

        if (_isStale) {
          _stopAlarm();
          // Optional: You can choose to auto-accept stale orders too,
          // but usually you just stop ringing.
          // Currently, I'll stick to auto-accepting FRESH orders that timed out.
        } else {
          _handleAutoAction();
        }
      } else {
        if (mounted) setState(() => _countdown--);
      }
    });
  }

  void _handleAutoAction() {
    _stopAlarm();
    // ✅ This triggers the onAutoAccept callback defined in the parent class
    widget.onAutoAccept();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _stopAlarm();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    widget.onClose();
    super.dispose();
  }

  Future<void> _handleRejectPress() async {
    await _stopAlarm();
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const CancellationReasonDialog(),
    );
    if (reason != null && mounted) {
      setState(() => _isProcessing = true);
      await widget.onReject(reason);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _handleAcceptPress() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    await _stopAlarm();
    try {
      await widget.onAccept();
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
    return PopScope(
      canPop: false,
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
              if (_errorMessage == null) const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                  _errorMessage ?? "Loading Order...",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _errorMessage != null ? Colors.red : Colors.black
                  )
              ),
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

class CancellationReasonDialog extends StatefulWidget {
  const CancellationReasonDialog({Key? key}) : super(key: key);

  @override
  State<CancellationReasonDialog> createState() => _CancellationReasonDialogState();
}

class _CancellationReasonDialogState extends State<CancellationReasonDialog> {
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