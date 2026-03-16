// lib/services/pos/pos_service.dart
// POS session and cart management service

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../constants.dart';
import '../../main.dart';
import '../../Widgets/TimeUtils.dart';
import '../inventory/InventoryService.dart';
import '../ingredients/IngredientService.dart';
import 'pos_models.dart';

class PosService extends ChangeNotifier {
  // ── Industry-grade limits ──────────────────────────────────
  static const int maxCartItems = 50;
  static const int maxQuantityPerItem = 999;
  static const Duration _firestoreWriteTimeout = Duration(seconds: 30);

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
  StreamSubscription? _ordersSubscription;

  @override
  void dispose() {
    _disposeSubscription();
    super.dispose();
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
  bool get isAppendMode => _ongoingOrders.isNotEmpty;
  List<DocumentSnapshot> get ongoingOrders => _ongoingOrders;
  String? get activeBranchId => _activeBranchId;

  double get subtotal =>
      double.parse(_cartItems.fold(0.0, (acc, item) => acc + item.subtotal).toStringAsFixed(2));

  double get discountAmount => double.parse((subtotal * (_orderDiscount / 100)).toStringAsFixed(2));

  double get taxAmount => 0; // Configure tax rate if needed

  double get total => double.parse((subtotal - discountAmount + taxAmount).toStringAsFixed(2));

  double get ongoingTotal => double.parse(_ongoingOrders.fold(0.0, (acc, doc) {
        final data = doc.data() as Map<String, dynamic>;
        return acc + (data['totalAmount'] as num? ?? 0).toDouble();
      }).toStringAsFixed(2));

  double get grandTotal => double.parse((total + ongoingTotal).toStringAsFixed(2));

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

  // ── Daily Order Number ──────────────────────────────────────
  Future<int> _generateDailyOrderNumber(List<String> branchIds) async {
    try {
      if (branchIds.isEmpty) return 1;
      final branchId = branchIds.first;
      final dynamic businessStart = TimeUtils.getBusinessStartTimestamp();
      final DateTime businessStartDt = businessStart is Timestamp ? businessStart.toDate() : businessStart;
      final dateKey = businessStartDt.toIso8601String().split('T')[0];
      final counterRef = FirebaseFirestore.instance.collection('Counters').doc('orders_${branchId}_$dateKey');

      return await FirebaseFirestore.instance.runTransaction((transaction) async {
        final counterSnap = await transaction.get(counterRef);
        if (!counterSnap.exists) {
          transaction.set(counterRef, {'count': 1});
          return 1;
        }
        final currentCount = (counterSnap.data()?['count'] as int?) ?? 0;
        final nextCount = currentCount + 1;
        transaction.update(counterRef, {'count': nextCount});
        return nextCount;
      });
    } catch (e) {
      debugPrint('⚠️ Error generating daily order number: $e');
      return DateTime.now().millisecondsSinceEpoch % 10000;
    }
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
    final branchId = data['branchIds'] is List ? (data['branchIds'] as List).first.toString() : '';
    
    if (orderTypeStr == 'dine_in' && data['tableId'] != null) {
      // For dine-in, we use the full table loading logic which handles ongoing orders
      await loadTableContext(data['tableId'].toString(), data['tableNumber']?.toString() ?? 'Table', branchIds: [branchId]);
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
    String initialStatus = 'preparing',
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
    final primaryBranchId = branchIds.first;

    if (_orderType == PosOrderType.dineIn && _existingOrderId != null && _ongoingOrders.isNotEmpty) {
      // Divert to append flow
      return _appendToExistingOrder(
        userScope: userScope,
        branchIds: branchIds,
        initialStatus: initialStatus,
      );
    }

    _isSubmitting = true;
    notifyListeners();

    try {
      final docRef = FirebaseFirestore.instance.collection(AppConstants.collectionOrders).doc();
      final String orderId = docRef.id;

      // ── INDUSTRY GRADE FIX: Wrap in Transaction for Table & Counter Safety ──
      final String finalOrderId = await FirebaseFirestore.instance.runTransaction((transaction) async {
        // 1. Check Table Status (if Dine-In)
        if (_orderType == PosOrderType.dineIn && _selectedTableId != null) {
          final branchRef = FirebaseFirestore.instance.collection(AppConstants.collectionBranch).doc(primaryBranchId);
          final branchSnap = await transaction.get(branchRef);
          final tables = (branchSnap.data()?['tables'] as Map<dynamic, dynamic>?) ?? {};
          final tableData = tables[_selectedTableId] as Map<dynamic, dynamic>?;
          
          if (tableData?['status'] == 'occupied' && tableData?['currentOrderId'] != null) {
             throw Exception('Table was just taken by another device!');
          }
          
          // Book the table
          transaction.update(branchRef, {
            'tables.$_selectedTableId.status': 'occupied',
            'tables.$_selectedTableId.currentOrderId': orderId,
          });
        }

        // 2. Generate Daily Number (Atomic inside transaction)
        final dailyNumber = await _generateDailyOrderNumber(branchIds);
        final orderData = _buildOrderData(branchIds, userScope, initialStatus, dailyNumber);
        
        // 3. Create Order
        transaction.set(docRef, orderData);

        return orderId;
      }).timeout(_firestoreWriteTimeout);

      // ── Ingredient deduction (background) ──
      final recordedBy = _getRecorder(userScope);
      InventoryService().deductForOrder(
        orderId: finalOrderId,
        branchIds: branchIds,
        recordedBy: recordedBy,
      ).catchError((e) => _logError('POS: Ingredient deduction failed', e));

      clearCart();
      return finalOrderId;
    } catch (e) {
      _logError('POS: Failed to submit order', e);
      if (e is TimeoutException) {
        throw Exception('Network timeout. Check KDS/Orders list before retrying to prevent duplicates.');
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

  static void _logError(String message, dynamic error) {
    debugPrint('🔴 $message: $error');
    // Integration point for Crashlytics or external logging
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
    notifyListeners();

    try {
      final String? orderIdToReturn;
      
      // ── INDUSTRY GRADE FIX: Wrap EVERYTHING in an atomic Transaction ──
      orderIdToReturn = await FirebaseFirestore.instance.runTransaction<String?>((transaction) async {
        // ── 1. ALL READS ──
        
        // A. Read existing orders to get items and check status
        final List<Map<String, dynamic>> itemsToDeduct = [];
        for (final doc in existingOrders) {
          final orderSnap = await transaction.get(doc.reference);
          if (orderSnap.exists) {
            final data = orderSnap.data() as Map<String, dynamic>;
            // Only deduct if not already done
            if (data['inventoryDeducted'] != true) {
              final items = (data['items'] ?? data['orderItems'] ?? []) as List<dynamic>;
              itemsToDeduct.addAll(items.cast<Map<String, dynamic>>());
            }
          }
        }

        // B. Add current cart items to deduction list
        if (_cartItems.isNotEmpty) {
          itemsToDeduct.addAll(_cartItems.map((item) => item.toOrderItemMap()).toList());
        }

        // C. Perform Batch Inventory Deduction
        DocumentReference? newOrderDocRef;
        String? newOrderId;
        if (_cartItems.isNotEmpty) {
          newOrderDocRef = FirebaseFirestore.instance.collection(AppConstants.collectionOrders).doc();
          newOrderId = newOrderDocRef.id;
        }

        if (itemsToDeduct.isNotEmpty) {
          await InventoryService().deductItemsInTransaction(
            transaction: transaction,
            items: itemsToDeduct,
            branchIds: branchIds,
            orderId: newOrderId ?? (existingOrders.isNotEmpty ? existingOrders.first.id : 'unknown'),
            recordedBy: _getRecorder(userScope),
          );
        }

        // ── 2. PREPARE WRITES ──
        Map<String, dynamic>? newOrderData;
        if (_cartItems.isNotEmpty && newOrderId != null) {
          final dailyNumber = await _generateDailyOrderNumber(branchIds);
          newOrderData = _buildOrderData(branchIds, userScope, AppConstants.statusPaid, dailyNumber);
          
          newOrderData['paymentMethod'] = payment.method;
          newOrderData['paymentAmount'] = payment.amount;
          newOrderData['paymentChange'] = payment.change;
          newOrderData['isPaid'] = true;
          newOrderData['paidAt'] = FieldValue.serverTimestamp();
          newOrderData['completedAt'] = FieldValue.serverTimestamp();
          newOrderData['timestamps.${AppConstants.statusPaid}'] = FieldValue.serverTimestamp();
          newOrderData['inventoryDeducted'] = true; // IMPORTANT: Mark as deducted

          // ── DUAL STATUS OVERRIDE ──
          // If paying now, legacy status is 'paid', but orderStatus should be 'placed' or 'preparing'
          newOrderData['orderStatus'] = 'preparing'; 
          newOrderData['paymentStatus'] = 'paid';
        }

        // ── 3. PERFORM ALL WRITES ──
        if (newOrderDocRef != null && newOrderData != null) {
          transaction.set(newOrderDocRef, newOrderData);
        }

        // Handle existing orders if any
        for (final doc in existingOrders) {
          transaction.update(doc.reference, {
            'paymentMethod': payment.method,
            'paymentAmount': payment.amount,
            'paymentChange': payment.change,
            'isPaid': true,
            'paidAt': FieldValue.serverTimestamp(),
            'status': AppConstants.statusPaid,
            'completedAt': FieldValue.serverTimestamp(),
            'timestamps.${AppConstants.statusPaid}': FieldValue.serverTimestamp(),
            'inventoryDeducted': true, // IMPORTANT: Mark as deducted

            // ── DUAL STATUS OVERRIDE ──
            // For existing orders being paid, keep orderStatus or derive it
            'paymentStatus': 'paid',
            // Do NOT touch orderStatus if it already exists, otherwise derive it
            'orderStatus': (doc.data() as Map<String, dynamic>).containsKey('orderStatus') 
                ? (doc.data() as Map<String, dynamic>)['orderStatus'] 
                : mapLegacyStatusToOrder((doc.data() as Map<String, dynamic>)['status'] ?? ''),
          });
        }

        // ── DUAL STATUS FIX ──
        // Table is NO LONGER freed here, even if paid. 
        // It remains occupied until the order is explicitly 'completed' via completeOrderWithDualCheck,
        // which requires BOTH served and paid statuses.

        if (newOrderId != null) {
          return newOrderId;
        } else if (existingOrders.isNotEmpty) {
          return existingOrders.first.id;
        } else {
          return null; // Should never happen given the empty guard at start, but keeps type safe
        }
      }).timeout(_firestoreWriteTimeout);

      clearCart();
      return orderIdToReturn ?? 'paid';
    } catch (e) {
      _logError('POS: Payment submission failed', e);
      if (e is TimeoutException) {
        throw Exception('Network timeout during payment. Verify status in Orders list before retrying.');
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
    int dailyOrderNumber,
  ) {

    final DateTime now = DateTime.now();
    final DateTime autoAcceptDeadline = now.add(const Duration(seconds: 15));
    return {
      'branchIds': branchIds,
      'source': 'pos',
      // ── SYNC FIX: Write BOTH field names so all screens can find this order ──
      'Order_type': _orderType.firestoreValue, // Queried by OrderService
      'orderType': _orderType.firestoreValue, // Used by KDS fallback
      'status': status,
      'dailyOrderNumber': dailyOrderNumber, // For display in order lists
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
      // ── New Dual Status fields ──
      'orderStatus': getOrderStatus({'status': status}),
      'paymentStatus': getPaymentStatus({'status': status, 'isPaid': status == AppConstants.statusPaid}),
      // ── New fields for improved POS order logic ──
      'autoAcceptDeadline': Timestamp.fromDate(autoAcceptDeadline),
      'isAutoAccepted': false,
      // POS orders should NEVER show popup alerts for admin accept/reject
      'showPopupAlert': false
    };
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
    final effectiveBranchIds = branchIds ?? (userScope.branchIds.isNotEmpty ? userScope.branchIds : <String>[]);
    
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final orderRef = FirebaseFirestore.instance.collection(AppConstants.collectionOrders).doc(orderId);
      final orderSnap = await transaction.get(orderRef);
      if (!orderSnap.exists) throw Exception("Order not found");

      // 1. ALL READS
      // ── Atomic Inventory Deduction ──
      // Must be performed BEFORE the order update in Firestore Transactions!
      await InventoryService().performDeductionInTransaction(
        transaction: transaction,
        orderId: orderId,
        branchIds: effectiveBranchIds,
        recordedBy: _getRecorder(userScope),
      );
      // (Add your order update logic here)
    });
  }

  static Future<void> _updateTableStatus(List<String> branchIds, String tableId, String status) async {
    try {
      if (branchIds.isEmpty) return;
      final primaryBranchId = branchIds.first;
      final branchDoc = FirebaseFirestore.instance.collection(AppConstants.collectionBranch).doc(primaryBranchId);
      
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
      final orderRef = FirebaseFirestore.instance.collection(AppConstants.collectionOrders).doc(orderId);
      final snap = await orderRef.get();
      if (!snap.exists) throw Exception("Order not found");

      final data = snap.data() as Map<String, dynamic>;
      final os = getOrderStatus(data);

      if (os == 'completed' || os == 'recalled' || os == 'cancelled') {
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
      });
      notifyListeners();
    } catch (e) {
      _logError('POS: Failed to recall order', e);
      rethrow;
    }
  }

  Future<void> cancelOrder({
    required String orderId,
    required UserScopeService userScope,
    String? tableId,
    List<String>? branchIds,
  }) async {
    final effectiveBranchIds = branchIds ?? (userScope.branchIds.isNotEmpty ? userScope.branchIds : <String>[]);
    final recordedBy = _getRecorder(userScope);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final orderRef = FirebaseFirestore.instance.collection(AppConstants.collectionOrders).doc(orderId);
        final orderSnap = await transaction.get(orderRef);
        
        if (!orderSnap.exists) throw Exception("Order not found");
        final orderData = orderSnap.data()!;
        final currentStatus = orderData['status']?.toString() ?? '';

        if (currentStatus == AppConstants.statusPrepared || currentStatus == AppConstants.statusServed) {
          throw Exception("Cannot cancel an order that is already ${currentStatus.toUpperCase()}.");
        }

        if (orderData['inventoryDeducted'] == true && orderData['inventoryRestored'] != true) {
          final rawItems = (orderData['items'] ?? orderData['orderItems'] ?? []) as List<dynamic>;
          if (rawItems.isNotEmpty) {
            await InventoryService().restoreItemsInTransaction(
              transaction: transaction,
              items: rawItems.cast<Map<String, dynamic>>(),
              branchIds: effectiveBranchIds,
              orderId: orderId,
              recordedBy: recordedBy,
              reason: 'Order cancelled via POS',
            );
          }
        }

        final isPaid = orderData['isPaid'] == true || getPaymentStatus(orderData) == 'paid';
        transaction.update(orderRef, {
          'status': 'cancelled',
          'orderStatus': 'cancelled',
          'paymentStatus': isPaid ? 'refunded' : 'unpaid',
          'inventoryRestored': true,
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelledBy': recordedBy,
          'timestamps.cancelled': FieldValue.serverTimestamp(),
          'timestamps.orderStatus_cancelled': FieldValue.serverTimestamp(),
        });
      }).timeout(_firestoreWriteTimeout);

      if (tableId != null && effectiveBranchIds.isNotEmpty) {
        _cleanupTableIfEmpty(branchIds: effectiveBranchIds, tableId: tableId);
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
    final effectiveBranchIds = branchIds ?? (userScope.branchIds.isNotEmpty ? userScope.branchIds : <String>[]);
    final recordedBy = _getRecorder(userScope);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final orderRef = FirebaseFirestore.instance.collection(AppConstants.collectionOrders).doc(orderId);
        final orderSnap = await transaction.get(orderRef);
        
        if (!orderSnap.exists) throw Exception("Order not found");
        final orderData = orderSnap.data()!;
        final currentStatus = orderData['status']?.toString() ?? '';

        if (currentStatus == AppConstants.statusPrepared || currentStatus == AppConstants.statusServed) {
          throw Exception("Cannot remove items from an order that is already ${currentStatus.toUpperCase()}.");
        }

        final items = List<Map<String, dynamic>>.from(orderData['items'] ?? []);
        if (itemIndex < 0 || itemIndex >= items.length) throw Exception("Invalid item index");

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

        final discountPct = (orderData['discountPercent'] as num?)?.toDouble() ?? 0.0;
        final discountAmt = double.parse((newSubtotal * (discountPct / 100)).toStringAsFixed(2));
        final tax = (orderData['tax'] as num?)?.toDouble() ?? 0.0;
        final newTotal = double.parse((newSubtotal - discountAmt + tax).toStringAsFixed(2));

        final cancelledItems = List<Map<String, dynamic>>.from(orderData['cancelledItems'] ?? []);
        cancelledItems.add(removedItem);

        if (items.isEmpty) {
          transaction.update(orderRef, {
            'items': [],
            'cancelledItems': cancelledItems,
            'subtotal': 0,
            'totalAmount': 0,
            'status': 'cancelled',
            'cancelledAt': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.update(orderRef, {
            'items': items,
            'cancelledItems': cancelledItems,
            'subtotal': newSubtotal,
            'totalAmount': newTotal,
            'discount': discountAmt,
            'itemCount': newItemCount,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }
      }).timeout(_firestoreWriteTimeout);
      notifyListeners();
    } catch (e) {
      _logError('POS: Failed to remove item from order', e);
      rethrow;
    }
  }

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection(AppConstants.collectionOrders).doc(orderId).update({
        'orderStatus': mapLegacyStatusToOrder(newStatus),
        'status': newStatus,
        'lastUpdated': FieldValue.serverTimestamp(),
        'timestamps.$newStatus': FieldValue.serverTimestamp(),
      });
      notifyListeners();
    } catch (e) {
      _logError('POS: Failed to update order status', e);
      rethrow;
    }
  }

  Future<void> updatePaymentStatus(String orderId, String newStatus, {PosPayment? payment}) async {
    try {
      final updateData = <String, dynamic>{
        'paymentStatus': newStatus,
        'lastUpdated': FieldValue.serverTimestamp(),
        'timestamps.$newStatus': FieldValue.serverTimestamp(),
      };
      if (newStatus == 'paid' && payment != null) {
        updateData['paymentMethod'] = payment.method;
        updateData['paymentAmount'] = payment.amount;
        updateData['paymentChange'] = payment.change;
        updateData['isPaid'] = true;
        updateData['paidAt'] = FieldValue.serverTimestamp();
      }
      await FirebaseFirestore.instance.collection(AppConstants.collectionOrders).doc(orderId).update(updateData);
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
        final orderRef = FirebaseFirestore.instance.collection(AppConstants.collectionOrders).doc(orderId);
        final snapshot = await orderRef.get();
        if (!snapshot.exists) throw Exception("Order not found");
        final data = snapshot.data()!;
        if (getOrderStatus(data) != 'served' || getPaymentStatus(data) != 'paid') return false;
        await orderRef.update({
          'orderStatus': 'completed',
          'status': AppConstants.statusPaid,
          'completedAt': FieldValue.serverTimestamp(),
        });
      } else if (tableId != null && branchIds != null && branchIds.isNotEmpty) {
        final snapshot = await FirebaseFirestore.instance.collection(AppConstants.collectionOrders)
            .where('branchIds', arrayContains: branchIds.first)
            .where('tableId', isEqualTo: tableId)
            .where('Order_type', isEqualTo: 'dine_in')
            .where('status', whereIn: [
              AppConstants.statusPending, AppConstants.statusPreparing, AppConstants.statusPrepared, AppConstants.statusServed,
            ]).get();
        if (snapshot.docs.isEmpty) {
          await _cleanupTableIfEmpty(branchIds: branchIds, tableId: tableId);
          return true;
        }
        for (final doc in snapshot.docs) {
          if (getOrderStatus(doc.data()) != 'served' || getPaymentStatus(doc.data()) != 'paid') return false;
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
        await _cleanupTableIfEmpty(branchIds: branchIds, tableId: tableId);
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
  static Future<void> _cleanupTableIfEmpty({
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
        return os != 'completed' && os != 'cancelled';
      });

      if (!hasActiveOrders) {
        final branchRef = FirebaseFirestore.instance.collection(AppConstants.collectionBranch).doc(primaryBranchId);
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
  Future<void> loadTableContext(String tableId, String tableName, {List<String>? branchIds}) async {
    _orderType = PosOrderType.dineIn;
    _selectedTableId = tableId;
    _selectedTableName = tableName;
    _existingOrderId = null;
    _disposeSubscription();

    if (branchIds != null && branchIds.isNotEmpty) {
      _startOrdersListener(tableId, branchIds);
    } else {
      _ongoingOrders = [];
      notifyListeners();
    }
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
        .where('status', whereIn: [
          AppConstants.statusPending,
          AppConstants.statusPreparing,
          AppConstants.statusPrepared,
          AppConstants.statusServed,
        ])
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) {
      _ongoingOrders = snapshot.docs;
      if (_ongoingOrders.isNotEmpty) {
        _existingOrderId = _ongoingOrders.first.id;
      } else {
        _existingOrderId = null;
      }
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

    _isSubmitting = true;
    notifyListeners();

    try {
      // Snapshot cart for this transaction attempt
      final currentCart = List<PosCartItem>.from(_cartItems);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final orderRef = FirebaseFirestore.instance
            .collection(AppConstants.collectionOrders)
            .doc(orderId);
        final orderSnap = await transaction.get(orderRef);

        if (!orderSnap.exists) {
          throw Exception('Target order does not exist. It may have been completed.');
        }

        final orderData = orderSnap.data()!;
        final existingItems = List<Map<String, dynamic>>.from(orderData['items'] ?? []);

        // ── ADD-ON ROUND TRACKING ──
        // Track which round of add-ons this is, and how many items existed before
        final int previousAddOnRound = (orderData['addOnRound'] as int?) ?? 0;
        final int newAddOnRound = previousAddOnRound + 1;
        final int previousItemCount = existingItems.length;

        // Merge logic: Appended items DO NOT merge with previous items.
        // We want them to stand out as ADD-ONs on the KDS and KOT.
        for (final cartItem in currentCart) {
          // Force isAddOn true for all items coming through append flow
          final addOnItem = cartItem.copyWith()..isAddOn = true;
          final map = addOnItem.toOrderItemMap();
          map['addOnRound'] = newAddOnRound; // Tag which round this item belongs to
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

        final discountPct = (orderData['discountPercent'] as num?)?.toDouble() ?? 0.0;
        final discountAmt = double.parse((newSubtotal * (discountPct / 100)).toStringAsFixed(2));
        final tax = (orderData['tax'] as num?)?.toDouble() ?? 0.0;
        final newTotal = double.parse((newSubtotal - discountAmt + tax).toStringAsFixed(2));

        // ── 2. PERFORM WRITES ──
        final updateData = <String, dynamic>{
          'items': existingItems,
          'subtotal': newSubtotal,
          'totalAmount': newTotal,
          'discount': discountAmt,
          'itemCount': newItemCount,
          'lastUpdated': FieldValue.serverTimestamp(),
          'kotPrinted': false,
          // ── ADD-ON TRACKING FIELDS ──
          'addOnRound': newAddOnRound,
          'previousItemCount': previousItemCount,
          'hasActiveAddOns': true,
          // ── DUAL STATUS ──
          'orderStatus': 'preparing',
          'paymentStatus': getPaymentStatus(orderData),
        };

        // ── FORCE BACK TO PENDING ──
        // Regardless of current status (preparing, prepared, served), if new items 
        // are appended, push the whole ticket back to "New Order" queue on KDS.
        updateData['status'] = AppConstants.statusPreparing;
        updateData['timestamps.${AppConstants.statusPreparing}'] = FieldValue.serverTimestamp();
        
        // ** CRITICAL FIX ** 
        // Also reset the main order timestamp so it drops to the BOTTOM of the queue
        // (the "Newest" position) rather than being buried 30 minutes in the past!
        updateData['timestamp'] = FieldValue.serverTimestamp();

        // ** FIREBASE CLOUD FUNCTION BYPASS **
        // The validateOrderStatusTransition Cloud Function blocks `served` -> `pending`
        // explicitly. We add this flag to tell the backend to allow this override.
        updateData['_cloudFunctionUpdate'] = true;

        transaction.update(orderRef, updateData);
      }).timeout(_firestoreWriteTimeout);

      // ── Ingredient deduction (background, non-blocking but logged) for new items ──
      _deductForNewItems(
        newItems: currentCart.map((i) => i.toOrderItemMap()).toList(),
        branchIds: branchIds,
        orderId: orderId,
        recordedBy: _getRecorder(userScope),
      )
.catchError((e) {
        _logError('POS: Appended item ingredient deduction failed', e);
      });

      clearCart();
      return orderId;
    } catch (e) {
      _logError('POS: Failed to append to order', e);
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
      final menuItemId = (item['menuItemId'] ?? item['productId'] ?? '').toString();
      final int orderedCount = (item['quantity'] as num?)?.toInt() ?? 1;
      if (menuItemId.isEmpty || orderedCount <= 0) continue;

      // Lookup menu_item → recipeId
      final menuSnap = await db.collection(AppConstants.collectionMenuItems).doc(menuItemId).get();
      if (!menuSnap.exists) continue;

      final recipeId = (menuSnap.data()?['recipeId'] ?? '').toString();
      DocumentSnapshot? recipeSnap;
      if (recipeId.isNotEmpty) {
        recipeSnap = await db.collection(AppConstants.collectionRecipes).doc(recipeId).get();
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

      final recipeIngredients = List<Map<String, dynamic>>.from(
          (recipeSnap.data() as Map<String, dynamic>?)?['ingredients'] ?? []);

      for (final ri in recipeIngredients) {
        final ingredientId = (ri['ingredientId'] ?? '').toString();
        if (ingredientId.isEmpty) continue;

        final double recipeQty = (ri['quantity'] as num?)?.toDouble() ?? 0.0;
        final deductQty = recipeQty * orderedCount;
        if (deductQty <= 0) continue;

        try {
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
    final lower = status.toLowerCase();
    if (lower == 'pending' || lower == 'placed') {
      return AppConstants.statusPending;
    }
    if (lower == 'preparing') {
      return AppConstants.statusPreparing;
    }
    if (lower == 'prepared' || lower == 'ready') {
      return AppConstants.statusPrepared;
    }
    if (lower == 'served') {
      return AppConstants.statusServed;
    }
    if (lower == 'paid' || lower == 'collected' || lower == 'completed') {
      return AppConstants.statusPaid; // Standardize terminal payment status
    }
    if (lower == 'cancelled' || lower == 'refunded') {
      return AppConstants.statusCancelled;
    }
    return AppConstants.statusPending;
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
    if (data.containsKey('orderStatus')) {
      final os = data['orderStatus'] as String;
      // Ensure we don't return 'prepared' or other legacy strings if they leaked into orderStatus
      return mapLegacyStatusToOrder(os);
    }
    return mapLegacyStatusToOrder(data['status']?.toString() ?? 'pending');
  }

  static String getPaymentStatus(Map<String, dynamic> data) {
    if (data.containsKey('paymentStatus')) return data['paymentStatus'] as String;
    return mapLegacyStatusToPayment(data['status']?.toString() ?? 'pending');
  }
}
