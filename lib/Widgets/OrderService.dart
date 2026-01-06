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
  }) {
    Query<Map<String, dynamic>> baseQuery = _db
        .collection(AppConstants.collectionOrders)
        .where('Order_type', isEqualTo: orderType);

    if (userScope.isSuperAdmin && userScope.branchIds.isEmpty) {
      // Show ALL orders if SuperAdmin has no specific branch selection
    } else if (userScope.branchIds.isNotEmpty) {
      // Filter by assigned branches (for BranchAdmin OR SuperAdmin with selection)
      baseQuery = baseQuery.where('branchIds', arrayContainsAny: userScope.branchIds);
    } else {
      // Non-SuperAdmin with no branches? Should not happen, but safe to return matches-none or handle gracefully
      // For now, let's assume they have branches if they are logged in as BranchAdmin.
      // If empty, this query would fail with arrayContainsAny([]);
      // So we prevent the query execution? Or just return valid stream.
      // We'll standardly filter if not empty. If empty and not SuperAdmin, maybe return empty?
      // Let's stick to the else-if logic above. If branchIds is empty and NOT SuperAdmin, we do nothing?
      // No, we must filter. If list is empty, we must return nothing.
      // Firestore throws on empty list.
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