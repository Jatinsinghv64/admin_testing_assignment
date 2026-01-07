import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../main.dart';
import 'TimeUtils.dart';
import '../Widgets/RiderAssignment.dart';
import '../constants.dart';

class OrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> getOrdersStream({
    required String orderType,
    required String status,
    required UserScopeService userScope,
    List<String>? filterBranchIds, // ✅ Optional filter
  }) {
    Query<Map<String, dynamic>> baseQuery = _db
        .collection(AppConstants.collectionOrders)
        .where('Order_type', isEqualTo: orderType);

    // Always filter by branches - SuperAdmin sees only their assigned branches
    if (filterBranchIds != null && filterBranchIds.isNotEmpty) {
      // Filter by provided specific branches (from BranchSelector)
      if (filterBranchIds.length == 1) {
        baseQuery = baseQuery.where('branchIds', arrayContains: filterBranchIds.first);
      } else {
        baseQuery = baseQuery.where('branchIds', arrayContainsAny: filterBranchIds);
      }
    } else if (userScope.branchIds.isNotEmpty) {
      // Fall back to user's assigned branches (for "All Branches" selection or initial state)
      if (userScope.branchIds.length == 1) {
        baseQuery = baseQuery.where('branchIds', arrayContains: userScope.branchIds.first);
      } else {
        baseQuery = baseQuery.where('branchIds', arrayContainsAny: userScope.branchIds);
      }
    } else {
      // User with no branches assigned - return empty
      return const Stream.empty();
    }

    if (status == 'all') {
      final startOfBusinessDay = TimeUtils.getBusinessStartTimestamp();
      final endOfBusinessDay = TimeUtils.getBusinessEndTimestamp();

      baseQuery = baseQuery
          .where('timestamp', isGreaterThanOrEqualTo: startOfBusinessDay)
          .where('timestamp', isLessThan: endOfBusinessDay);
    } else {
      // Handle status normalization for queries
      // Note: pickedUp vs pickedup - query for the normalized version
      final normalizedStatus = AppConstants.normalizeStatus(status);
      baseQuery = baseQuery.where('status', isEqualTo: normalizedStatus);
    }

    return baseQuery.orderBy('timestamp', descending: true).snapshots();
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
    Query<Map<String, dynamic>> query = _db.collection('menu_items'); // Hardcoded collection name from Dashboard

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
      'paid',
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
    final orderRef = _db.collection(AppConstants.collectionOrders).doc(orderId);

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

          if (reason != null) updates['cancellationReason'] = reason;
          updates['cancelledBy'] = currentUserEmail ?? 'Admin';

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

        await RiderAssignmentService.cancelAutoAssignment(orderId);

      } else {
        final WriteBatch batch = _db.batch();
        final Map<String, dynamic> updateData = {'status': newStatus};

        if (newStatus == AppConstants.statusDelivered) {
          updateData['timestamps.delivered'] = FieldValue.serverTimestamp();

          final orderDoc = await orderRef.get().timeout(AppConstants.firestoreTimeout);
          final data = orderDoc.data() as Map<String, dynamic>? ?? {};
          final String orderType = (data['Order_type'] as String?)?.toLowerCase() ?? '';
          final String? riderId = data['riderId'] as String?;

          if (orderType == 'delivery' && riderId != null && riderId.isNotEmpty) {
            final driverRef = _db.collection(AppConstants.collectionDrivers).doc(riderId);
            batch.update(driverRef, {'assignedOrderId': '', 'isAvailable': true});
          }
        } else if (AppConstants.statusEquals(newStatus, AppConstants.statusPickedUp)) {
          updateData['timestamps.pickedUp'] = FieldValue.serverTimestamp();
        } else if (newStatus == AppConstants.statusRiderAssigned) {
          updateData['timestamps.riderAssigned'] = FieldValue.serverTimestamp();
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