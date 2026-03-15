import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../main.dart';
import 'TimeUtils.dart';
import '../Widgets/RiderAssignment.dart';
import '../constants.dart';
import '../utils/security_utils.dart';
import '../services/inventory/InventoryService.dart';

class OrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @Deprecated('Use getOrdersStreamMerged instead. This method returns empty stream.')
  Stream<QuerySnapshot<Map<String, dynamic>>> getOrdersStream({
    required String orderType,
    required String status,
    required UserScopeService userScope,
    List<String>? filterBranchIds,
  }) {
    return const Stream.empty();
  }

  /// Returns merged stream of order documents (handles both branchId and branchIds)
  /// Industry Grade: Added [activeOnly] flag to heavily reduce memory usage on POS/KDS devices
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getOrdersStreamMerged({
    String? orderType, // Nullable to fetch all types if needed (useful for KDS)
    required String status,
    required UserScopeService userScope,
    List<String>? filterBranchIds,
    bool activeOnly = false,
  }) {
    final effectiveBranchIds = filterBranchIds ?? userScope.branchIds;

    if (effectiveBranchIds.isEmpty && !userScope.isSuperAdmin) {
      return Stream.value([]);
    }

    Query<Map<String, dynamic>> arrayQuery = _db.collection(AppConstants.collectionOrders);
    
    // Apply refined branch filtering
    arrayQuery = _applyBranchFilter(arrayQuery, userScope, filterBranchIds);

    if (orderType != null && orderType != 'all') {
      arrayQuery = arrayQuery.where('Order_type', isEqualTo: orderType);
    }

    // Performance Optimization for KDS/POS: Only fetch actively moving tickets
    if (activeOnly) {
      arrayQuery = arrayQuery.where('status', whereIn: [
        AppConstants.statusPending,
        AppConstants.statusPreparing,
        AppConstants.statusPrepared,
        AppConstants.statusServed,
        AppConstants.statusNeedsAssignment,
        AppConstants.statusRiderAssigned,
        AppConstants.statusPickedUp,
      ]).orderBy('timestamp', descending: false); // Oldest first for KDS
    } else if (status == 'all') {
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

  Stream<QuerySnapshot<Map<String, dynamic>>> getTodayOrdersStream({
    required UserScopeService userScope,
    List<String>? filterBranchIds,
  }) {
    final startOfShift = TimeUtils.getBusinessStartTimestamp();
    Query<Map<String, dynamic>> query = _db.collection(AppConstants.collectionOrders);
    query = _applyBranchFilter(query, userScope, filterBranchIds);
    return query
        .where('timestamp', isGreaterThanOrEqualTo: startOfShift)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getActiveDriversStream({
    required UserScopeService userScope,
    List<String>? filterBranchIds,
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection(AppConstants.collectionDrivers)
        .where('isAvailable', isEqualTo: true);
    query = _applyBranchFilter(query, userScope, filterBranchIds);
    return query.snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getAvailableMenuItemsStream({
    required UserScopeService userScope,
    List<String>? filterBranchIds,
  }) {
    Query<Map<String, dynamic>> query = _db.collection(AppConstants.collectionMenuItems);
    query = _applyBranchFilter(query, userScope, filterBranchIds);
    return query.where('isAvailable', isEqualTo: true).snapshots();
  }

  static double calculateRevenue(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    double totalRevenue = 0;
    final billableStatuses = {
      AppConstants.statusDelivered,
      'completed',
      AppConstants.statusPaid,
      AppConstants.statusCollected,
    };

    for (var doc in docs) {
      final data = doc.data();
      final status = (data['status'] ?? '').toString().toLowerCase();
      final isExchange = data['isExchange'] == true;

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

  Query<Map<String, dynamic>> _applyBranchFilter(
      Query<Map<String, dynamic>> query,
      UserScopeService userScope,
      List<String>? filterBranchIds,
      ) {
    // 1. If explicit filter is selected (e.g. from dropdown)
    if (filterBranchIds != null && filterBranchIds.isNotEmpty) {
      if (filterBranchIds.length == 1) {
        return query.where('branchIds', arrayContains: filterBranchIds.first);
      } else if (filterBranchIds.length <= 10) {
        return query.where('branchIds', arrayContainsAny: filterBranchIds);
      }
      // If more than 10, and user is SuperAdmin, showing all is better than failing
      if (userScope.isSuperAdmin) return query;
      // For non-super admins, we have to limit to 10 due to Firestore restrictions
      return query.where('branchIds', arrayContainsAny: filterBranchIds.take(10).toList());
    }

    // 2. No filter selected - use user's scope
    if (userScope.isSuperAdmin) {
       // SuperAdmin sees all by default in global view
       return query;
    }

    if (userScope.branchIds.isNotEmpty) {
      if (userScope.branchIds.length == 1) {
        return query.where('branchIds', arrayContains: userScope.branchIds.first);
      } else {
        // Limit to 10 for Firestore compatibility
        return query.where('branchIds', arrayContainsAny: userScope.branchIds.take(10).toList());
      }
    }

    return query.where(FieldPath.documentId, isEqualTo: 'force_empty_result');
  }

  /// INDUSTRY GRADE FIX: Atomic Exchange Transaction.
  /// Prevents data corruption if a user clicks "Exchange" twice rapidly.
  Future<void> processExchange(String orderId, String reason, String adminEmail) async {
    final sanitizedOrderId = InputSanitizer.sanitizeDocumentId(orderId);
    final orderRef = _db.collection(AppConstants.collectionOrders).doc(sanitizedOrderId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(orderRef);
      if (!snapshot.exists) throw Exception("Order does not exist!");

      transaction.update(orderRef, {
        'status': AppConstants.statusPreparing,
        'isExchange': true,
        'exchangeDetails': {
          'reason': reason,
          'timestamp': FieldValue.serverTimestamp(),
          'adminId': adminEmail,
        },
        // Log the return in history
        'statusHistory': FieldValue.arrayUnion([{
          'status': AppConstants.statusPreparing,
          'timestamp': FieldValue.serverTimestamp(),
          'note': 'Exchange Requested: $reason'
        }])
      });
    });
  }

  Future<void> updateOrderStatus(
      BuildContext context, String orderId, String newStatus,
      {String? reason, String? currentUserEmail}) async {

    final orderIdError = InputValidator.validateDocumentId(orderId, fieldName: 'Order ID');
    if (orderIdError != null) throw Exception('Invalid order ID format');

    final sanitizedOrderId = InputSanitizer.sanitizeDocumentId(orderId);
    String? sanitizedReason;

    if (reason != null && reason.isNotEmpty) {
      sanitizedReason = InputSanitizer.sanitizeNotes(reason);
    }

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

          if (AppConstants.isTerminalStatus(currentStatus)) {
            throw Exception("Cannot cancel an order that is already completed!");
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
        await _db.runTransaction((transaction) async {
          final snapshot = await transaction.get(orderRef);
          if (!snapshot.exists) throw Exception("Order does not exist!");

          final data = snapshot.data() as Map<String, dynamic>;
          final currentStatus = AppConstants.normalizeStatus(data['status']);

          final isRecallToKitchen = newStatus == AppConstants.statusPreparing &&
              currentStatus != AppConstants.statusPending &&
              currentStatus != AppConstants.statusPreparing &&
              currentStatus != AppConstants.statusCancelled;

          if (AppConstants.isTerminalStatus(currentStatus) && !isRecallToKitchen && newStatus != AppConstants.statusRefunded) {
            throw Exception("Cannot update order - it is already $currentStatus");
          }

          final Map<String, dynamic> updateData = {'status': newStatus};

          // INDUSTRY GRADE FIX: Auto-Assignment Loop Bug
          // If KDS recalls an order, instantly strip the old rider to prevent ghost dispatching.
          if (isRecallToKitchen) {
            updateData['riderId'] = FieldValue.delete();
            updateData['autoAssignStarted'] = FieldValue.delete();

            final String? oldRiderId = data['riderId'];
            if (oldRiderId != null && oldRiderId.isNotEmpty) {
              final driverRef = _db.collection(AppConstants.collectionDrivers).doc(oldRiderId);
              transaction.update(driverRef, {
                'assignedOrderId': '',
                'isAvailable': true,
              });
            }
          }

          if (newStatus == AppConstants.statusPreparing && !isRecallToKitchen) {
            final String orderType = (data['Order_type'] ?? data['orderType'] ?? '').toString().toLowerCase();
            final String? existingRiderId = data['riderId'];
            final bool hasAutoAssignStarted = data['autoAssignStarted'] != null;

            if (orderType == 'delivery' && (existingRiderId == null || existingRiderId.isEmpty) && !hasAutoAssignStarted) {
              updateData['autoAssignStarted'] = FieldValue.serverTimestamp();
              updateData['lastAssignmentUpdate'] = FieldValue.serverTimestamp();
            }
          }

          if (newStatus == AppConstants.statusDelivered) {
            updateData['timestamps.delivered'] = FieldValue.serverTimestamp();
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
          } else if (newStatus == AppConstants.statusRefunded) {
            updateData['timestamps.refunded'] = FieldValue.serverTimestamp();
            if (sanitizedReason != null) updateData['refundReason'] = sanitizedReason;
          }

          transaction.update(orderRef, updateData);

          const terminalForDeduction = {
            AppConstants.statusDelivered,
            AppConstants.statusPaid,
            AppConstants.statusCollected,
          };
          if (terminalForDeduction.contains(newStatus)) {
            await InventoryService().performDeductionInTransaction(
              transaction: transaction,
              orderId: sanitizedOrderId,
              branchIds: data['branchIds'] is List 
                  ? List<String>.from(data['branchIds']) 
                  : [data['branchId']?.toString() ?? ''],
              recordedBy: sanitizedEmail,
            );
          }

          if (newStatus == AppConstants.statusDelivered) {
            final String orderType = (data['Order_type'] as String?)?.toLowerCase() ?? '';
            final String? riderId = data['riderId'] as String?;

            if (orderType == 'delivery' && riderId != null && riderId.isNotEmpty) {
              final driverRef = _db.collection(AppConstants.collectionDrivers).doc(riderId);
              transaction.update(driverRef, {
                'assignedOrderId': '',
                'isAvailable': true,
                'status': 'online',
              });
            }
          }
        }).timeout(AppConstants.firestoreWriteTimeout);

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