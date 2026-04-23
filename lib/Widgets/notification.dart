// lib/Widgets/notification.dart
import 'dart:async';
import 'dart:collection'; // For Queue
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../main.dart'; // Imports UserScopeService
import 'PrintingService.dart';
import 'RiderAssignment.dart';

class OrderItem {
  final String name;
  final int quantity;
  final String price;
  final String? originalPrice;
  final String? discountedPrice;
  final String? note;

  const OrderItem({
    required this.name,
    required this.quantity,
    required this.price,
    this.originalPrice,
    this.discountedPrice,
    this.note,
  });
}

class OrderNotificationService with ChangeNotifier {
  static const String _soundKey = 'notification_sound_enabled';
  static const String _vibrateKey = 'notification_vibrate_enabled';

  final AudioPlayer _audioPlayer = AudioPlayer();

  // Queue to handle high volume of incoming orders
  final Queue<String> _orderQueue = Queue<String>();

  // ✅ Session-level guard: prevent re-queuing the same order ID across
  // listener restarts (scope changes, branch reassignments, etc.)
  final Set<String> _seenOrderIds = {};

  // Multiple subscriptions — one per chunk of branches (≤10 each) to
  // work around Firestore's arrayContainsAny hard limit of 10 items.
  final List<StreamSubscription> _backupSubscriptions = [];

  GlobalKey<NavigatorState>? _navigatorKey;
  bool _isDialogOpen = false;
  String? _currentOrderId;

  // Preferences
  bool _playSound = true;
  bool _vibrate = true;

  // ✅ NEW: Track scope service and branch changes
  UserScopeService? _scopeService;
  List<String> _lastKnownBranchIds = [];
  VoidCallback? _scopeListener;

  bool get playSound => _playSound;
  bool get vibrate => _vibrate;

  /// Check if service is properly initialized with navigator key
  bool get isInitialized => _navigatorKey != null;

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
    _scopeService = scopeService;

    // Clean up any existing listener
    if (_scopeListener != null) {
      scopeService.removeListener(_scopeListener!);
    }

    // ✅ NEW: Listen for branch changes
    _scopeListener = () => _onScopeChanged(scopeService);
    scopeService.addListener(_scopeListener!);
    
    // START FIX: Ensure listener starts immediately on init
    debugPrint("🚀 OrderNotificationService: Initializing listeners...");
    _startBackupListener(scopeService);

    debugPrint("✅ OrderNotificationService initialized with navigator key");
  }

  /// ✅ NEW: Handle scope changes (e.g., branch reassignment)
  void _onScopeChanged(UserScopeService scopeService) {
    if (!scopeService.isLoaded) return;

    // Check if branchIds actually changed
    final currentBranchIds = scopeService.branchIds;
    final branchesChanged = !_listEquals(currentBranchIds, _lastKnownBranchIds);

    if (branchesChanged) {
      debugPrint(
          "🔄 Branch IDs changed: $_lastKnownBranchIds → $currentBranchIds");
      _lastKnownBranchIds = List.from(currentBranchIds);

      // Restart the backup listener with new branches
      _startBackupListener(scopeService);
    }
  }

  /// Compare two lists for equality
  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final sortedA = List<String>.from(a)..sort();
    final sortedB = List<String>.from(b)..sort();
    for (int i = 0; i < sortedA.length; i++) {
      if (sortedA[i] != sortedB[i]) return false;
    }
    return true;
  }

  /// Clean up listeners when service is disposed
  @override
  void dispose() {
    reset();
    super.dispose();
  }

  /// ✅ NEW: Reset all session-specific state and listeners
  void reset() {
    debugPrint("🧹 Resetting OrderNotificationService...");
    for (final sub in _backupSubscriptions) {
      sub.cancel();
    }
    _backupSubscriptions.clear();
    if (_scopeService != null && _scopeListener != null) {
      _scopeService!.removeListener(_scopeListener!);
    }
    _scopeListener = null;
    _scopeService = null;
    _lastKnownBranchIds = [];
    _orderQueue.clear();
    _seenOrderIds.clear();
    _currentOrderId = null;
    _isDialogOpen = false;
    notifyListeners();
  }

  void _startBackupListener(UserScopeService scopeService) {
    // Cancel all existing backup subscriptions
    for (final sub in _backupSubscriptions) {
      sub.cancel();
    }
    _backupSubscriptions.clear();

    try {
      final branchIds = scopeService.branchIds;
      final bool isSuperAdmin = scopeService.isSuperAdmin;

      if (branchIds.isEmpty) {
        if (isSuperAdmin) {
          debugPrint("👑 OrderNotificationService: SuperAdmin detected with no branch restriction. Listening to ALL orders.");
          _backupSubscriptions.add(FirebaseFirestore.instance.collection('Orders')
            .where('status', whereIn: ['pending', 'pending_payment'])
            .orderBy('timestamp', descending: true)
            .limit(20)
            .snapshots()
            .listen((s) => _handleOrderSnapshot(s, scopeService),
              onError: (error) => debugPrint("⚠️ Order backup listener error: $error")));
          return;
        } else {
          debugPrint("⚠️ OrderNotificationService: No branch IDs in scope, skipping backup listener.");
          return;
        }
      }

      debugPrint("📡 OrderNotificationService: Starting backup listener for branches: $branchIds");

      // Firestore array-contains-any is limited to 10 items.
      for (var i = 0; i < branchIds.length; i += 10) {
        final chunk = branchIds.sublist(i, i + 10 > branchIds.length ? branchIds.length : i + 10);
        _backupSubscriptions.add(FirebaseFirestore.instance.collection('Orders')
          .where('branchIds', arrayContainsAny: chunk)
          .where('status', whereIn: ['pending', 'pending_payment'])
          .orderBy('timestamp', descending: true)
          .limit(20)
          .snapshots()
          .listen((s) => _handleOrderSnapshot(s, scopeService),
            onError: (error) => debugPrint("⚠️ Order backup listener error: $error")));
      }
    } catch (e) {
      debugPrint("❌ OrderNotificationService: Failed to start backup listener: $e");
    }
  }

  void _handleOrderSnapshot(
      QuerySnapshot snapshot, UserScopeService scopeService) {
    for (var change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.added) {
        final String orderId = change.doc.id;

        // ✅ Age check: ignore orders older than 12 hours (ghost orders)
        try {
          final Timestamp? ts = change.doc['timestamp'] as Timestamp?;
          if (ts != null) {
            final Duration diff = DateTime.now().difference(ts.toDate());
            if (diff.inHours > 12) {
              debugPrint(
                  "👻 Ghost order skipped: $orderId (${diff.inHours}h old)");
              continue;
            }
          }
        } catch (e) {
          debugPrint("⚠️ Date parse error: $e");
        }

        // ✅ Seen-ID guard: never re-queue an order we already processed
        // in this session (prevents ghost dialogs on listener restarts).
        if (_seenOrderIds.contains(orderId)) continue;

        if (orderId != _currentOrderId && !_orderQueue.contains(orderId)) {
          debugPrint("📥 Backup Listener queuing order: $orderId");
          _seenOrderIds.add(orderId);
          _orderQueue.add(orderId);
          _processOrderQueue(scopeService);
        }
      }
    }
  }

  void handleFCMOrder(Map<String, dynamic> data, UserScopeService scope) {
    // Robustly extract orderId from data payload
    final String? orderId = data['orderId']?.toString() ?? data['id']?.toString() ?? data['order_id']?.toString();
    
    if (orderId == null) {
      debugPrint("⚠️ FCM Message received but no orderId found in data: $data");
      return;
    }

    debugPrint("🔔 FCM Order received: $orderId");
    if (_seenOrderIds.contains(orderId)) {
      debugPrint("⏭️ FCM Order $orderId already seen, skipping.");
      return;
    }

    _seenOrderIds.add(orderId);
    _orderQueue.add(orderId);
    _processOrderQueue(scope);
  }

  void _processOrderQueue(UserScopeService scopeService) async {
    if (_isDialogOpen || _orderQueue.isEmpty) return;

    final String nextOrderId = _orderQueue.removeFirst();

    // ✅ NEW: Check if order is from POS to suppress popup and start auto-accept timer
    try {
      final orderSnap = await FirebaseFirestore.instance
          .collection('Orders')
          .doc(nextOrderId)
          .get();

      if (orderSnap.exists) {
        final data = orderSnap.data() as Map<String, dynamic>;
        final String source = data['source']?.toString().toLowerCase() ?? '';
        final bool showPopup = (data['showPopupAlert'] as bool?) ?? (source != 'pos');

        if (!showPopup) {
          debugPrint("🚫 Skipping popup for order $nextOrderId (Source: $source)");

          // Start 15-second auto-accept timer for POS orders
          _startPosAutoAcceptTimer(nextOrderId);

          // Process next in queue
          _processOrderQueue(scopeService);
          return;
        }
      }
    } catch (e) {
      debugPrint("⚠️ Error checking order source: $e");
    }

    _showRobustOrderDialog(nextOrderId, scopeService);
  }

  void _startPosAutoAcceptTimer(String orderId) {
    debugPrint("⏳ Starting 15s auto-accept timer for POS order $orderId");
    Timer(const Duration(seconds: 15), () async {
      try {
        final docRef = FirebaseFirestore.instance.collection('Orders').doc(orderId);
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(docRef);
          if (!snapshot.exists) return;

          final status = snapshot.get('status');
          if (status == 'pending' || status == 'pending_payment') {
            transaction.update(docRef, {
              'status': 'preparing',
              'orderStatus': 'preparing',
              'isAutoAccepted': true,
              'acceptedBy': 'Auto-Accept (POS)',
              'acceptedAt': FieldValue.serverTimestamp(),
              'timestamps.preparing': FieldValue.serverTimestamp(),
            });
            debugPrint("✅ Auto-accepted POS order $orderId after 15s");
          } else {
            debugPrint("ℹ️ POS order $orderId was already handled (Status: $status)");
          }
        }).timeout(const Duration(seconds: 10), onTimeout: () {
          debugPrint("⏳ Auto-accept transaction timed out for $orderId");
        });
      } catch (e) {
        debugPrint("❌ Failed to auto-accept POS order $orderId: $e");
      }
    });
  }

  void _showRobustOrderDialog(String orderId, UserScopeService scopeService,
      {int retryCount = 0}) {
    final context = _navigatorKey?.currentContext;

    // ✅ Context null-safety: retry once after 800ms if context isn't ready
    if (context == null || !context.mounted) {
      if (retryCount < 2) {
        debugPrint(
            "⏳ Navigator context unavailable for order $orderId, retrying (attempt ${retryCount + 1})...");
        Future.delayed(const Duration(milliseconds: 800), () {
          _showRobustOrderDialog(orderId, scopeService,
              retryCount: retryCount + 1);
        });
      } else {
        debugPrint(
            "❌ Dropping order $orderId — navigator context permanently unavailable after retries");
        // Remove from seen so FCM can retry via another channel
        _seenOrderIds.remove(orderId);
        _isDialogOpen = false;
        _currentOrderId = null;
        _processOrderQueue(scopeService);
      }
      return;
    }

    if (context.mounted) {
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
                // ✅ Support both email and phone users
                String acceptedBy = scopeService.userIdentifier.isNotEmpty
                    ? scopeService.userIdentifier
                    : 'Admin';
                final docRef = FirebaseFirestore.instance
                    .collection('Orders')
                    .doc(orderId);

                await FirebaseFirestore.instance
                    .runTransaction((transaction) async {
                  final snapshot = await transaction.get(docRef);

                  if (!snapshot.exists)
                    throw Exception("Order no longer exists!");
                  final status = snapshot.get('status');
                  // Allow accepting 'pending' AND 'pending_payment'
                  if (status != 'pending' && status != 'pending_payment') {
                    throw Exception(
                        "Order was already accepted by someone else.");
                  }

                  transaction.update(docRef, {
                    'status': 'preparing',
                    'acceptedBy': acceptedBy,
                    'acceptedAt': FieldValue.serverTimestamp(),
                  });
                });

                // Auto-print receipt after successful acceptance
                try {
                  final orderDoc = await FirebaseFirestore.instance
                      .collection('Orders')
                      .doc(orderId)
                      .get();
                  if (orderDoc.exists && context.mounted) {
                    // Start printing in background, don't await it here to avoid blocking UI feedback
                    unawaited(PrintingService.printReceipt(context, orderDoc).catchError((printError) {
                      debugPrint("⚠️ Background auto-print failed: $printError");
                    }));
                    debugPrint("✅ Initiated auto-print for order $orderId");
                  }
                } catch (printError) {
                  debugPrint(
                      "⚠️ Auto-print preparation failed (non-blocking): $printError");
                }
              } catch (e) {
                debugPrint("❌ CRITICAL: Failed to accept order $orderId: $e");
                if (context.mounted) {
                  String msg = e.toString().contains("MissingPluginException")
                      ? "Plugin error: Please restart the app completely."
                      : e.toString().replaceAll("Exception:", "").trim();
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
                // ✅ Support both email and phone users
                String rejectedBy = scopeService.userIdentifier.isNotEmpty
                    ? scopeService.userIdentifier
                    : 'Admin';
                await FirebaseFirestore.instance
                    .collection('Orders')
                    .doc(orderId)
                    .update({
                  'status': 'cancelled',
                  'cancellationReason': reason,
                  'rejectedBy': rejectedBy,
                  'rejectedAt': FieldValue.serverTimestamp(),
                });
              } catch (e) {
                debugPrint("❌ Failed to reject order: $e");
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text("Error rejecting order: $e"),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            // ✅ CRITICAL UPDATE: AUTO-ACCEPT LOGIC
            onAutoAccept: () async {
              try {
                debugPrint("⏳ Timer expired. Attempting to Auto-Accept...");

                // ✅ SAFE AUTO-ACCEPT: Use Transaction to check status first
                final docRef = FirebaseFirestore.instance
                    .collection('Orders')
                    .doc(orderId);

                await FirebaseFirestore.instance
                    .runTransaction((transaction) async {
                  final snapshot = await transaction.get(docRef);

                  if (!snapshot.exists)
                    throw Exception("Order no longer exists!");

                  final currentStatus = snapshot.get('status');

                  // 🛑 CRITICAL CHECK: Only auto-accept if STILL PENDING or PENDING PAYMENT
                  if (currentStatus != 'pending' &&
                      currentStatus != 'pending_payment') {
                    debugPrint(
                        "⚠️ Order $orderId was already handled (Status: $currentStatus). Aborting Auto-Accept.");
                    return; // Do nothing, let the listener dismiss the dialog
                  }

                  transaction.update(docRef, {
                    'status': 'preparing',
                    'autoAccepted': true,
                    'acceptedBy': 'Auto-Accept System',
                    'acceptedAt': FieldValue.serverTimestamp(),
                  });
                }).timeout(const Duration(seconds: 15), onTimeout: () {
                  debugPrint("⏳ NewOrderDialog auto-accept transaction timed out for $orderId");
                });
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

class NewOrderDialogState extends State<NewOrderDialog>
    with WidgetsBindingObserver {
  Timer? _timer;
  Timer? _vibrationTimer;
  int _countdown = 60;
  bool _isStale = false;

  final AudioPlayer _player = AudioPlayer();
  bool _isAudioPlaying = false;
  bool _isProcessing = false;
  bool _isClosing = false; // Prevent multiple pop() calls

  Map<String, dynamic>? _orderData;
  bool _isLoading = true;
  String? _errorMessage;

  String get orderNumber =>
      _orderData?['dailyOrderNumber']?.toString() ?? '---';
  String get customerName => _orderData?['customerName']?.toString() ?? 'Guest';
  String get orderType => _orderData?['Order_type']?.toString() ?? 'Delivery';

  String get address {
    try {
      if (_orderData?['deliveryAddress'] is Map) {
        return _orderData?['deliveryAddress']['street']?.toString() ??
            'No Address';
      }
    } catch (e) {}
    return 'N/A';
  }

  String get sourcePlatform {
    final src = _orderData?['source']?.toString().toUpperCase() ?? 'APP';
    return src.isEmpty ? 'APP' : src;
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
            'discountedPrice': itemMap['discountedPrice'],
            'finalPrice': itemMap['finalPrice'],
          };
        }).toList();
      }
    } catch (e) {
      debugPrint("Error parsing items: $e");
    }
    return [];
  }

  double get totalAmount =>
      double.tryParse(_orderData?['totalAmount']?.toString() ?? '0') ?? 0.0;

  double get subTotal {
    double sum = 0;
    for (var item in items) {
      double price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
      int qty = item['qty'] as int? ?? 0;
      sum += price * qty;
    }
    return sum;
  }

  double get discountTotal {
    double totalD = 0;
    for (var item in items) {
      final double price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
      final double? dPrice = (item['discountedPrice'] ?? item['finalPrice']) != null 
          ? double.tryParse((item['discountedPrice'] ?? item['finalPrice']).toString()) 
          : null;
      
      if (dPrice != null && dPrice < price) {
        int qty = item['qty'] as int? ?? 0;
        totalD += (price - dPrice) * qty;
      }
    }
    return totalD;
  }

  double get deliveryFee =>
      double.tryParse((_orderData?['riderPaymentAmount'] ?? _orderData?['deliveryFee'])?.toString() ?? '0') ?? 0.0;
  String get specialInstructions =>
      _orderData?['specialInstructions']?.toString() ?? '';

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
      if (status != 'pending' && status != 'pending_payment') {
        if (mounted && !_isClosing) {
          _isClosing = true;
          final acceptedBy = data['acceptedBy'] ?? 'another user';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Order handled by $acceptedBy'),
                backgroundColor: Colors.blue),
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
    List<dynamic> orderBranchIds = [];
    if (data['branchIds'] is List && (data['branchIds'] as List).isNotEmpty) {
      orderBranchIds = data['branchIds'];
    }

    if (orderBranchIds.isNotEmpty) {
      return orderBranchIds
          .any((id) => widget.scopeService.branchIds.contains(id.toString()));
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
      try {
        final hasVibrator = await Vibration.hasVibrator() ?? false;
        if (hasVibrator) {
          _vibrationTimer?.cancel();
          _vibrationTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
            try {
              await Vibration.vibrate(pattern: [500, 1000, 500, 1000]);
            } catch (e) {
              debugPrint("⚠️ Periodic vibration error: $e");
              timer.cancel();
            }
          });
          // Initial vibration
          await Vibration.vibrate(pattern: [500, 1000, 500, 1000]);
        }
      } catch (e) {
        debugPrint("Vibration Error: $e");
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
      _vibrationTimer?.cancel();
      _vibrationTimer = null;
      try {
        await Vibration.cancel();
      } catch (e) {
        debugPrint("Vibration Cancel Error: $e");
      }
    } catch (e) {
      debugPrint("Stop Audio Error: $e");
    }
  }

  void startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 0) {
        timer.cancel();

        if (_isStale) {
          _stopAlarm();
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
    widget.onAutoAccept();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
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
    if (reason != null && mounted && !_isClosing) {
      _isClosing = true;
      setState(() => _isProcessing = true);
      await _orderSubscription?.cancel();
      await widget.onReject(reason);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _handleAcceptPress() async {
    if (_isProcessing || _isClosing) return;
    _isClosing = true;
    setState(() => _isProcessing = true);

    await _stopAlarm();
    await _orderSubscription?.cancel();
    try {
      await widget.onAccept();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _isClosing = false;
      setState(() => _isProcessing = false);
      _startListeningToOrder();
    }
  }

  Color _getHeaderColor() {
    if (_orderData == null) return Colors.deepPurple;
    switch (orderType.toLowerCase()) {
      case 'delivery':
        return Colors.blue.shade800;
      case 'takeaway':
        return Colors.orange.shade800;
      case 'pickup':
        return Colors.green.shade800;
      case 'dine_in':
        return Colors.purple.shade800;
      default:
        return Colors.deepPurple;
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isLargeScreen = MediaQuery.of(context).size.width > 600;

    return PopScope(
      canPop: false,
      child: _isLoading
          ? Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 10,
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMessage == null)
                const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(_errorMessage ?? "Loading Order...",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _errorMessage != null
                          ? Colors.red
                          : Colors.black)),
            ],
          ),
        ),
      )
          : isLargeScreen
          ? _buildLargeScreenDialog(context)
          : _buildSmallScreenDialog(context),
    );
  }

  Widget _buildLargeScreenDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = colorScheme.primary;

    List<OrderItem> mappedItems = items.map((item) {
      final double price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
      final double? dPrice = (item['discountedPrice'] ?? item['finalPrice']) != null 
          ? double.tryParse((item['discountedPrice'] ?? item['finalPrice']).toString()) 
          : null;
      
      final bool hasDiscount = dPrice != null && dPrice < price;

      return OrderItem(
        name: item['name'].toString(),
        quantity: item['qty'] as int,
        price: 'QAR ${item['price']}',
        originalPrice: hasDiscount ? 'QAR ${item['price']}' : null,
        discountedPrice: hasDiscount ? 'QAR $dPrice' : null,
        note: null,
      );
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 500,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 15,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withOpacity(0.4),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.shopping_bag,
                          color: colorScheme.onPrimary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'NEW ORDER',
                                style: GoogleFonts.inter(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                  color: primaryColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  orderNumber,
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Incoming Transmission',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                              color: primaryColor.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.timer,
                            color: _isStale ? Colors.red : primaryColor,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isStale ? 'LATE' : '${_countdown}s',
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: _isStale ? Colors.red : primaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (!_isStale)
                        SizedBox(
                          width: 100,
                          child: LinearProgressIndicator(
                            value: _countdown / 60,
                            backgroundColor: primaryColor.withOpacity(0.2),
                            color: primaryColor,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5),

            // Customer Details
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CUSTOMER IDENTITY',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        customerName,
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            address,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'SOURCE PLATFORM',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.bolt,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              sourcePlatform,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5),

            // Items List
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PAYLOAD MANIFEST',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Column(
                        children: mappedItems
                            .map(
                              (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: colorScheme.outline.withOpacity(0.1),
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${item.quantity}x',
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                        if (item.note != null)
                                          Text(
                                            item.note!,
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.5,
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (item.originalPrice != null)
                                      Text(
                                        item.originalPrice!,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                                          decoration: TextDecoration.lineThrough,
                                        ),
                                      ),
                                    Text(
                                      item.discountedPrice ?? item.price,
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: item.discountedPrice != null 
                                            ? Colors.green 
                                            : colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SUBTOTAL',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        'QAR ${subTotal.toStringAsFixed(2)}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  if (discountTotal > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'DISCOUNT',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: Colors.green,
                          ),
                        ),
                        Text(
                          '- QAR ${discountTotal.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (deliveryFee > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'DELIVERY FEE',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          'QAR ${deliveryFee.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Note section if specialInstructions exists
            if (specialInstructions.isNotEmpty) ...[
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.yellow[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.yellow[200]!)),
                    child: Text("Note: $specialInstructions",
                        style: GoogleFonts.inter(
                            color: Colors.brown,
                            fontStyle: FontStyle.italic)),
                  )
              ),
              const SizedBox(height: 12),
            ],

            // Total Section
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colorScheme.outline.withOpacity(0.1), width: 0.5),
                  bottom: BorderSide(color: colorScheme.outline.withOpacity(0.1), width: 0.5),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL RECEIVABLE',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        'Includes delivery',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'QAR ${totalAmount.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),

            // Action Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isProcessing ? null : _handleRejectPress,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colorScheme.outline.withOpacity(0.1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.close, size: 18, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text(
                            'REJECT',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _handleAcceptPress,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shadowColor: colorScheme.primary.withOpacity(0.3),
                      ),
                      child: _isProcessing
                          ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: colorScheme.onPrimary, strokeWidth: 2),
                      )
                          : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 18,
                            color: colorScheme.onPrimary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'ACCEPT ORDER',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: colorScheme.onPrimary,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildSmallScreenDialog(BuildContext context) {
    return Dialog(
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
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  if (_isProcessing)
                    const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                  else
                    const Icon(Icons.notifications_active,
                        color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NEW ${orderType.toUpperCase()}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18),
                        ),
                        Text(
                          'Order #$orderNumber',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: _isStale ? Colors.red : Colors.white24,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      _isStale ? 'LATE' : '$_countdown s',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
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
                        const Icon(Icons.person,
                            color: Colors.grey, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(customerName,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold))),
                      ],
                    ),
                    if (orderType.toLowerCase() == 'delivery') ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on,
                              color: Colors.grey, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(address,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87),
                                  maxLines: 2)),
                        ],
                      ),
                    ],
                    const Divider(height: 24),
                    ...items
                        .map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius:
                                BorderRadius.circular(4)),
                            child: Text('${item['qty']}x',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(item['name'],
                                  style: const TextStyle(
                                      fontSize: 15))),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if ((item['discountedPrice'] ?? item['finalPrice']) != null && 
                                  double.tryParse((item['discountedPrice'] ?? item['finalPrice']).toString())! < double.tryParse(item['price'].toString())!)
                                Text(
                                  'QAR ${item['price']}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              Text(
                                'QAR ${item['discountedPrice'] ?? item['finalPrice'] ?? item['price']}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: (item['discountedPrice'] ?? item['finalPrice']) != null && 
                                      double.tryParse((item['discountedPrice'] ?? item['finalPrice']).toString())! < double.tryParse(item['price'].toString())!
                                      ? Colors.green 
                                      : Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ))
                        .toList(),
                    if (specialInstructions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: Colors.yellow[50],
                            borderRadius: BorderRadius.circular(8),
                            border:
                            Border.all(color: Colors.yellow[200]!)),
                        child: Text("Note: $specialInstructions",
                            style: const TextStyle(
                                color: Colors.brown,
                                fontStyle: FontStyle.italic)),
                      )
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Subtotal",
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.black54)),
                        Text("QAR ${subTotal.toStringAsFixed(2)}",
                            style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87)),
                      ],
                    ),
                    if (discountTotal > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Discount",
                              style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.green)),
                          Text("- QAR ${discountTotal.toStringAsFixed(2)}",
                              style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.green)),
                        ],
                      ),
                    ],
                    if (deliveryFee > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Delivery Fee",
                              style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54)),
                          Text("QAR ${deliveryFee.toStringAsFixed(2)}",
                              style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87)),
                        ],
                      ),
                    ],
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Total Amount",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        Text("QAR ${totalAmount.toStringAsFixed(2)}",
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green)),
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
                      onPressed:
                      _isProcessing ? null : _handleRejectPress,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text("REJECT"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed:
                      _isProcessing ? null : _handleAcceptPress,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 5,
                      ),
                      child: const Text("ACCEPT ORDER",
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ));
  }
}

class CancellationReasonDialog extends StatefulWidget {
  const CancellationReasonDialog({Key? key}) : super(key: key);

  @override
  State<CancellationReasonDialog> createState() =>
      _CancellationReasonDialogState();
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
    final bool isValid = _selectedReason != null &&
        (!isOther || _otherReasonController.text.trim().isNotEmpty);

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
                  Icon(Icons.report_problem_rounded,
                      color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  Text(
                    'Reject Order',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade900),
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
                      style: TextStyle(
                          fontWeight: FontWeight.w500, color: Colors.grey),
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
                                  color: isSelected
                                      ? Colors.red
                                      : Colors.grey.shade300,
                                  width: isSelected ? 2 : 1),
                              borderRadius: BorderRadius.circular(8),
                              color: isSelected
                                  ? Colors.red.shade50
                                  : Colors.white,
                            ),
                            child: RadioListTile<String>(
                              title: Text(
                                reason,
                                style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Colors.red.shade900
                                        : Colors.black87),
                              ),
                              value: reason,
                              groupValue: _selectedReason,
                              onChanged: _onReasonSelected,
                              activeColor: Colors.red,
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                    AnimatedCrossFade(
                      firstChild:
                      const SizedBox(width: double.infinity, height: 0),
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
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                              const BorderSide(color: Colors.red, width: 2),
                            ),
                          ),
                          maxLines: 2,
                        ),
                      ),
                      crossFadeState: isOther
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
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
                      onPressed: isValid
                          ? () {
                        String finalReason = _selectedReason!;
                        if (finalReason == 'Other') {
                          finalReason =
                              _otherReasonController.text.trim();
                        }
                        Navigator.of(context).pop(finalReason);
                      }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
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