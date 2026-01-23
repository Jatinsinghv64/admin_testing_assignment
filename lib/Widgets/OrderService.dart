import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../main.dart';
import 'TimeUtils.dart';
import '../Widgets/RiderAssignment.dart';
import '../constants.dart';
import '../utils/security_utils.dart'; // SECURITY: Input validation utilities

class OrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// @Deprecated: Use [getOrdersStreamMerged] instead.
  /// This method is kept for backward compatibility but will be removed in a future version.
  /// 
  /// Returns an empty stream. All callers should migrate to getOrdersStreamMerged.
  @Deprecated('Use getOrdersStreamMerged instead. This method returns empty stream.')
  Stream<QuerySnapshot<Map<String, dynamic>>> getOrdersStream({
    required String orderType,
    required String status,
    required UserScopeService userScope,
    List<String>? filterBranchIds,
  }) {
    // Log deprecation warning in debug mode
    assert(() {
      debugPrint('⚠️ DEPRECATED: getOrdersStream called. Use getOrdersStreamMerged instead.');
      return true;
    }());
    
    // Return empty stream instead of throwing error
    // This prevents crashes if any code path still uses this method
    return const Stream.empty();
  }

  /// ✅ NEW: Returns merged stream of order documents (handles both branchId and branchIds)
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getOrdersStreamMerged({
    required String orderType,
    required String status,
    required UserScopeService userScope,
    List<String>? filterBranchIds,
  }) {
    debugPrint('🔍 OrderService.getOrdersStreamMerged called:');
    debugPrint('   - orderType: $orderType');
    debugPrint('   - status: $status');
    debugPrint('   - filterBranchIds: $filterBranchIds');
    debugPrint('   - userScope.branchIds: ${userScope.branchIds}');
    
    final effectiveBranchIds = filterBranchIds ?? userScope.branchIds;
    
    if (effectiveBranchIds.isEmpty) {
      return Stream.value([]);
    }

    return _getMergedOrdersStream(
      orderType: orderType,
      status: status,
      branchIds: effectiveBranchIds,
    );
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _getMergedOrdersStream({
    required String orderType,
    required String status,
    required List<String> branchIds,
  }) {
    // Only query orders with branchIds array field
    Query<Map<String, dynamic>> arrayQuery = _db
        .collection(AppConstants.collectionOrders)
        .where('Order_type', isEqualTo: orderType);
    
    if (branchIds.length == 1) {
      arrayQuery = arrayQuery.where('branchIds', arrayContains: branchIds.first);
    } else {
      arrayQuery = arrayQuery.where('branchIds', arrayContainsAny: branchIds);
    }
    
    // Apply status/timestamp filters
    if (status == 'all') {
      final startOfBusinessDay = TimeUtils.getBusinessStartTimestamp();
      final endOfBusinessDay = TimeUtils.getBusinessEndTimestamp();
      
      arrayQuery = arrayQuery
          .where('timestamp', isGreaterThanOrEqualTo: startOfBusinessDay)
          .where('timestamp', isLessThan: endOfBusinessDay)
          .orderBy('timestamp', descending: true);
    } else {
      final normalizedStatus = AppConstants.normalizeStatus(status);
      arrayQuery = arrayQuery
          .where('status', isEqualTo: normalizedStatus)
          .orderBy('timestamp', descending: true);
    }

    return arrayQuery.snapshots().map((snapshot) => snapshot.docs);
  }



  // STANDARD QUERY HELPERS (Refactored from DashboardScreen)

  // 1. Get Today's Orders
  Stream<QuerySnapshot<Map<String, dynamic>>> getTodayOrdersStream({
    required UserScopeService userScope,
    List<String>? filterBranchIds,
  }) {
    final startOfShift = TimeUtils.getBusinessStartTimestamp();
    
    Query<Map<String, dynamic>> query = _db.collection(AppConstants.collectionOrders);
    
    // Apply Branch Filter
    query = _applyBranchFilter(query, userScope, filterBranchIds);

    // Apply Time Filter
    return query
        .where('timestamp', isGreaterThanOrEqualTo: startOfShift)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // 2. Get Active Drivers
  Stream<QuerySnapshot<Map<String, dynamic>>> getActiveDriversStream({
    required UserScopeService userScope,
    List<String>? filterBranchIds,
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection(AppConstants.collectionDrivers)
        .where('isAvailable', isEqualTo: true);

    // Apply Branch Filter
    query = _applyBranchFilter(query, userScope, filterBranchIds);
    
    return query.snapshots();
  }

  // 3. Get Available Menu Items
  Stream<QuerySnapshot<Map<String, dynamic>>> getAvailableMenuItemsStream({
    required UserScopeService userScope,
    List<String>? filterBranchIds,
  }) {
    Query<Map<String, dynamic>> query = _db.collection(AppConstants.collectionMenuItems);

    // Apply Branch Filter
    query = _applyBranchFilter(query, userScope, filterBranchIds);

    return query.where('isAvailable', isEqualTo: true).snapshots();
  }

  // Helper: Centralized Revenue Calculation Logic
  static double calculateRevenue(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    double totalRevenue = 0;
    final billableStatuses = {
      AppConstants.statusDelivered,
      'completed',
      AppConstants.statusPaid,      // Takeaway/Dine-in terminal
      AppConstants.statusCollected, // Pickup terminal
      // AppConstants.statusRefunded // Refunds should NOT count (deducts from revenue)
    };

    for (var doc in docs) {
      final data = doc.data();
      final status = (data['status'] ?? '').toString().toLowerCase();
      final isExchange = data['isExchange'] == true;

      // 1. Check if status is billable (Delivered, Completed, Paid)
      // 2. OR if it's an Exchange order that is currently being prepared (Preparing)
      //    (Normal preparing orders are not paid yet/revenue realized, but Exchanges were already paid)
      bool shouldCount = billableStatuses.contains(status);
      
      if (!shouldCount && isExchange && status == AppConstants.statusPreparing) {
        shouldCount = true;
      }

      if (shouldCount) {
        totalRevenue += (data['totalAmount'] as num? ?? 0).toDouble();
      }
    }
    return totalRevenue;
  }

  // Private Helper: Apply Branch Filter
  Query<Map<String, dynamic>> _applyBranchFilter(
    Query<Map<String, dynamic>> query,
    UserScopeService userScope,
    List<String>? filterBranchIds,
  ) {
    // Priority 1: Specific Filter (e.g. from Dropdown)
    if (filterBranchIds != null && filterBranchIds.isNotEmpty) {
      if (filterBranchIds.length == 1) {
        return query.where('branchIds', arrayContains: filterBranchIds.first);
      } else {
        return query.where('branchIds', arrayContainsAny: filterBranchIds);
      }
    }
    
    // Priority 2: User's Assigned Branches (Default view)
    if (userScope.branchIds.isNotEmpty) {
      if (userScope.branchIds.length == 1) {
        return query.where('branchIds', arrayContains: userScope.branchIds.first);
      } else {
        return query.where('branchIds', arrayContainsAny: userScope.branchIds);
      }
    }

    // Priority 3: No Access (Safety Fallback)
    // Return a query that is guaranteed to be empty
    return query.where(FieldPath.documentId, isEqualTo: 'force_empty_result');
  }

  Future<void> updateOrderStatus(
      BuildContext context,
      String orderId,
      String newStatus,
      {String? reason, String? currentUserEmail}
      ) async {
    // =========================================================
    // SECURITY: Input Validation
    // =========================================================
    // Validate orderId format
    final orderIdError = InputValidator.validateDocumentId(orderId, fieldName: 'Order ID');
    if (orderIdError != null) {
      debugPrint('🔒 SECURITY: Invalid orderId: $orderId');
      throw Exception('Invalid order ID format');
    }
    
    // Sanitize orderId (extra safety)
    final sanitizedOrderId = InputSanitizer.sanitizeDocumentId(orderId);
    
    // Validate and sanitize cancellation reason if provided
    String? sanitizedReason;
    if (reason != null && reason.isNotEmpty) {
      final reasonError = InputValidator.validateText(
        reason, 
        maxLength: InputLimits.maxCancellationReason,
        fieldName: 'Cancellation reason',
      );
      if (reasonError != null) {
        debugPrint('🔒 SECURITY: Invalid cancellation reason');
        throw Exception(reasonError);
      }
      sanitizedReason = InputSanitizer.sanitizeNotes(reason);
    }
    
    // Sanitize email if provided
    final sanitizedEmail = currentUserEmail != null 
        ? InputSanitizer.sanitizeEmail(currentUserEmail)
        : 'Admin';
    
    final orderRef = _db.collection(AppConstants.collectionOrders).doc(sanitizedOrderId);

    try {
      if (newStatus == AppConstants.statusCancelled) {
        await _db.runTransaction((transaction) async {
          final snapshot = await transaction.get(orderRef);
          if (!snapshot.exists) throw Exception("Order does not exist!");

          final data = snapshot.data() as Map<String, dynamic>;
          final currentStatus = AppConstants.normalizeStatus(data['status']);

          if (currentStatus == AppConstants.statusDelivered) {
            throw Exception("Cannot cancel an order that is already delivered!");
          }

          final Map<String, dynamic> updates = {
            'status': AppConstants.statusCancelled,
            'timestamps.cancelled': FieldValue.serverTimestamp(),
            'riderId': FieldValue.delete(),
          };

          if (sanitizedReason != null) updates['cancellationReason'] = sanitizedReason;
          updates['cancelledBy'] = sanitizedEmail;

          transaction.update(orderRef, updates);

          final String? riderId = data['riderId'];
          if (riderId != null && riderId.isNotEmpty) {
            final driverRef = _db.collection(AppConstants.collectionDrivers).doc(riderId);
            transaction.update(driverRef, {
              'assignedOrderId': '',
              'isAvailable': true,
            });
          }
        }).timeout(AppConstants.firestoreWriteTimeout);

        await RiderAssignmentService.cancelAutoAssignment(sanitizedOrderId);

      } else {
        final WriteBatch batch = _db.batch();
        final Map<String, dynamic> updateData = {'status': newStatus};

        // ========================================================
        // AUTO RIDER ASSIGNMENT: Trigger for delivery orders
        // ========================================================
        // When a delivery order moves to 'preparing', automatically start
        // the rider assignment workflow by setting the 'autoAssignStarted'
        // timestamp. This triggers the Cloud Function 'startAssignmentWorkflowV2'
        // which finds the nearest available rider and sends them an offer.
        if (newStatus == AppConstants.statusPreparing) {
          final orderDoc = await orderRef.get().timeout(AppConstants.firestoreTimeout);
          final data = orderDoc.data() as Map<String, dynamic>? ?? {};
          
          // Check both Order_type (primary) and orderType (fallback) field names
          final String orderType = (data['Order_type'] ?? data['orderType'] ?? '').toString().toLowerCase();
          final String? existingRiderId = data['riderId'];
          final bool hasAutoAssignStarted = data['autoAssignStarted'] != null;
          
          // Only trigger for delivery orders without an assigned rider
          // and where auto-assignment hasn't already been started
          if (orderType == 'delivery' && 
              (existingRiderId == null || existingRiderId.isEmpty) &&
              !hasAutoAssignStarted) {
            updateData['autoAssignStarted'] = FieldValue.serverTimestamp();
            updateData['lastAssignmentUpdate'] = FieldValue.serverTimestamp();
            debugPrint('🚀 Auto-assignment triggered for delivery order: $orderId');
          }
        }

        if (newStatus == AppConstants.statusDelivered) {
          updateData['timestamps.delivered'] = FieldValue.serverTimestamp();

          final orderDoc = await orderRef.get().timeout(AppConstants.firestoreTimeout);
          final data = orderDoc.data() as Map<String, dynamic>? ?? {};
          final String orderType = (data['Order_type'] as String?)?.toLowerCase() ?? '';
          final String? riderId = data['riderId'] as String?;

          if (orderType == 'delivery' && riderId != null && riderId.isNotEmpty) {
            final driverRef = _db.collection(AppConstants.collectionDrivers).doc(riderId);
            batch.update(driverRef, {
              'assignedOrderId': '',
              'isAvailable': true,
              'status': 'online', // Force online to correct any drift
            });
          }
        } else if (AppConstants.statusEquals(newStatus, AppConstants.statusPickedUp)) {
          updateData['timestamps.pickedUp'] = FieldValue.serverTimestamp();
        } else if (newStatus == AppConstants.statusRiderAssigned) {
          updateData['timestamps.riderAssigned'] = FieldValue.serverTimestamp();
        } else if (newStatus == AppConstants.statusPrepared) {
          updateData['timestamps.prepared'] = FieldValue.serverTimestamp();
        } else if (newStatus == AppConstants.statusServed) {
          updateData['timestamps.served'] = FieldValue.serverTimestamp();
        } else if (newStatus == AppConstants.statusPaid) {
          updateData['timestamps.paid'] = FieldValue.serverTimestamp();
        } else if (newStatus == AppConstants.statusCollected) {
          updateData['timestamps.collected'] = FieldValue.serverTimestamp();
        }

        batch.update(orderRef, updateData);
        await batch.commit().timeout(AppConstants.firestoreWriteTimeout);
      }
    } on TimeoutException {
      debugPrint("Timeout updating order: $orderId");
      rethrow;
    } catch (e, stack) {
      debugPrint("Error updating order: $e");
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Order Status Update Failed: $orderId -> $newStatus');
      rethrow;
    }
  }
}