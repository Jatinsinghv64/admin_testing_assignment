// lib/services/pos/pos_service.dart
// POS session and cart management service

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../constants.dart';
import '../../main.dart';
import '../inventory/InventoryService.dart';
import '../ingredients/IngredientService.dart';
import 'pos_order_lifecycle.dart';
import 'pos_models.dart';

class _AllocatedPaymentPart {
  final String method;
  final String? label;
  final double amount;
  final double change;
  final double appliedAmount;
  final DateTime timestamp;

  const _AllocatedPaymentPart({
    required this.method,
    this.label,
    required this.amount,
    required this.change,
    required this.appliedAmount,
    required this.timestamp,
  });

  PosPayment toPayment() {
    return PosPayment(
      method: method,
      label: label,
      amount: amount,
      change: change,
      appliedAmount: appliedAmount,
      timestamp: timestamp,
    );
  }
}

class PosService extends ChangeNotifier {
  // ── Industry-grade limits ──────────────────────────────────
  static const int maxCartItems = 50;
  static const int maxQuantityPerItem = 999;
  static const Duration _firestoreWriteTimeout = Duration(seconds: 30);
  static const Duration _kitchenResponseTimeout = Duration(seconds: 30);
  static const double _currencyEpsilon = 0.01;
  static const List<String> _activeTableStatuses = <String>[
    AppConstants.statusPending,
    AppConstants.statusPreparing,
    AppConstants.statusPrepared,
    AppConstants.statusServed,
  ];

  // ── Cart State ──────────────────────────────────────────────
  final List<PosCartItem> _cartItems = [];
  PosOrderType _orderType = PosOrderType.dineIn;
  String? _selectedTableId;
  String? _selectedTableName;
  String _customerName = 'Walk-in Customer';
  String? _customerPhone;
  double _orderDiscount = 0; // Overall order discount %
  String _orderNotes = '';
  bool _isSubmitting = false; // Debounce guard
  String? _existingOrderId; // Legacy: used to track the first active order
  List<DocumentSnapshot> _ongoingOrders = []; // Generalize to DocumentSnapshot
  String? _activeBranchId; // Explicit branch for this POS session
  String? _registerSessionId; // Active register session ID for order attribution
  StreamSubscription? _ordersSubscription;

  @override
  void dispose() {
    _disposeSubscription();
    super.dispose();
  }

  /// ✅ NEW: Explicit reset for auth lifecycle
  void reset() {
    debugPrint("🧹 Resetting PosService...");
    _disposeSubscription();
    _cartItems.clear();
    _ongoingOrders = [];
    _activeBranchId = null;
    _existingOrderId = null;
    _selectedTableId = null;
    _selectedTableName = null;
    _isSubmitting = false;
    notifyListeners();
  }

  // ── Getters ─────────────────────────────────────────────────
  List<PosCartItem> get cartItems => List.unmodifiable(_cartItems);
  PosOrderType get orderType => _orderType;
  String? get selectedTableId => _selectedTableId;
  String? get selectedTableName => _selectedTableName;
  String get customerName => _customerName;
  String? get customerPhone => _customerPhone;
  double get orderDiscount => _orderDiscount;
  String get orderNotes => _orderNotes;
  bool get isEmpty => _cartItems.isEmpty;
  int get itemCount => _cartItems.fold(0, (acc, item) => acc + item.quantity);
  bool get isAppendMode => _existingOrderId != null;
  List<DocumentSnapshot> get ongoingOrders => _ongoingOrders;
  String? get activeBranchId => _activeBranchId;
  String? get registerSessionId => _registerSessionId;

  void setRegisterSessionId(String? sessionId) {
    _registerSessionId = sessionId;
  }

  double get subtotal => double.parse(_cartItems
      .fold(0.0, (acc, item) => acc + item.subtotal)
      .toStringAsFixed(2));

  double get discountAmount =>
      double.parse((subtotal * (_orderDiscount / 100)).toStringAsFixed(2));

  double get taxAmount => 0; // Configure tax rate if needed

  double get total =>
      double.parse((subtotal - discountAmount + taxAmount).toStringAsFixed(2));

  double get ongoingTotal => double.parse(_ongoingOrders.fold(0.0, (acc, doc) {
        final data = doc.data() as Map<String, dynamic>;
        return acc + PosOrderLifecycle.outstandingAmount(data);
      }).toStringAsFixed(2));

  double get grandTotal =>
      double.parse((total + ongoingTotal).toStringAsFixed(2));

  static double _roundMoney(double value) =>
      double.parse(value.toStringAsFixed(2));

  static Map<String, dynamic> _buildPaymentWriteFields(PosPayment payment) {
    final breakdown =
        payment.splits.isNotEmpty ? payment.splits : <PosPayment>[payment];
    final paymentMethods = <String>[];
    for (final part in breakdown) {
      final method = part.method.trim().toLowerCase();
      if (method.isEmpty || paymentMethods.contains(method)) continue;
      paymentMethods.add(method);
    }

    return {
      'paymentMethod': payment.isSplit ? 'split' : payment.method,
      'paymentMethods': paymentMethods,
      'paymentAmount': _roundMoney(payment.amount),
      'paymentAppliedAmount': _roundMoney(payment.appliedAmount),
      'paymentChange': _roundMoney(payment.change),
      'payments': breakdown.map((part) => part.toMap()).toList(),
    };
  }

  static List<PosPayment> _allocatePaymentAcrossAmounts({
    required PosPayment payment,
    required List<double> dueAmounts,
  }) {
    if (dueAmounts.isEmpty) return const [];

    final normalizedDues = dueAmounts
        .map((amount) => _roundMoney(amount < 0 ? 0 : amount))
        .toList(growable: false);
    final totalDue = _roundMoney(
      normalizedDues.fold(0.0, (dueTotal, amount) => dueTotal + amount),
    );

    if ((payment.appliedAmount - totalDue).abs() > _currencyEpsilon) {
      throw Exception('Payment breakdown does not match the order total');
    }

    if (normalizedDues.length == 1) {
      return <PosPayment>[payment];
    }

    final sourceParts =
        payment.splits.isNotEmpty ? payment.splits : <PosPayment>[payment];
    final orderBreakdowns = List<List<_AllocatedPaymentPart>>.generate(
      normalizedDues.length,
      (_) => <_AllocatedPaymentPart>[],
    );
    final remainingDues = List<double>.from(normalizedDues);

    int currentOrderIndex = 0;
    int? lastTouchedOrderIndex;

    for (final part in sourceParts) {
      var remainingApplied = _roundMoney(part.appliedAmount);
      int? lastOrderForPart;

      while (remainingApplied > _currencyEpsilon &&
          currentOrderIndex < remainingDues.length) {
        final dueRemaining = remainingDues[currentOrderIndex];
        if (dueRemaining <= _currencyEpsilon) {
          currentOrderIndex++;
          continue;
        }

        final appliedSlice = _roundMoney(
          remainingApplied < dueRemaining ? remainingApplied : dueRemaining,
        );
        orderBreakdowns[currentOrderIndex].add(
          _AllocatedPaymentPart(
            method: part.method,
            label: part.label,
            amount: appliedSlice,
            change: 0,
            appliedAmount: appliedSlice,
            timestamp: part.timestamp,
          ),
        );

        remainingDues[currentOrderIndex] =
            _roundMoney(dueRemaining - appliedSlice);
        remainingApplied = _roundMoney(remainingApplied - appliedSlice);
        lastOrderForPart = currentOrderIndex;
        lastTouchedOrderIndex = currentOrderIndex;

        if (remainingDues[currentOrderIndex] <= _currencyEpsilon) {
          currentOrderIndex++;
        }
      }

      final change = _roundMoney(part.change);
      if (change > _currencyEpsilon) {
        final targetIndex = lastOrderForPart ??
            lastTouchedOrderIndex ??
            (normalizedDues.length - 1);
        final targetBreakdown = orderBreakdowns[targetIndex];
        if (targetBreakdown.isNotEmpty && lastOrderForPart == targetIndex) {
          final existing = targetBreakdown.removeLast();
          targetBreakdown.add(
            _AllocatedPaymentPart(
              method: existing.method,
              label: existing.label,
              amount: _roundMoney(existing.amount + change),
              change: _roundMoney(existing.change + change),
              appliedAmount: existing.appliedAmount,
              timestamp: existing.timestamp,
            ),
          );
        } else {
          targetBreakdown.add(
            _AllocatedPaymentPart(
              method: part.method,
              label: part.label,
              amount: change,
              change: change,
              appliedAmount: 0,
              timestamp: part.timestamp,
            ),
          );
        }
      }
    }

    if (remainingDues.any((amount) => amount > _currencyEpsilon)) {
      throw Exception('Unable to allocate guest payments across the order');
    }

    return orderBreakdowns.map((parts) {
      final payments = parts.map((part) => part.toPayment()).toList();
      final amount = _roundMoney(
        payments.fold(
            0.0, (tenderedTotal, part) => tenderedTotal + part.amount),
      );
      final change = _roundMoney(
        payments.fold(0.0, (changeTotal, part) => changeTotal + part.change),
      );
      final appliedAmount = _roundMoney(
        payments.fold(
          0.0,
          (appliedTotal, part) => appliedTotal + part.appliedAmount,
        ),
      );

      if (payments.length == 1) {
        return PosPayment(
          method: payments.first.method,
          label: payments.first.label,
          amount: amount,
          change: change,
          appliedAmount: appliedAmount,
          timestamp: payments.first.timestamp,
        );
      }

      return PosPayment(
        method: 'split',
        label: 'Split Bill',
        amount: amount,
        change: change,
        appliedAmount: appliedAmount,
        splits: payments,
        timestamp: payments.first.timestamp,
      );
    }).toList(growable: false);
  }

  @visibleForTesting
  static List<PosPayment> allocatePaymentAcrossAmountsForTesting({
    required PosPayment payment,
    required List<double> dueAmounts,
  }) {
    return _allocatePaymentAcrossAmounts(
      payment: payment,
      dueAmounts: dueAmounts,
    );
  }

  // ── Cart Operations ─────────────────────────────────────────
  void addItem(PosCartItem item) {
    // Guard: empty product ID
    if (item.productId.trim().isEmpty) return;

    // Check if same product with SAME addons already exists (merge quantities)
    final existingIndex = _cartItems.indexWhere((i) {
      if (i.productId != item.productId) return false;
      if (i.addons.length != item.addons.length) return false;

      // Check if all addons are the same
      for (int k = 0; k < i.addons.length; k++) {
        if (i.addons[k].name != item.addons[k].name ||
            i.addons[k].price != item.addons[k].price) {
          return false;
        }
      }
      return true;
    });

    if (existingIndex != -1) {
      final newQty = _cartItems[existingIndex].quantity + item.quantity;
      _cartItems[existingIndex].quantity = newQty.clamp(1, maxQuantityPerItem);
    } else {
      // Guard: max cart items
      if (_cartItems.length >= maxCartItems) {
        debugPrint('⚠️ Cart full: max $maxCartItems items allowed');
        return;
      }
      _cartItems.add(item);
    }
    notifyListeners();
  }

  void removeItem(int index) {
    if (index >= 0 && index < _cartItems.length) {
      _cartItems.removeAt(index);
      notifyListeners();
    }
  }

  void removeItemById(String productId) {
    _cartItems.removeWhere((i) => i.productId == productId);
    notifyListeners();
  }

  void updateQuantity(int index, int newQuantity) {
    if (index >= 0 && index < _cartItems.length) {
      if (newQuantity <= 0) {
        _cartItems.removeAt(index);
      } else {
        _cartItems[index].quantity = newQuantity.clamp(1, maxQuantityPerItem);
      }
      notifyListeners();
    }
  }

  void updateItemNotes(int index, String notes) {
    if (index >= 0 && index < _cartItems.length) {
      _cartItems[index].notes = notes;
      notifyListeners();
    }
  }

  void updateItemDiscount(int index, double discount) {
    if (index >= 0 && index < _cartItems.length) {
      _cartItems[index].discountPercent = discount.clamp(0, 100);
      notifyListeners();
    }
  }

  void clearCart() {
    _cartItems.clear();
    _selectedTableId = null;
    _selectedTableName = null;
    _existingOrderId = null;
    _customerName = 'Walk-in Customer';
    _customerPhone = null;
    _orderDiscount = 0;
    _orderNotes = '';
    _ongoingOrders = [];
    _activeBranchId = null;
    _disposeSubscription();
    notifyListeners();
  }

  // ── Order Configuration ─────────────────────────────────────
  void setOrderType(PosOrderType type) {
    _orderType = type;
    // Only dine-in needs a table; clear table for takeaway
    if (type == PosOrderType.takeaway) {
      _selectedTableId = null;
      _selectedTableName = null;
    }
    notifyListeners();
  }

  void setActiveBranch(String? branchId) {
    _activeBranchId = branchId;
    notifyListeners();
  }

  void selectTable(String tableId, String tableName) {
    _selectedTableId = tableId;
    _selectedTableName = tableName;
    notifyListeners();
  }

  void setCustomer(String name, {String? phone}) {
    _customerName = name;
    _customerPhone = phone;
    notifyListeners();
  }

  void setOrderDiscount(double discount) {
    _orderDiscount = discount.clamp(0, 100);
    notifyListeners();
  }

  void setOrderNotes(String notes) {
    _orderNotes = notes;
    notifyListeners();
  }

  // ── Cart Validation ─────────────────────────────────────────
  String? validateCart() {
    if (_cartItems.isEmpty) return 'Cart is empty';
    for (final item in _cartItems) {
      if (item.name.trim().isEmpty) return 'Item with empty name found';
      if (item.price < 0) return 'Item "${item.name}" has invalid price';
      if (item.quantity <= 0) return 'Item "${item.name}" has invalid quantity';
    }
    if (_orderType == PosOrderType.dineIn && _selectedTableId == null) {
      return 'Please select a table for dine-in orders';
    }
    return null; // Valid
  }

  // ── Order Submission ────────────────────────────────────────
  /// Loads an existing order into the POS cart for modification.
  /// Used by the Delivery/Orders panel "Load Order" feature.
  Future<void> loadExistingOrder(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final orderTypeStr = data['Order_type']?.toString();

    // 1. Clear current cart (NOT ongoing orders)
    _cartItems.clear();
    _orderDiscount = 0;
    _orderNotes = '';

    // 2. Set Context
    final branchId = data['branchIds'] is List
        ? (data['branchIds'] as List).first.toString()
        : '';
    _activeBranchId = branchId.isNotEmpty ? branchId : null;

    if (orderTypeStr == 'dine_in' && data['tableId'] != null) {
      // For dine-in, we use the full table loading logic which handles ongoing orders
      await loadTableContext(data['tableId'].toString(),
          data['tableNumber']?.toString() ?? 'Table',
          branchIds: [branchId]);
    } else {
      // For takeaway, we set append mode manually
      _orderType = PosOrderType.takeaway;
      _selectedTableId = data['tableId']?.toString();
      _selectedTableName = data['tableNumber']?.toString();
      _startSingleOrderListener(doc.id);
    }

    notifyListeners();
  }

  /// Submits the current cart as an order to Firestore.
  /// Returns the created order document ID.
  Future<String> submitOrder({
    required UserScopeService userScope,
    required List<String> branchIds,
    String initialStatus = AppConstants.statusPending,
  }) async {
    // Debounce: prevent double-tap submission
    if (_isSubmitting) {
      throw Exception('Order is already being submitted');
    }

    final validationError = validateCart();
    if (validationError != null) {
      throw Exception(validationError);
    }

    if (branchIds.isEmpty) {
      throw Exception('No branch selected');
    }
    // POS orders should only be associated with a single branch to avoid cross-branch blocking.
    final primaryBranchId = branchIds.first;
    final singleBranchList = [primaryBranchId];
    final isDineInSubmit =
        _orderType == PosOrderType.dineIn && _selectedTableId != null;

    // 🛠️ FIX: Allow appending for takeaway orders if they were manually loaded
    final canUseCachedTableContext =
        (isDineInSubmit || _orderType == PosOrderType.takeaway) &&
            _activeBranchId == primaryBranchId;

    if (canUseCachedTableContext && _existingOrderId != null) {
      try {
        return await _appendToExistingOrder(
          userScope: userScope,
          branchIds: singleBranchList,
          initialStatus: initialStatus,
        );
      } catch (e, stackTrace) {
        if (!_isRecoverableAppendTargetError(e)) rethrow;

        // If it was already prepaid or otherwise completed, we fall through
        // to create a new order instead of failing.
        _logError(
          'POS: Append target became stale or prepaid, falling back to new order',
          e,
          stackTrace: stackTrace,
        );

        if (isDineInSubmit) {
          await _syncSelectedTableOrders(singleBranchList, notify: false);
          if (_existingOrderId != null) {
            return _appendToExistingOrder(
              userScope: userScope,
              branchIds: singleBranchList,
              initialStatus: initialStatus,
            );
          }
        } else {
          // For takeaway, clear the existing order ID so we create a fresh one
          _existingOrderId = null;
        }
      }
    }

    _isSubmitting = true;
    notifyListeners();

    try {
      final docRef = FirebaseFirestore.instance
          .collection(AppConstants.collectionOrders)
          .doc();
      final String orderId = docRef.id;

      // ── INDUSTRY GRADE FIX: Wrap in Transaction for Table & Counter Safety ──
      // 🛠️ FIX: Explicit <String> generic ensures Flutter Web compilation doesn't fail
      final String finalOrderId = await FirebaseFirestore.instance
          .runTransaction<String>((transaction) async {
        try {
          // 1. ALL READS (Must happen before any writes)
          DocumentSnapshot<Map<String, dynamic>>? branchSnap;
          final branchRef = FirebaseFirestore.instance
              .collection(AppConstants.collectionBranch)
              .doc(primaryBranchId);
          if (_orderType == PosOrderType.dineIn && _selectedTableId != null) {
            branchSnap = await transaction.get(branchRef);
          }

          // 2. LOGIC / CALCULATIONS
          if (branchSnap != null) {
            // 🛠️ FIX: Safer casting for Web
            final data = branchSnap.data();
            final tables =
                (data?['tables'] as Map?)?.cast<String, dynamic>() ?? {};
            final tableDataRaw = tables[_selectedTableId];
            final tableData = tableDataRaw is Map
                ? tableDataRaw.cast<String, dynamic>()
                : null;

            final currentOrderId = tableData?['currentOrderId']?.toString();
            if (tableData?['status'] == 'occupied' &&
                currentOrderId != null &&
                currentOrderId.isNotEmpty) {
              final currentOrderSnap = await transaction.get(
                FirebaseFirestore.instance
                    .collection(AppConstants.collectionOrders)
                    .doc(currentOrderId),
              );
              if (_isActiveOccupyingOrder(currentOrderSnap, _selectedTableId)) {
                throw Exception(
                    'Table already has an active order. Please wait a moment and try again.');
              }
            }
          }

          final orderData =
              _buildOrderData(singleBranchList, userScope, initialStatus);

          // 3. ALL WRITES (Strictly after all reads)

          if (_orderType == PosOrderType.dineIn && _selectedTableId != null) {
            transaction.update(branchRef, {
              'tables.$_selectedTableId.status': 'occupied',
              'tables.$_selectedTableId.currentOrderId': orderId,
            });
          }

          transaction.set(docRef, orderData);

          return orderId;
        } catch (e, stackTrace) {
          _logError('POS: Internal transaction error in submitOrder', e,
              stackTrace: stackTrace);
          rethrow;
        }
      }).timeout(_firestoreWriteTimeout);

      // ── Ingredient deduction (with retry) ──
      // C2 FIX: Ensure deduction is retried on failure so inventory stays accurate.
      final recordedBy = _getRecorder(userScope);
      _deductWithRetry(
        orderId: finalOrderId,
        branchIds: branchIds,
        recordedBy: recordedBy,
      );

      clearCart();
      return finalOrderId;
    } catch (e, stackTrace) {
      if (isDineInSubmit && _isActiveTableConflict(e)) {
        await _syncSelectedTableOrders(branchIds, notify: false);
        if (_existingOrderId != null) {
          return _appendToExistingOrder(
            userScope: userScope,
            branchIds: branchIds,
            initialStatus: initialStatus,
          );
        }
      }
      _logError('POS: Failed to submit order', e, stackTrace: stackTrace);
      if (e is TimeoutException) {
        throw Exception(
            'Network timeout. Check KDS/Orders list before retrying to prevent duplicates.');
      }
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  static String _getRecorder(UserScopeService userScope) {
    return userScope.userIdentifier.isNotEmpty
        ? userScope.userIdentifier
        : (userScope.userEmail.isNotEmpty ? userScope.userEmail : 'system');
  }

  static void _logError(String message, dynamic error,
      {StackTrace? stackTrace}) {
    final unboxedError = _extractBoxedError(error);
    debugPrint('🔴 $message: ${_errorSummary(unboxedError)}');
    if (!identical(unboxedError, error)) {
      debugPrint('🔴 $message (wrapper): ${_errorSummary(error)}');
    }
    if (stackTrace != null) {
      debugPrint('🧵 $message stack: $stackTrace');
    }
    final boxedStack = _extractBoxedStack(error);
    if (boxedStack != null && boxedStack.isNotEmpty) {
      debugPrint('🧵 $message boxed stack: $boxedStack');
    }
    // Integration point for Crashlytics or external logging
  }

  static String displayError(dynamic error) {
    final unboxedError = _extractBoxedError(error);
    final message = _errorSummary(unboxedError);
    final normalized = message.toLowerCase();

    if (normalized.contains('permission-denied') ||
        normalized.contains('missing or insufficient permissions')) {
      return 'Missing Firestore permission. Deploy the updated rules for Orders and Branch.';
    }

    if (normalized.contains('table already has an active order') ||
        normalized.contains('table was just taken by another device')) {
      return 'This table already has an active order. Wait a moment for POS to load it, then submit again.';
    }

    if (normalized.contains('dart exception thrown from converted future')) {
      return 'Firestore transaction failed. Check the deployed rules for Orders and Branch.';
    }

    return message;
  }

  static bool _messageContains(
    dynamic error,
    Iterable<String> fragments,
  ) {
    final message = _errorSummary(_extractBoxedError(error)).toLowerCase();
    for (final fragment in fragments) {
      if (message.contains(fragment.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  static bool _isRecoverableAppendTargetError(dynamic error) {
    return _messageContains(error, const <String>[
      'already prepaid',
      'target order does not exist',
      'may have been completed',
    ]);
  }

  static bool _isActiveTableConflict(dynamic error) {
    return _messageContains(error, const <String>[
      'table already has an active order',
      'table was just taken by another device',
    ]);
  }

  static dynamic _extractBoxedError(dynamic error) {
    dynamic current = error;
    for (int i = 0; i < 3; i++) {
      try {
        final nested = (current as dynamic).error;
        if (nested == null || identical(nested, current)) break;
        current = nested;
      } catch (_) {
        break;
      }
    }
    return current;
  }

  static String? _extractBoxedStack(dynamic error) {
    try {
      final boxedStack = (error as dynamic).stack;
      if (boxedStack == null) return null;
      return boxedStack.toString();
    } catch (_) {
      return null;
    }
  }

  static String _errorSummary(dynamic error) {
    if (error == null) return 'Unknown error';
    if (error is FirebaseException) {
      final code = error.code.trim();
      final message = (error.message ?? '').trim();
      if (code.isNotEmpty && message.isNotEmpty) {
        return 'Firebase $code: $message';
      }
      if (message.isNotEmpty) return message;
    }

    final raw = error.toString().trim();
    const prefix = 'Exception: ';
    if (raw.startsWith(prefix)) {
      return raw.substring(prefix.length).trim();
    }
    return raw;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _fetchActiveDineInOrdersForTable({
    required String tableId,
    required List<String> branchIds,
  }) async {
    if (branchIds.isEmpty) return const [];
    final snapshot = await FirebaseFirestore.instance
        .collection(AppConstants.collectionOrders)
        .where('branchIds', arrayContains: branchIds.first)
        .where('tableId', isEqualTo: tableId)
        .where('Order_type', isEqualTo: PosOrderType.dineIn.firestoreValue)
        .where('status', whereIn: _activeTableStatuses)
        .orderBy('timestamp', descending: false)
        .get();
    return snapshot.docs;
  }

  Future<bool> _syncSelectedTableOrders(
    List<String> branchIds, {
    bool notify = true,
  }) async {
    final tableId = _selectedTableId;
    if (_orderType != PosOrderType.dineIn ||
        tableId == null ||
        branchIds.isEmpty) {
      return false;
    }

    final docs = await _fetchActiveDineInOrdersForTable(
      tableId: tableId,
      branchIds: branchIds,
    );
    final nextOrders = List<DocumentSnapshot>.from(docs);
    QueryDocumentSnapshot<Map<String, dynamic>>? unpaidDoc;
    for (final doc in docs) {
      if (!PosOrderLifecycle.isPaymentCaptured(doc.data())) {
        unpaidDoc = doc;
        break;
      }
    }
    final nextExistingOrderId = unpaidDoc?.id;
    final previousIds =
        _ongoingOrders.map((doc) => doc.id).toList(growable: false);
    final nextIds = docs.map((doc) => doc.id).toList(growable: false);
    final changed = _existingOrderId != nextExistingOrderId ||
        previousIds.join('|') != nextIds.join('|');

    _ongoingOrders = nextOrders;
    _existingOrderId = nextExistingOrderId;
    _activeBranchId = branchIds.first;

    if (notify && changed) {
      notifyListeners();
    }

    return docs.isNotEmpty;
  }

  static bool _isActiveOccupyingOrder(
    DocumentSnapshot<Map<String, dynamic>> orderSnap,
    String? tableId,
  ) {
    if (!orderSnap.exists) return false;
    final data = orderSnap.data();
    if (data == null) return false;
    if (tableId != null && data['tableId']?.toString() != tableId) {
      return false;
    }
    if (data['Order_type']?.toString() != PosOrderType.dineIn.firestoreValue) {
      return false;
    }
    return _activeTableStatuses.contains(data['status']?.toString());
  }

  /// Submits the order and immediately marks it as paid.
  Future<String> submitOrderWithPayment({
    required UserScopeService userScope,
    required List<String> branchIds,
    required PosPayment payment,
    List<DocumentSnapshot> existingOrders = const [],
  }) async {
    // Debounce: prevent double-tap submission
    if (_isSubmitting) {
      throw Exception('Payment is already being processed');
    }

    // Logic change: Allow empty cart if we have ongoing orders to pay
    if (_cartItems.isEmpty && existingOrders.isEmpty) {
      throw Exception('Cart is empty and no ongoing orders found');
    }

    // If we HAVE items in cart, they MUST be valid
    if (_cartItems.isNotEmpty) {
      final validationError = validateCart();
      if (validationError != null) {
        throw Exception(validationError);
      }
    }

    if (branchIds.isEmpty) {
      throw Exception('No branch selected');
    }
    // POS orders should only be associated with a single branch.
    final primaryBranchId = branchIds.first;
    final singleBranchList = [primaryBranchId];

    notifyListeners();

    try {
      final String? orderIdToReturn;
      final tablesToCleanup = <String>{};

      // ── INDUSTRY GRADE FIX: Wrap EVERYTHING in an atomic Transaction ──
      // 🛠️ FIX: Explicit <String?> generic ensures Flutter Web compilation doesn't fail
      orderIdToReturn = await FirebaseFirestore.instance
          .runTransaction<String?>((transaction) async {
        try {
          // 1. ALL READS (Must happen before any writes)
          final List<Map<String, dynamic>> itemsToDeduct = [];
          final List<DocumentSnapshot<Map<String, dynamic>>> orderSnaps = [];
          for (final doc in existingOrders) {
            final orderSnap = await transaction
                .get(doc.reference as DocumentReference<Map<String, dynamic>>);
            if (orderSnap.exists) {
              orderSnaps.add(orderSnap);
              final data = orderSnap.data()!;
              if (data['inventoryDeducted'] != true) {
                final rawItems = data['items'] ?? data['orderItems'] ?? [];
                final items =
                    List<dynamic>.from(rawItems is Iterable ? rawItems : []);
                // 🛠️ FIX: Safer map conversion for Web
                itemsToDeduct.addAll(items
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList());
              }
            }
          }

          // ── MERGE LOGIC: Identify if we can add cart items to an existing unpaid order ──
          DocumentSnapshot<Map<String, dynamic>>? mergeTargetSnap;
          if (_cartItems.isNotEmpty) {
            for (final snap in orderSnaps) {
              if (!PosOrderLifecycle.isPaymentCaptured(snap.data()!)) {
                mergeTargetSnap = snap;
                break;
              }
            }
          }

          if (_cartItems.isNotEmpty) {
            itemsToDeduct.addAll(
                _cartItems.map((item) => item.toOrderItemMap()).toList());
          }

          DocumentReference? newOrderDocRef;
          String? newOrderId;
          if (_cartItems.isNotEmpty && mergeTargetSnap == null) {
            newOrderDocRef = FirebaseFirestore.instance
                .collection(AppConstants.collectionOrders)
                .doc();
            newOrderId = newOrderDocRef.id;
          } else if (mergeTargetSnap != null) {
            newOrderId = mergeTargetSnap.id;
          }

          final perOrderPayments = <String, PosPayment>{};
          PosPayment? newOrderPayment;
          final paymentDues = <double>[];
          final unpaidOrderIds = <String>[];

          for (final snap in orderSnaps) {
            final data = snap.data()!;
            if (PosOrderLifecycle.isPaymentCaptured(data)) continue;

            double due = PosOrderLifecycle.outstandingAmount(data);
            if (snap.id == mergeTargetSnap?.id) {
              due += total; // Merge cart items total into this order's due
            }

            if (due <= _currencyEpsilon) continue;
            unpaidOrderIds.add(snap.id);
            paymentDues.add(_roundMoney(due));
          }

          if (newOrderDocRef != null && newOrderId != null) {
            paymentDues.add(_roundMoney(total));
          }

          if (paymentDues.isEmpty) {
            throw Exception('Nothing left to pay for this bill');
          }

          final totalDue = _roundMoney(
            paymentDues.fold(0.0, (dueTotal, amount) => dueTotal + amount),
          );
          if ((payment.appliedAmount - totalDue).abs() > _currencyEpsilon) {
            throw Exception('Collected amount does not match the bill total');
          }

          final allocatedPayments = _allocatePaymentAcrossAmounts(
            payment: payment,
            dueAmounts: paymentDues,
          );

          var allocationIndex = 0;
          for (final orderId in unpaidOrderIds) {
            perOrderPayments[orderId] = allocatedPayments[allocationIndex++];
          }
          if (newOrderDocRef != null && newOrderId != null) {
            newOrderPayment = allocatedPayments[allocationIndex];
          }

          if (itemsToDeduct.isNotEmpty) {
            await InventoryService().deductItemsInTransaction(
              transaction: transaction,
              items: itemsToDeduct,
              branchIds: singleBranchList,
              orderId: newOrderId ??
                  (existingOrders.isNotEmpty
                      ? existingOrders.first.id
                      : 'unknown'),
              recordedBy: _getRecorder(userScope),
            );
          }

          // 2. ALL WRITES
          if (newOrderDocRef != null && newOrderId != null) {
            final newOrderData = _buildOrderData(
                singleBranchList, userScope, AppConstants.statusPending);
            if (newOrderPayment == null) {
              throw Exception('Missing payment allocation for new order');
            }
            newOrderData.addAll(_buildPaymentWriteFields(newOrderPayment));
            newOrderData['isPaid'] = true;
            newOrderData['paidAt'] = FieldValue.serverTimestamp();
            newOrderData['timestamps.${AppConstants.statusPaid}'] =
                FieldValue.serverTimestamp();
            newOrderData['inventoryDeducted'] = true;
            newOrderData['orderStatus'] = AppConstants.statusPending;
            newOrderData['paymentStatus'] = PosOrderLifecycle.paymentPaid;

            transaction.set(newOrderDocRef, newOrderData);
          }

          for (final snap in orderSnaps) {
            final docData = snap.data()!;
            final isAlreadyPaid = PosOrderLifecycle.isPaymentCaptured(docData);

            if (!isAlreadyPaid) {
              final currentStage = PosOrderLifecycle.stageFromData(docData);
              final orderType = PosOrderLifecycle.orderTypeFromData(docData);
              final terminalStatus =
                  PosOrderLifecycle.terminalStatusForOrderType(orderType);
              final allocatedPayment = perOrderPayments[snap.id];
              if (allocatedPayment == null) {
                throw Exception(
                    'Missing payment allocation for order ${snap.id}');
              }

              final updateData = <String, dynamic>{
                ..._buildPaymentWriteFields(allocatedPayment),
                'isPaid': true,
                'paidAt': FieldValue.serverTimestamp(),
                'timestamps.${AppConstants.statusPaid}':
                    FieldValue.serverTimestamp(),
                'inventoryDeducted': true,
                'paymentStatus': PosOrderLifecycle.paymentPaid,
              };

              // ── MERGE WRITE LOGIC ──
              if (snap.id == mergeTargetSnap?.id) {
                // Support both 'items' and 'orderItems' field names
                final existingItemsRaw =
                    docData['items'] ?? docData['orderItems'] ?? [];
                final existingItems = List<dynamic>.from(
                        existingItemsRaw is Iterable ? existingItemsRaw : [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();

                final int previousAddOnRound =
                    (docData['addOnRound'] as num?)?.toInt() ?? 0;
                final int newAddOnRound = previousAddOnRound + 1;
                final int previousItemCount = existingItems.length;

                // If adding new items, the order status should revert to 'preparing'
                // for the kitchen, while the payment status becomes 'paid'.
                final bool isAlreadyPrepared =
                    currentStage == AppConstants.statusPrepared ||
                        currentStage == AppConstants.statusServed;

                if (isAlreadyPrepared) {
                  // Mark old items as completed so they stay struck through
                  updateData['completedItems'] =
                      List.generate(previousItemCount, (i) => i);
                  updateData['status'] = AppConstants.statusPreparing;
                }

                // CRITICAL: Always reset these if new items are added to ensure KDS visibility
                updateData['orderStatus'] = AppConstants.statusPreparing;
                updateData['status'] =
                    updateData['status'] ?? AppConstants.statusPreparing;
                updateData['isKdsDismissed'] = false;

                for (final cartItem in _cartItems) {
                  final addOnItem = cartItem.copyWith()..isAddOn = true;
                  final map = addOnItem.toOrderItemMap();
                  map['addOnRound'] = newAddOnRound;
                  existingItems.add(map);
                }

                double newSubtotal = 0;
                int newItemCount = 0;
                for (final item in existingItems) {
                  final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                  final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                  newSubtotal += price * qty;
                  newItemCount += qty;
                }
                newSubtotal = _roundMoney(newSubtotal);

                final discountPct =
                    (docData['discountPercent'] as num?)?.toDouble() ?? 0.0;
                final discountAmt =
                    _roundMoney(newSubtotal * (discountPct / 100));
                final tax = (docData['tax'] as num?)?.toDouble() ?? 0.0;
                final newTotal = _roundMoney(newSubtotal - discountAmt + tax);

                updateData.addAll({
                  'items': existingItems,
                  'subtotal': newSubtotal,
                  'totalAmount': newTotal,
                  'discount': discountAmt,
                  'itemCount': newItemCount,
                  'addOnRound': newAddOnRound,
                  'previousItemCount': previousItemCount,
                  'hasActiveAddOns': true,
                });
              }

              // Finalize check AFTER possibly merging
              final fullDataForFinalize = {...docData, ...updateData};
              final shouldFinalize = PosOrderLifecycle.shouldFinalizeOnPayment(
                  fullDataForFinalize);

              // 🛠️ CRITICAL FIX: Even if shouldFinalize is true, if we just added
              // new items to an existing order, we must keep it in 'preparing'
              // so the kitchen sees the new items.
              final bool hasExplicitNewItems =
                  snap.id == mergeTargetSnap?.id && _cartItems.isNotEmpty;

              if (shouldFinalize && !hasExplicitNewItems) {
                updateData['status'] = terminalStatus;
                updateData['orderStatus'] = PosOrderLifecycle.stageCompleted;
                updateData['completedAt'] = FieldValue.serverTimestamp();
                if (orderType == AppConstants.orderTypeDineIn) {
                  final tableId = docData['tableId']?.toString();
                  if (tableId != null && tableId.isNotEmpty) {
                    tablesToCleanup.add(tableId);
                  }
                }
                if (terminalStatus == AppConstants.statusCollected) {
                  updateData['collectedAt'] = FieldValue.serverTimestamp();
                  updateData['timestamps.${AppConstants.statusCollected}'] =
                      FieldValue.serverTimestamp();
                }
              } else {
                updateData['status'] =
                    updateData['status'] ?? docData['status'];
                updateData['orderStatus'] = updateData['orderStatus'] ??
                    PosOrderLifecycle.stageFromData(docData);
              }

              transaction.update(snap.reference, updateData);
            }
          }

          return newOrderId ??
              (existingOrders.isNotEmpty ? existingOrders.first.id : null);
        } catch (e, stackTrace) {
          _logError(
              'POS: Internal transaction error in submitOrderWithPayment', e,
              stackTrace: stackTrace);
          rethrow;
        }
      }).timeout(_firestoreWriteTimeout);

      for (final tableId in tablesToCleanup) {
        await cleanupTableIfEmpty(branchIds: singleBranchList, tableId: tableId);
      }

      clearCart();
      return orderIdToReturn ?? 'paid';
    } catch (e, stackTrace) {
      _logError('POS: Payment submission failed', e, stackTrace: stackTrace);
      if (e is TimeoutException) {
        throw Exception(
            'Network timeout during payment. Verify status in Orders list before retrying.');
      }
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Map<String, dynamic> _buildOrderData(
    List<String> branchIds,
    UserScopeService userScope,
    String status,
  ) {
    final DateTime now = DateTime.now();
    final DateTime autoAcceptDeadline = now.add(_kitchenResponseTimeout);
    final bool isPendingKitchenDecision = status == AppConstants.statusPending;
    return {
      'branchIds': branchIds,
      'branchId': branchIds.isNotEmpty ? branchIds.first : null,
      'source': 'pos',
      // ── SYNC FIX: Write BOTH field names so all screens can find this order ──
      'Order_type': _orderType.firestoreValue, // Queried by OrderService
      'orderType': _orderType.firestoreValue, // Used by KDS fallback
      'status': status,
      'items': _cartItems.map((item) => item.toOrderItemMap()).toList(),
      'customerName': _customerName,
      if (_customerPhone != null) 'customerPhone': _customerPhone,
      if (_selectedTableId != null) 'tableId': _selectedTableId,
      if (_selectedTableName != null) 'tableName': _selectedTableName,
      // ── SYNC FIX: Add tableNumber (read by OrdersScreenLarge) ──
      if (_selectedTableName != null) 'tableNumber': _selectedTableName,
      'subtotal': subtotal,
      'discount': discountAmount,
      'discountPercent': _orderDiscount,
      'tax': taxAmount,
      'totalAmount': total,
      'itemCount': itemCount,
      if (_orderNotes.isNotEmpty) 'notes': _orderNotes,
      if (_orderNotes.isNotEmpty) 'specialInstructions': _orderNotes,
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': userScope.userIdentifier,
      'kotPrinted': true,
      'posOrder': true,
      // The shared order number is assigned by the backend so every source
      // (POS, dine-in, takeaway, delivery) uses the same sequence.
      // ── New Dual Status fields ──
      'orderStatus': getOrderStatus({'status': status}),
      'paymentStatus': getPaymentStatus(
          {'status': status, 'isPaid': status == AppConstants.statusPaid}),
      'timestamps.$status': FieldValue.serverTimestamp(),
      if (isPendingKitchenDecision) 'pendingAt': FieldValue.serverTimestamp(),
      // ── New fields for improved POS order logic ──
      'autoAcceptDeadline': Timestamp.fromDate(autoAcceptDeadline),
      'isAutoAccepted': false,
      'kitchenDecisionStatus': isPendingKitchenDecision
          ? PosOrderLifecycle.kitchenDecisionPending
          : PosOrderLifecycle.kitchenDecisionAccepted,
      // POS orders should NEVER show popup alerts for admin accept/reject
      'showPopupAlert': false,
      // C2 FIX: Explicitly track inventory deduction state for non-payment orders
      'inventoryDeducted': false,
      // Register session attribution for analytics
      if (_registerSessionId != null) 'registerSessionId': _registerSessionId,
    };
  }

  /// C2 FIX: Retries inventory deduction up to 2 times on failure.
  /// Prevents silent stock drift when fire-and-forget deduction fails.
  void _deductWithRetry({
    required String orderId,
    required List<String> branchIds,
    required String recordedBy,
    int attempt = 1,
  }) {
    InventoryService()
        .deductForOrder(
          orderId: orderId,
          branchIds: branchIds,
          recordedBy: recordedBy,
        )
        .catchError((e) {
      _logError('POS: Ingredient deduction failed (attempt $attempt)', e);
      if (attempt < 3) {
        Future.delayed(Duration(seconds: attempt * 2), () {
          _deductWithRetry(
            orderId: orderId,
            branchIds: branchIds,
            recordedBy: recordedBy,
            attempt: attempt + 1,
          );
        });
      } else {
        _logError(
          'POS: Ingredient deduction PERMANENTLY FAILED for order $orderId after 3 attempts',
          e,
        );
      }
    });
  }

  /// Complete payment for an existing order.
  /// Only frees the table if no other active orders remain on it.
  /// INDUSTRY GRADE: Transactional logic with atomic inventory deduction.
  Future<void> completePayment({
    required String orderId,
    required PosPayment payment,
    required UserScopeService userScope,
    String? tableId,
    List<String>? branchIds,
  }) async {
    final effectiveBranchIds = branchIds ??
        (userScope.branchIds.isNotEmpty ? userScope.branchIds : <String>[]);
    String? resolvedTableId = tableId;
    List<String> resolvedBranchIds = effectiveBranchIds;
    bool shouldCleanupTable = false;

    try {
      await FirebaseFirestore.instance
          .runTransaction<void>((transaction) async {
        final orderRef = FirebaseFirestore.instance
            .collection(AppConstants.collectionOrders)
            .doc(orderId);
        final orderSnap = await transaction.get(orderRef);
        if (!orderSnap.exists) throw Exception("Order not found");

        final orderData = orderSnap.data()!;
        if (PosOrderLifecycle.isCancelled(orderData) ||
            PosOrderLifecycle.isCompleted(orderData)) {
          throw Exception("Order is already closed");
        }
        if (PosOrderLifecycle.isPaymentCaptured(orderData)) {
          throw Exception("Order is already paid");
        }

        final orderType = PosOrderLifecycle.orderTypeFromData(orderData);
        final currentStage = PosOrderLifecycle.stageFromData(orderData);
        final terminalStatus =
            PosOrderLifecycle.terminalStatusForOrderType(orderType);
        final finalizeNow =
            PosOrderLifecycle.shouldFinalizeOnPayment(orderData);

        final orderBranchIds = orderData['branchIds'] is List
            ? List<String>.from(orderData['branchIds'] as List)
            : <String>[];
        if (resolvedBranchIds.isEmpty) {
          resolvedBranchIds = orderBranchIds;
        }
        resolvedTableId ??= orderData['tableId']?.toString();

        await InventoryService().performDeductionInTransaction(
          transaction: transaction,
          orderId: orderId,
          branchIds: resolvedBranchIds,
          recordedBy: _getRecorder(userScope),
        );

        final updateData = <String, dynamic>{
          ..._buildPaymentWriteFields(payment),
          'isPaid': true,
          'paidAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
          'paymentStatus': PosOrderLifecycle.paymentPaid,
          'timestamps.${AppConstants.statusPaid}': FieldValue.serverTimestamp(),
          'inventoryDeducted': true,
        };

        if (finalizeNow) {
          updateData['status'] = terminalStatus;
          updateData['orderStatus'] = PosOrderLifecycle.stageCompleted;
          updateData['completedAt'] = FieldValue.serverTimestamp();
          if (terminalStatus == AppConstants.statusCollected) {
            updateData['collectedAt'] = FieldValue.serverTimestamp();
            updateData['timestamps.${AppConstants.statusCollected}'] =
                FieldValue.serverTimestamp();
          }
          shouldCleanupTable = orderType == AppConstants.orderTypeDineIn;
        } else {
          updateData['status'] = orderData['status'];
          updateData['orderStatus'] = currentStage;
        }

        transaction.update(orderRef, updateData);
      }).timeout(_firestoreWriteTimeout);

      if (shouldCleanupTable &&
          resolvedTableId != null &&
          resolvedBranchIds.isNotEmpty) {
        await cleanupTableIfEmpty(
          branchIds: resolvedBranchIds,
          tableId: resolvedTableId!,
        );
      }
      notifyListeners();
    } catch (e) {
      _logError('POS: Failed to complete payment', e);
      rethrow;
    }
  }

  static Future<void> _updateTableStatus(
      List<String> branchIds, String tableId, String status) async {
    try {
      if (branchIds.isEmpty) return;
      final primaryBranchId = branchIds.first;
      final branchDoc = FirebaseFirestore.instance
          .collection(AppConstants.collectionBranch)
          .doc(primaryBranchId);

      final Map<String, dynamic> updates = {
        'tables.$tableId.status': status,
      };

      if (status == 'available') {
        updates['tables.$tableId.currentOrderId'] = FieldValue.delete();
      }

      await branchDoc.update(updates);
    } catch (e) {
      debugPrint('⚠️ POS: Failed to update table status: $e');
    }
  }

  // ── Order Management (Instance Methods for Provider Compatibility) ──

  Future<void> recallOrder(String orderId, String reason) async {
    try {
      final orderRef = FirebaseFirestore.instance
          .collection(AppConstants.collectionOrders)
          .doc(orderId);
      final snap = await orderRef.get();
      if (!snap.exists) throw Exception("Order not found");

      final data = snap.data() as Map<String, dynamic>;
      final os = PosOrderLifecycle.stageFromData(data);

      if (os == PosOrderLifecycle.stageCompleted ||
          os == PosOrderLifecycle.stageCancelled) {
        throw Exception("Cannot recall order in $os status");
      }

      await orderRef.update({
        'status': AppConstants.statusPreparing,
        'orderStatus': 'preparing',
        'recallReason': reason,
        'recalledAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
        'timestamps.recalled': FieldValue.serverTimestamp(),
        'timestamps.preparing': FieldValue.serverTimestamp(),
        'completedItems': [], // [MOD] Clear strikethroughs on recall
      });
      notifyListeners();
    } catch (e) {
      _logError('POS: Failed to recall order', e);
      rethrow;
    }
  }

  Future<void> acceptKitchenPendingOrder({
    required String orderId,
    required UserScopeService userScope,
    bool isAutoAccepted = false,
    String? acceptedBy,
  }) async {
    final recordedBy = acceptedBy ?? _getRecorder(userScope);
    final decisionStatus = isAutoAccepted
        ? PosOrderLifecycle.kitchenDecisionAutoAccepted
        : PosOrderLifecycle.kitchenDecisionAccepted;

    try {
      await FirebaseFirestore.instance
          .runTransaction<void>((transaction) async {
        final orderRef = FirebaseFirestore.instance
            .collection(AppConstants.collectionOrders)
            .doc(orderId);
        final orderSnap = await transaction.get(orderRef);

        if (!orderSnap.exists) throw Exception("Order not found");
        final orderData = orderSnap.data()!;

        if (!PosOrderLifecycle.requiresChefDecision(orderData)) {
          final currentStage = PosOrderLifecycle.stageFromData(orderData);
          if (currentStage == AppConstants.statusPreparing) return;
          throw Exception('Order is no longer awaiting kitchen confirmation.');
        }

        transaction.update(orderRef, {
          'status': AppConstants.statusPreparing,
          'orderStatus': AppConstants.statusPreparing,
          'preparingAt': FieldValue.serverTimestamp(),
          'acceptedAt': FieldValue.serverTimestamp(),
          'acceptedBy': recordedBy,
          'isAutoAccepted': isAutoAccepted,
          'kitchenDecisionStatus': decisionStatus,
          'kitchenDecisionAt': FieldValue.serverTimestamp(),
          'kitchenDecisionBy': recordedBy,
          'lastUpdated': FieldValue.serverTimestamp(),
          'timestamps.${AppConstants.statusPreparing}':
              FieldValue.serverTimestamp(),
        });
      }).timeout(const Duration(seconds: 15), onTimeout: () {
        throw TimeoutException('KDS auto-accept took too long (Firestore contention?)');
      });

      notifyListeners();
    } catch (e, stackTrace) {
      _logError('POS: Failed to accept pending kitchen order', e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> rejectKitchenPendingOrder({
    required String orderId,
    required String reason,
    required UserScopeService userScope,
    String? tableId,
    List<String>? branchIds,
  }) async {
    final effectiveBranchIds = branchIds ??
        (userScope.branchIds.isNotEmpty ? userScope.branchIds : <String>[]);
    final recordedBy = _getRecorder(userScope);
    final sanitizedReason = reason.trim();
    if (sanitizedReason.isEmpty) {
      throw Exception('Cancellation reason is required.');
    }

    try {
      await FirebaseFirestore.instance
          .runTransaction<void>((transaction) async {
        final orderRef = FirebaseFirestore.instance
            .collection(AppConstants.collectionOrders)
            .doc(orderId);
        final orderSnap = await transaction.get(orderRef);

        if (!orderSnap.exists) throw Exception("Order not found");
        final orderData = orderSnap.data()!;

        if (!PosOrderLifecycle.requiresChefDecision(orderData)) {
          if (PosOrderLifecycle.isCancelled(orderData)) return;
          throw Exception('Order is no longer awaiting kitchen confirmation.');
        }

        if (orderData['inventoryDeducted'] == true &&
            orderData['inventoryRestored'] != true) {
          final rawItemsData =
              orderData['items'] ?? orderData['orderItems'] ?? [];
          final rawItems =
              List<dynamic>.from(rawItemsData is Iterable ? rawItemsData : []);
          if (rawItems.isNotEmpty) {
            await InventoryService().restoreItemsInTransaction(
              transaction: transaction,
              items: rawItems
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
              branchIds: effectiveBranchIds,
              orderId: orderId,
              recordedBy: recordedBy,
              reason: 'Order rejected by kitchen',
            );
          }
        }

        final isPaid = orderData['isPaid'] == true ||
            getPaymentStatus(orderData) == PosOrderLifecycle.paymentPaid;
        transaction.update(orderRef, {
          'status': AppConstants.statusCancelled,
          'orderStatus': PosOrderLifecycle.stageCancelled,
          'paymentStatus': isPaid
              ? PosOrderLifecycle.paymentRefunded
              : PosOrderLifecycle.paymentUnpaid,
          'inventoryRestored': true,
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelledBy': recordedBy,
          'cancelledFromKitchen': true,
          'cancellationReason': sanitizedReason,
          'rejectedBy': recordedBy,
          'rejectedAt': FieldValue.serverTimestamp(),
          'kitchenDecisionStatus': PosOrderLifecycle.kitchenDecisionRejected,
          'kitchenDecisionAt': FieldValue.serverTimestamp(),
          'kitchenDecisionBy': recordedBy,
          'lastUpdated': FieldValue.serverTimestamp(),
          'timestamps.cancelled': FieldValue.serverTimestamp(),
          'timestamps.orderStatus_cancelled': FieldValue.serverTimestamp(),
        });
      }).timeout(_firestoreWriteTimeout);

      // H1 FIX: Await cleanup to prevent ghost tables
      if (tableId != null && effectiveBranchIds.isNotEmpty) {
        try {
          await cleanupTableIfEmpty(branchIds: effectiveBranchIds, tableId: tableId);
        } catch (e) {
          _logError('POS: Table cleanup failed after kitchen rejection', e);
        }
      }
      notifyListeners();
    } catch (e) {
      _logError('POS: Failed to reject pending kitchen order', e);
      rethrow;
    }
  }

  Future<void> cancelOrder({
    required String orderId,
    required UserScopeService userScope,
    String? tableId,
    List<String>? branchIds,
  }) async {
    final effectiveBranchIds = branchIds ??
        (userScope.branchIds.isNotEmpty ? userScope.branchIds : <String>[]);
    final recordedBy = _getRecorder(userScope);

    try {
      await FirebaseFirestore.instance
          .runTransaction<void>((transaction) async {
        final orderRef = FirebaseFirestore.instance
            .collection(AppConstants.collectionOrders)
            .doc(orderId);
        final orderSnap = await transaction.get(orderRef);

        if (!orderSnap.exists) throw Exception("Order not found");
        final orderData = orderSnap.data()!;
        final currentStatus = orderData['status']?.toString() ?? '';

        if (currentStatus == AppConstants.statusPrepared ||
            currentStatus == AppConstants.statusServed) {
          throw Exception(
              "Cannot cancel an order that is already ${currentStatus.toUpperCase()}.");
        }

        if (orderData['inventoryDeducted'] == true &&
            orderData['inventoryRestored'] != true) {
          final rawItemsData =
              orderData['items'] ?? orderData['orderItems'] ?? [];
          final rawItems =
              List<dynamic>.from(rawItemsData is Iterable ? rawItemsData : []);
          if (rawItems.isNotEmpty) {
            await InventoryService().restoreItemsInTransaction(
              transaction: transaction,
              items: rawItems
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
              branchIds: effectiveBranchIds,
              orderId: orderId,
              recordedBy: recordedBy,
              reason: 'Order cancelled via POS',
            );
          }
        }

        // L2 FIX: Use constants instead of string literals
        final isPaid = orderData['isPaid'] == true ||
            getPaymentStatus(orderData) == PosOrderLifecycle.paymentPaid;
        transaction.update(orderRef, {
          'status': AppConstants.statusCancelled,
          'orderStatus': PosOrderLifecycle.stageCancelled,
          'paymentStatus': isPaid
              ? PosOrderLifecycle.paymentRefunded
              : PosOrderLifecycle.paymentUnpaid,
          'inventoryRestored': true,
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelledBy': recordedBy,
          'timestamps.cancelled': FieldValue.serverTimestamp(),
          'timestamps.orderStatus_cancelled': FieldValue.serverTimestamp(),
        });
      }).timeout(_firestoreWriteTimeout);

      // H1 FIX: Await cleanup to prevent ghost tables
      if (tableId != null && effectiveBranchIds.isNotEmpty) {
        try {
          await cleanupTableIfEmpty(branchIds: effectiveBranchIds, tableId: tableId);
        } catch (e) {
          _logError('POS: Table cleanup failed after cancellation', e);
        }
      }
      notifyListeners();
    } catch (e) {
      _logError('POS: Failed to cancel order', e);
      rethrow;
    }
  }

  Future<void> removeItemFromOrder({
    required String orderId,
    required int itemIndex,
    required UserScopeService userScope,
    List<String>? branchIds,
  }) async {
    final effectiveBranchIds = branchIds ??
        (userScope.branchIds.isNotEmpty ? userScope.branchIds : <String>[]);
    final recordedBy = _getRecorder(userScope);

    try {
      await FirebaseFirestore.instance
          .runTransaction<void>((transaction) async {
        final orderRef = FirebaseFirestore.instance
            .collection(AppConstants.collectionOrders)
            .doc(orderId);
        final orderSnap = await transaction.get(orderRef);

        if (!orderSnap.exists) throw Exception("Order not found");
        final orderData = orderSnap.data()!;
        final currentStatus = orderData['status']?.toString() ?? '';

        if (currentStatus == AppConstants.statusPrepared ||
            currentStatus == AppConstants.statusServed) {
          throw Exception(
              "Cannot remove items from an order that is already ${currentStatus.toUpperCase()}.");
        }

        final items = List<Map<String, dynamic>>.from(orderData['items'] ?? []);
        if (itemIndex < 0 || itemIndex >= items.length) {
          throw Exception("Invalid item index");
        }

        final removedItem = items.removeAt(itemIndex);
        removedItem['isCancelled'] = true;
        removedItem['cancelledAt'] = DateTime.now().toIso8601String();

        if (orderData['inventoryDeducted'] == true) {
          await InventoryService().restoreItemsInTransaction(
            transaction: transaction,
            items: [removedItem],
            branchIds: effectiveBranchIds,
            orderId: orderId,
            recordedBy: recordedBy,
            reason: 'Item removed from order via POS',
          );
        }

        double newSubtotal = 0;
        int newItemCount = 0;
        for (final item in items) {
          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
          final price = (item['price'] as num?)?.toDouble() ?? 0.0;
          newSubtotal += price * qty;
          newItemCount += qty;
        }

        final discountPct =
            (orderData['discountPercent'] as num?)?.toDouble() ?? 0.0;
        final discountAmt = double.parse(
            (newSubtotal * (discountPct / 100)).toStringAsFixed(2));
        final tax = (orderData['tax'] as num?)?.toDouble() ?? 0.0;
        final newTotal =
            double.parse((newSubtotal - discountAmt + tax).toStringAsFixed(2));

        final cancelledItems =
            List<Map<String, dynamic>>.from(orderData['cancelledItems'] ?? []);
        cancelledItems.add(removedItem);

        if (items.isEmpty) {
          final wasPaid = PosOrderLifecycle.isPaymentCaptured(orderData);
          // L2 FIX: Use constants instead of string literals
          transaction.update(orderRef, {
            'items': [],
            'cancelledItems': cancelledItems,
            'subtotal': 0,
            'totalAmount': 0,
            'status': AppConstants.statusCancelled,
            'orderStatus': PosOrderLifecycle.stageCancelled,
            'paymentStatus': wasPaid
                ? PosOrderLifecycle.paymentRefunded
                : PosOrderLifecycle.paymentUnpaid,
            'cancelledAt': FieldValue.serverTimestamp(),
            'timestamps.cancelled': FieldValue.serverTimestamp(),
            // C3 FIX: Flag for accounting review if order was paid
            if (wasPaid) 'requiresRefundReview': true,
          });
        } else {
          // C3 FIX: Adjust payment tracking when items are removed from paid orders
          final updateFields = <String, dynamic>{
            'items': items,
            'cancelledItems': cancelledItems,
            'subtotal': newSubtotal,
            'totalAmount': newTotal,
            'discount': discountAmt,
            'itemCount': newItemCount,
            'lastUpdated': FieldValue.serverTimestamp(),
          };
          if (PosOrderLifecycle.isPaymentCaptured(orderData)) {
            updateFields['paymentAppliedAmount'] = newTotal;
            updateFields['requiresRefundReview'] = true;
          }
          transaction.update(orderRef, updateFields);
        }
      }).timeout(_firestoreWriteTimeout);
      notifyListeners();
    } catch (e) {
      _logError('POS: Failed to remove item from order', e);
      rethrow;
    }
  }

  Future<void> updateOrderStatus(
    String orderId,
    String newStatus, {
    Map<String, dynamic>? currentData,
  }) async {
    try {
      final orderRef = FirebaseFirestore.instance
          .collection(AppConstants.collectionOrders)
          .doc(orderId);

      // Reuse the live order snapshot when the caller already has it.
      final Map<String, dynamic> data;
      if (currentData != null) {
        data = Map<String, dynamic>.from(currentData);
      } else {
        final snap = await orderRef.get();
        if (!snap.exists) throw Exception('Order not found');
        data = snap.data() ?? <String, dynamic>{};
      }
      final orderType = PosOrderLifecycle.orderTypeFromData(data);
      final currentStage = PosOrderLifecycle.stageFromData(data);
      final normalizedStage = PosOrderLifecycle.normalizeOrderStage(newStatus);
      final terminalStatus =
          PosOrderLifecycle.terminalStatusForOrderType(orderType);

      final updateData = <String, dynamic>{
        'orderStatus': normalizedStage,
        'status': newStatus,
        'lastUpdated': FieldValue.serverTimestamp(),
        'timestamps.$newStatus': FieldValue.serverTimestamp(),
      };

      if (newStatus == AppConstants.statusPrepared) {
        updateData['preparedAt'] = FieldValue.serverTimestamp();
        // [MOD] Populate completedItems for KDS persistence
        final items = (data['items'] ?? []) as List<dynamic>;
        updateData['completedItems'] = List.generate(items.length, (i) => i);
      }
      if (newStatus == AppConstants.statusServed) {
        updateData['servedAt'] = FieldValue.serverTimestamp();
        // [MOD] Populate completedItems for KDS persistence
        final items = (data['items'] ?? []) as List<dynamic>;
        updateData['completedItems'] = List.generate(items.length, (i) => i);
      }
      if (newStatus == AppConstants.statusPaid) {
        updateData['paymentStatus'] = PosOrderLifecycle.paymentPaid;
        updateData['isPaid'] = true;
        if (!PosOrderLifecycle.isPaymentCaptured(data)) {
          updateData['paidAt'] = FieldValue.serverTimestamp();
        }
      }
      if (newStatus == AppConstants.statusCollected) {
        updateData['collectedAt'] = FieldValue.serverTimestamp();
        updateData['paymentStatus'] = PosOrderLifecycle.paymentPaid;
        updateData['isPaid'] = true;
      }

      final shouldAutoComplete =
          PosOrderLifecycle.shouldAutoCompleteOnKitchenUpdate(data, newStatus);
      final isTerminalRequest = newStatus == AppConstants.statusPaid ||
          newStatus == AppConstants.statusCollected ||
          newStatus == AppConstants.statusDelivered;

      if (shouldAutoComplete || isTerminalRequest) {
        updateData['status'] = shouldAutoComplete ? terminalStatus : newStatus;
        updateData['orderStatus'] = PosOrderLifecycle.stageCompleted;
        updateData['completedAt'] = FieldValue.serverTimestamp();
      } else if (normalizedStage == PosOrderLifecycle.stageCancelled) {
        updateData['orderStatus'] = PosOrderLifecycle.stageCancelled;
      }

      await orderRef.update(updateData);

      final shouldCleanupTable = orderType == AppConstants.orderTypeDineIn &&
          (shouldAutoComplete ||
              (isTerminalRequest &&
                  currentStage != PosOrderLifecycle.stageCancelled));
      if (shouldCleanupTable) {
        final tableId = data['tableId']?.toString();
        final branchIdsList = data['branchIds'] as List<dynamic>?;
        if (tableId != null &&
            branchIdsList != null &&
            branchIdsList.isNotEmpty) {
          await cleanupTableIfEmpty(
              branchIds: branchIdsList.cast<String>(), tableId: tableId);
        }
      }

      notifyListeners();
    } catch (e) {
      _logError('POS: Failed to update order status', e);
      rethrow;
    }
  }

  Future<void> updatePaymentStatus(String orderId, String newStatus,
      {PosPayment? payment}) async {
    try {
      final updateData = <String, dynamic>{
        'paymentStatus': newStatus,
        'lastUpdated': FieldValue.serverTimestamp(),
        'timestamps.$newStatus': FieldValue.serverTimestamp(),
      };
      if (newStatus == 'paid' && payment != null) {
        updateData.addAll(_buildPaymentWriteFields(payment));
        updateData['isPaid'] = true;
        updateData['paidAt'] = FieldValue.serverTimestamp();
      }
      await FirebaseFirestore.instance
          .collection(AppConstants.collectionOrders)
          .doc(orderId)
          .update(updateData);
      notifyListeners();
    } catch (e) {
      _logError('POS: Failed to update payment status', e);
      rethrow;
    }
  }

  Future<bool> completeOrderWithDualCheck({
    String? orderId,
    String? tableId,
    List<String>? branchIds,
  }) async {
    try {
      if (orderId != null) {
        final orderRef = FirebaseFirestore.instance
            .collection(AppConstants.collectionOrders)
            .doc(orderId);
        final snapshot = await orderRef.get();
        if (!snapshot.exists) throw Exception("Order not found");
        final data = snapshot.data()!;
        if (getOrderStatus(data) != 'served' ||
            getPaymentStatus(data) != 'paid') {
          return false;
        }
        await orderRef.update({
          'orderStatus': 'completed',
          'status': AppConstants.statusPaid,
          'completedAt': FieldValue.serverTimestamp(),
        });
      } else if (tableId != null && branchIds != null && branchIds.isNotEmpty) {
        final snapshot = await FirebaseFirestore.instance
            .collection(AppConstants.collectionOrders)
            .where('branchIds', arrayContains: branchIds.first)
            .where('tableId', isEqualTo: tableId)
            .where('Order_type', isEqualTo: 'dine_in')
            .where('status', whereIn: [
          AppConstants.statusPending,
          AppConstants.statusPreparing,
          AppConstants.statusPrepared,
          AppConstants.statusServed,
        ]).get();
        if (snapshot.docs.isEmpty) {
          await cleanupTableIfEmpty(branchIds: branchIds, tableId: tableId);
          return true;
        }
        for (final doc in snapshot.docs) {
          if (getOrderStatus(doc.data()) != 'served' ||
              getPaymentStatus(doc.data()) != 'paid') {
            return false;
          }
        }
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in snapshot.docs) {
          batch.update(doc.reference, {
            'orderStatus': 'completed',
            'status': AppConstants.statusPaid,
            'completedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      if (tableId != null && branchIds != null && branchIds.isNotEmpty) {
        await cleanupTableIfEmpty(branchIds: branchIds, tableId: tableId);
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('POS: Failed to complete order: $e');
      return false;
    }
  }

  /// Helper to check if a table has any remaining active orders and free it if not.
  /// Moved OUTSIDE of transactions to avoid timeouts and blocking.
  static Future<void> cleanupTableIfEmpty({
    required List<String> branchIds,
    required String tableId,
  }) async {
    try {
      if (branchIds.isEmpty) return;
      final primaryBranchId = branchIds.first;
      final remainingOrdersQuery = await FirebaseFirestore.instance
          .collection(AppConstants.collectionOrders)
          .where('branchIds', arrayContains: primaryBranchId)
          .where('tableId', isEqualTo: tableId)
          .where('Order_type', isEqualTo: 'dine_in')
          .get();

      // ── DUAL STATUS CHECK ──
      // Table is only empty if ALL orders are 'completed' or 'cancelled'
      final hasActiveOrders = remainingOrdersQuery.docs.any((doc) {
        final os = getOrderStatus(doc.data());
        return os != PosOrderLifecycle.stageCompleted &&
            os != PosOrderLifecycle.stageCancelled;
      });

      if (!hasActiveOrders) {
        final branchRef = FirebaseFirestore.instance
            .collection(AppConstants.collectionBranch)
            .doc(primaryBranchId);
        await branchRef.update({
          'tables.$tableId.status': 'available',
          'tables.$tableId.currentOrderId': FieldValue.delete(),
        });
        debugPrint('🧹 POS: Table $tableId cleared (no active orders)');
      }
    } catch (e) {
      debugPrint('⚠️ POS: Table cleanup failed: $e');
    }
  }

  /// Free a table (mark as available). Used by Pay All flow.
  Future<void> freeTable({
    required List<String> branchIds,
    required String tableId,
  }) async {
    await _updateTableStatus(branchIds, tableId, 'available');
  }

  /// Pre-select a table for the "Add Items" flow.
  /// Sets order type to dine-in, selects the table, and finds the
  /// active order to append items to.
  Future<void> loadTableContext(String tableId, String tableName,
      {List<String>? branchIds}) async {
    _orderType = PosOrderType.dineIn;
    _selectedTableId = tableId;
    _selectedTableName = tableName;
    _existingOrderId = null;
    _disposeSubscription();

    if (branchIds != null && branchIds.isNotEmpty) {
      await _syncSelectedTableOrders(branchIds, notify: false);
      _startOrdersListener(tableId, branchIds);
    } else {
      _ongoingOrders = [];
      notifyListeners();
      return;
    }

    notifyListeners();
  }

  void _disposeSubscription() {
    _ordersSubscription?.cancel();
    _ordersSubscription = null;
  }

  void _startOrdersListener(String tableId, List<String> branchIds) {
    if (branchIds.isEmpty) return;
    final primaryBranchId = branchIds.first;
    _disposeSubscription();
    _ordersSubscription = FirebaseFirestore.instance
        .collection(AppConstants.collectionOrders)
        .where('branchIds', arrayContains: primaryBranchId)
        .where('tableId', isEqualTo: tableId)
        .where('Order_type', isEqualTo: 'dine_in')
        .where('status', whereIn: _activeTableStatuses)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) {
      _ongoingOrders = snapshot.docs;
      QueryDocumentSnapshot<Map<String, dynamic>>? unpaidOrder;
      for (final doc in snapshot.docs) {
        if (!PosOrderLifecycle.isPaymentCaptured(doc.data())) {
          unpaidOrder = doc;
          break;
        }
      }
      _existingOrderId = unpaidOrder?.id;
      notifyListeners();
    }, onError: (e) {
      debugPrint('⚠️ POS: Subscription error: $e');
    });
  }

  void _startSingleOrderListener(String orderId) {
    _disposeSubscription();
    _ordersSubscription = FirebaseFirestore.instance
        .collection(AppConstants.collectionOrders)
        .doc(orderId)
        .snapshots()
        .listen((doc) {
      if (doc.exists) {
        _ongoingOrders = [doc];
        _existingOrderId = doc.id;
      } else {
        _ongoingOrders = [];
        _existingOrderId = null;
      }
      notifyListeners();
    }, onError: (e) {
      debugPrint('⚠️ POS: Single order subscription error: $e');
    });
  }

  /// Merges cart items into an existing active order on the table.
  /// Wrapped in a transaction to prevent race conditions in busy environments.
  Future<String> _appendToExistingOrder({
    required UserScopeService userScope,
    required List<String> branchIds,
    required String initialStatus,
  }) async {
    final orderId = _existingOrderId!;
    // POS orders should only ever be associated with ONE branch.
    final primaryBranchId = branchIds.first;
    final singleBranchList = [primaryBranchId];

    _isSubmitting = true;
    notifyListeners();

    try {
      // Snapshot cart for this transaction attempt
      final currentCart = List<PosCartItem>.from(_cartItems);

      await FirebaseFirestore.instance
          .runTransaction<String>((transaction) async {
        try {
          final orderRef = FirebaseFirestore.instance
              .collection(AppConstants.collectionOrders)
              .doc(orderId);
          final orderSnap = await transaction.get(orderRef);

          if (!orderSnap.exists) {
            throw Exception(
                'Target order does not exist. It may have been completed.');
          }

          final orderData = orderSnap.data() as Map<String, dynamic>;
          if (PosOrderLifecycle.isPaymentCaptured(orderData)) {
            throw Exception(
                'The selected table is already prepaid. Submit again to open a new add-on ticket.');
          }
          final existingItemsRaw = orderData['items'] ?? [];
          final existingItems = List<dynamic>.from(
                  existingItemsRaw is Iterable ? existingItemsRaw : [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

          // ── ADD-ON ROUND TRACKING ──
          final int previousAddOnRound =
              (orderData['addOnRound'] as num?)?.toInt() ?? 0;
          final int newAddOnRound = previousAddOnRound + 1;
          final int previousItemCount = existingItems.length;

          for (final cartItem in currentCart) {
            final addOnItem = cartItem.copyWith()..isAddOn = true;
            final map = addOnItem.toOrderItemMap();
            map['addOnRound'] = newAddOnRound;
            existingItems.add(map);
          }

          double newSubtotal = 0;
          int newItemCount = 0;
          for (final item in existingItems) {
            final qty = (item['quantity'] as num?)?.toInt() ?? 1;
            final price = (item['price'] as num?)?.toDouble() ?? 0.0;
            newSubtotal += price * qty;
            newItemCount += qty;
          }
          newSubtotal = double.parse(newSubtotal.toStringAsFixed(2));

          final discountPct =
              (orderData['discountPercent'] as num?)?.toDouble() ?? 0.0;
          final discountAmt = double.parse(
              (newSubtotal * (discountPct / 100)).toStringAsFixed(2));
          final tax = (orderData['tax'] as num?)?.toDouble() ?? 0.0;
          final newTotal = double.parse(
              (newSubtotal - discountAmt + tax).toStringAsFixed(2));

          // ── 2. PERFORM WRITES ──
          final updateData = <String, dynamic>{
            'items': existingItems,
            'subtotal': newSubtotal,
            'totalAmount': newTotal,
            'discount': discountAmt,
            'itemCount': newItemCount,
            'lastUpdated': FieldValue.serverTimestamp(),
            'kotPrinted': false,
            'addOnRound': newAddOnRound,
            'previousItemCount': previousItemCount,
            'hasActiveAddOns': true,
            'orderStatus': 'preparing',
            'paymentStatus': getPaymentStatus(orderData),
            'status': AppConstants.statusPreparing,
            'timestamps.${AppConstants.statusPreparing}':
                FieldValue.serverTimestamp(),
            'timestamp': FieldValue.serverTimestamp(),
            '_cloudFunctionUpdate': true,
          };

          transaction.update(orderRef, updateData);
          return orderId;
        } catch (e, stackTrace) {
          _logError(
              'POS: Internal transaction error in _appendToExistingOrder', e,
              stackTrace: stackTrace);
          rethrow;
        }
      }).timeout(_firestoreWriteTimeout);

      // ── Ingredient deduction (background, non-blocking but logged) for new items ──
      _deductForNewItems(
        newItems: currentCart.map((i) => i.toOrderItemMap()).toList(),
        branchIds: singleBranchList,
        orderId: orderId,
        recordedBy: _getRecorder(userScope),
      ).catchError((e) {
        _logError('POS: Appended item ingredient deduction failed', e);
      });

      clearCart();
      return orderId;
    } catch (e, stackTrace) {
      _logError('POS: Failed to append to order', e, stackTrace: stackTrace);
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Deducts inventory for a specific set of items (used when appending to orders).
  Future<void> _deductForNewItems({
    required List<Map<String, dynamic>> newItems,
    required List<String> branchIds,
    required String orderId,
    required String recordedBy,
  }) async {
    final db = FirebaseFirestore.instance;
    final ingredientService = IngredientService();

    for (final item in newItems) {
      final menuItemId =
          (item['menuItemId'] ?? item['productId'] ?? '').toString();
      final int orderedCount = (item['quantity'] as num?)?.toInt() ?? 1;
      if (menuItemId.isEmpty || orderedCount <= 0) continue;

      // Lookup menu_item → recipeId
      final menuSnap = await db
          .collection(AppConstants.collectionMenuItems)
          .doc(menuItemId)
          .get();
      if (!menuSnap.exists) continue;

      final recipeId = (menuSnap.data()?['recipeId'] ?? '').toString();
      DocumentSnapshot? recipeSnap;
      if (recipeId.isNotEmpty) {
        recipeSnap = await db
            .collection(AppConstants.collectionRecipes)
            .doc(recipeId)
            .get();
        if (!recipeSnap.exists) recipeSnap = null;
      }
      if (recipeSnap == null) {
        final recipeQuery = await db
            .collection(AppConstants.collectionRecipes)
            .where('linkedMenuItemId', isEqualTo: menuItemId)
            .where('isActive', isEqualTo: true)
            .limit(1)
            .get();
        if (recipeQuery.docs.isEmpty) continue;
        recipeSnap = recipeQuery.docs.first;
      }

      final recipeIngredientsData =
          (recipeSnap.data() as Map?)?['ingredients'] ?? [];
      final recipeIngredients = List<dynamic>.from(
          recipeIngredientsData is Iterable ? recipeIngredientsData : []);

      for (final riData in recipeIngredients) {
        final ri = Map<String, dynamic>.from(riData as Map? ?? {});
        final ingredientId = (ri['ingredientId'] ?? '').toString();
        if (ingredientId.isEmpty) continue;

        final double recipeQty = (ri['quantity'] as num?)?.toDouble() ?? 0.0;
        final String recipeUnit = (ri['unit'] ?? '').toString();
        double deductQty = recipeQty * orderedCount;
        if (deductQty <= 0) continue;

        try {
          // Fetch the ingredient to get its storage unit for conversion
          final ingDoc = await db
              .collection(AppConstants.collectionIngredients)
              .doc(ingredientId)
              .get();
          if (!ingDoc.exists) continue;

          final ingData = ingDoc.data()!;
          final String ingUnit = (ingData['unit'] ?? '').toString();

          // Convert recipe unit → ingredient storage unit if they differ
          if (recipeUnit.isNotEmpty &&
              ingUnit.isNotEmpty &&
              recipeUnit != ingUnit) {
            final converted =
                IngredientService.convertUnit(deductQty, recipeUnit, ingUnit);
            if (converted == null) {
              debugPrint(
                  '⚠️ POS: Cannot convert $recipeUnit→$ingUnit for ingredient $ingredientId, skipping');
              continue;
            }
            deductQty = converted;
          }

          await ingredientService.adjustStock(
            ingredientId: ingredientId,
            branchIds: branchIds,
            delta: -deductQty,
            movementType: 'order_deduction',
            recordedBy: recordedBy,
            referenceId: orderId,
            reason: 'Items appended to table order',
          );
        } catch (e) {
          debugPrint('⚠️ POS: Failed to deduct ingredient $ingredientId: $e');
        }
      }
    }
  }

  // ── Utility Helpers (Static) ──────────────────────────────────
  static String mapLegacyStatusToOrder(String status) {
    return PosOrderLifecycle.normalizeOrderStage(status);
  }

  static String mapLegacyStatusToPayment(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'collected':
        return 'paid';
      case 'refunded':
        return 'refunded';
      default:
        return 'unpaid';
    }
  }

  static String getOrderStatus(Map<String, dynamic> data) {
    return PosOrderLifecycle.stageFromData(data);
  }

  static String getPaymentStatus(Map<String, dynamic> data) {
    return PosOrderLifecycle.paymentStatusFromData(data);
  }

  static String getNormalizedOrderType(Map<String, dynamic> data) {
    return PosOrderLifecycle.orderTypeFromData(data);
  }

  static bool isPaymentCaptured(Map<String, dynamic> data) {
    return PosOrderLifecycle.isPaymentCaptured(data);
  }

  static bool requiresKitchenDecision(Map<String, dynamic> data) {
    return PosOrderLifecycle.requiresChefDecision(data);
  }

  static int? getKitchenDecisionSecondsRemaining(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    return PosOrderLifecycle.kitchenResponseSecondsRemaining(data, now: now);
  }

  static bool shouldAutoAcceptPending(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    return PosOrderLifecycle.shouldAutoAcceptPending(data, now: now);
  }

  static bool isKitchenRejected(Map<String, dynamic> data) {
    return PosOrderLifecycle.isKitchenRejected(data);
  }

  static double getOutstandingAmount(Map<String, dynamic> data) {
    return PosOrderLifecycle.outstandingAmount(data);
  }

  static Map<String, String>? getKdsPrimaryAction(
    Map<String, dynamic> data, {
    bool isRecall = false,
  }) {
    return PosOrderLifecycle.kdsPrimaryAction(data, isRecall: isRecall);
  }
}
