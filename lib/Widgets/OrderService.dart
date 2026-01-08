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
  /// Gets orders stream, handling both legacy `branchId` (string) and new `branchIds` (array) fields
  Stream<QuerySnapshot<Map<String, dynamic>>> getOrdersStream({
    required String orderType,
    required String status,
    required UserScopeService userScope,
    List<String>? filterBranchIds, // ✅ Optional filter
  }) {
    debugPrint('🔍 OrderService.getOrdersStream called:');
    debugPrint('   - orderType: $orderType');
    debugPrint('   - status: $status');
    debugPrint('   - filterBranchIds: $filterBranchIds');
    debugPrint('   - userScope.branchIds: ${userScope.branchIds}');
    
    final effectiveBranchIds = filterBranchIds ?? userScope.branchIds;
    
    if (effectiveBranchIds.isEmpty) {
      return const Stream.empty();
    }

    // ✅ FIX: Query for BOTH branchId (singular string) AND branchIds (array)
    // Some orders (like takeaway) use branchId, others use branchIds
    
    // Build two separate streams and merge them
    final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> mergedStream = 
        _getMergedOrdersStream(
          orderType: orderType,
          status: status,
          branchIds: effectiveBranchIds,
        );
    
    // Convert merged list back to a QuerySnapshot-like stream
    // We'll return a custom stream that OrdersScreen can consume
    return mergedStream.map((docs) {
      // Create a fake QuerySnapshot wrapper - but actually we need to return
      // QuerySnapshot type. Let's use a different approach.
      throw UnimplementedError('Use getOrdersStreamMerged instead');
    });
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

  /// Internal: Creates merged stream from both branchId and branchIds queries
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _getMergedOrdersStream({
    required String orderType,
    required String status,
    required List<String> branchIds,
  }) {
    // Query 1: Orders with branchIds array field
    Query<Map<String, dynamic>> arrayQuery = _db
        .collection(AppConstants.collectionOrders)
        .where('Order_type', isEqualTo: orderType);
    
    if (branchIds.length == 1) {
      arrayQuery = arrayQuery.where('branchIds', arrayContains: branchIds.first);
    } else {
      arrayQuery = arrayQuery.where('branchIds', arrayContainsAny: branchIds);
    }
    
    // Query 2: Orders with singular branchId string field (for each branch)
    // We need to use whereIn for branchId since it's a simple string field
    Query<Map<String, dynamic>> stringQuery = _db
        .collection(AppConstants.collectionOrders)
        .where('Order_type', isEqualTo: orderType)
        .where('branchId', whereIn: branchIds.take(10).toList()); // Firestore limit: 10 items in whereIn
    
    // Apply status/timestamp filters to both queries
    if (status == 'all') {
      final startOfBusinessDay = TimeUtils.getBusinessStartTimestamp();
      final endOfBusinessDay = TimeUtils.getBusinessEndTimestamp();
      
      arrayQuery = arrayQuery
          .where('timestamp', isGreaterThanOrEqualTo: startOfBusinessDay)
          .where('timestamp', isLessThan: endOfBusinessDay)
          .orderBy('timestamp', descending: true);
      
      stringQuery = stringQuery
          .where('timestamp', isGreaterThanOrEqualTo: startOfBusinessDay)
          .where('timestamp', isLessThan: endOfBusinessDay)
          .orderBy('timestamp', descending: true);
    } else {
      final normalizedStatus = AppConstants.normalizeStatus(status);
      arrayQuery = arrayQuery
          .where('status', isEqualTo: normalizedStatus)
          .orderBy('timestamp', descending: true);
      stringQuery = stringQuery
          .where('status', isEqualTo: normalizedStatus)
          .orderBy('timestamp', descending: true);
    }

    // Combine both streams
    final arrayStream = arrayQuery.snapshots();
    final stringStream = stringQuery.snapshots();

    // Merge and deduplicate
    return _combineStreams(arrayStream, stringStream);
  }

  /// Combines two QuerySnapshot streams and deduplicates by document ID
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _combineStreams(
    Stream<QuerySnapshot<Map<String, dynamic>>> stream1,
    Stream<QuerySnapshot<Map<String, dynamic>>> stream2,
  ) {
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs1 = [];
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs2 = [];

    // Use StreamController to emit merged results
    final controller = StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.broadcast();

    void emitMerged() {
      // Merge and deduplicate by document ID
      final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> merged = {};
      for (final doc in docs1) {
        merged[doc.id] = doc;
      }
      for (final doc in docs2) {
        merged[doc.id] = doc;
      }
      
      // Sort by timestamp descending
      final sortedDocs = merged.values.toList()
        ..sort((a, b) {
          final tsA = a.data()['timestamp'] as Timestamp?;
          final tsB = b.data()['timestamp'] as Timestamp?;
          if (tsA == null && tsB == null) return 0;
          if (tsA == null) return 1;
          if (tsB == null) return -1;
          return tsB.compareTo(tsA);
        });
      
      controller.add(sortedDocs);
    }

    final sub1 = stream1.listen((snapshot) {
      docs1 = snapshot.docs;
      emitMerged();
    }, onError: (e) => debugPrint('Stream1 error: $e'));

    final sub2 = stream2.listen((snapshot) {
      docs2 = snapshot.docs;
      emitMerged();
    }, onError: (e) => debugPrint('Stream2 error: $e'));

    controller.onCancel = () {
      sub1.cancel();
      sub2.cancel();
    };

    return controller.stream;
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