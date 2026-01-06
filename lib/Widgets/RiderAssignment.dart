import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../constants.dart';

class RiderAssignmentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Starts the auto-assignment workflow by updating the order.
  /// This triggers the Cloud Function 'startAssignmentWorkflowV2'.
  static Future<bool> autoAssignRider({
    required String orderId,
    required String branchId,
  }) async {
    try {
      final orderDoc = await _firestore.collection(AppConstants.collectionOrders).doc(orderId).get();
      if (!orderDoc.exists) return false;

      final data = orderDoc.data() as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';
      final currentRider = data['riderId'] as String? ?? '';

      // Prevent triggering if already assigned or in a terminal state
      if (currentRider.isNotEmpty) return false;
      if ([AppConstants.statusPickedUp, AppConstants.statusDelivered, AppConstants.statusCancelled].contains(status)) {
        return false;
      }

      // Mark the order to start the background search loop in Cloud Functions
      await _firestore.collection(AppConstants.collectionOrders).doc(orderId).update({
        'autoAssignStarted': FieldValue.serverTimestamp(),
        'lastAssignmentUpdate': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint("Error starting auto-assignment: $e");
      return false;
    }
  }

  /// Transaction-based Manual Assignment.
  /// Decouples kitchen preparation from rider assignment logic.
  static Future<bool> manualAssignRider({
    required String orderId,
    required String riderId,
    required BuildContext context,
  }) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final orderRef = _firestore.collection(AppConstants.collectionOrders).doc(orderId);
        final riderRef = _firestore.collection(AppConstants.collectionDrivers).doc(riderId);
        final assignmentRef = _firestore.collection(AppConstants.collectionRiderAssignments).doc(orderId);

        final orderDoc = await transaction.get(orderRef);
        final riderDoc = await transaction.get(riderRef);

        if (!orderDoc.exists) throw Exception("Order not found");
        if (!riderDoc.exists) throw Exception("Rider not found");

        final orderData = orderDoc.data() as Map<String, dynamic>;
        final String currentStatus = orderData['status'] ?? '';

        // Block assignment if the order is already finished or cancelled
        if ([
          AppConstants.statusPickedUp,
          AppConstants.statusDelivered,
          AppConstants.statusCancelled
        ].contains(currentStatus)) {
          throw Exception("Order is already $currentStatus. Assignment blocked.");
        }

        // ROBUSTNESS FIX: Do not skip the kitchen state.
        // Rider assignment should NOT override kitchen preparation status.
        // Only set to "Rider Assigned" if the food is already "Prepared".
        String statusToSet;
        if (currentStatus == AppConstants.statusPending) {
          // If pending, at minimum move to preparing (order is being worked on)
          statusToSet = AppConstants.statusPreparing;
        } else if (currentStatus == AppConstants.statusPreparing) {
          // Keep as preparing - kitchen staff will mark as prepared when ready
          statusToSet = AppConstants.statusPreparing;
        } else if (currentStatus == AppConstants.statusPrepared) {
          // Food is ready, now we can advance to rider_assigned
          statusToSet = AppConstants.statusRiderAssigned;
        } else {
          // For any other status (rider_assigned, pickedUp, etc.), don't change it
          statusToSet = currentStatus;
        }

        // 1. Update Order: Attach rider without necessarily changing preparation status
        transaction.update(orderRef, {
          'riderId': riderId,
          'status': statusToSet,
          'timestamps.riderAssigned': FieldValue.serverTimestamp(),
          'assignmentNotes': 'Manually assigned by admin',
          'autoAssignStarted': FieldValue.delete(), // Stop any active auto-search
          'lastAssignmentUpdate': FieldValue.serverTimestamp(),
        });

        // 2. Update Driver: Mark as busy
        transaction.update(riderRef, {
          'assignedOrderId': orderId,
          'isAvailable': false,
        });

        // 3. Cleanup: Remove any pending auto-assignment records
        transaction.delete(assignmentRef);
      });

      // Send notifications to the rider after the DB update succeeds
      _notifyRider(orderId, riderId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rider assigned successfully'), backgroundColor: Colors.green),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        final String errorMsg = e.toString().replaceAll("Exception: ", "");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to assign rider: $errorMsg'), backgroundColor: Colors.red),
        );
      }
      return false;
    }
  }

  /// Internal helper to fetch data and send FCM
  static Future<void> _notifyRider(String orderId, String riderId) async {
    try {
      final riderDoc = await _firestore.collection(AppConstants.collectionDrivers).doc(riderId).get();
      final orderDoc = await _firestore.collection(AppConstants.collectionOrders).doc(orderId).get();

      if (riderDoc.exists && orderDoc.exists) {
        final riderData = riderDoc.data()!;
        final orderData = orderDoc.data()!;
        final String? token = riderData['fcmToken'];

        if (token != null && token.isNotEmpty) {
          await _sendRiderAssignmentNotification(
            fcmToken: token,
            orderId: orderId,
            riderName: riderData['name'] ?? 'Rider',
            orderData: orderData,
            isManualAssignment: true,
          );
        }
      }
    } catch (e) {
      debugPrint("Notification failed: $e");
    }
  }

  static Stream<QuerySnapshot> getOrdersNeedingAssignment() {
    return _firestore
        .collection(AppConstants.collectionOrders)
        .where('status', isEqualTo: AppConstants.statusNeedsAssignment)
        .snapshots();
  }

  static Future<void> cancelAutoAssignment(String orderId) async {
    try {
      await _firestore.collection(AppConstants.collectionOrders).doc(orderId).update({
        'autoAssignStarted': FieldValue.delete(),
        'assignmentNotes': 'Auto-assignment cancelled by admin',
      });
      await _firestore.collection(AppConstants.collectionRiderAssignments).doc(orderId).delete();
    } catch (e) {
      debugPrint('Error cancelling auto-assignment: $e');
    }
  }

  static Future<void> _sendRiderAssignmentNotification({
    required String fcmToken,
    required String orderId,
    required String riderName,
    required Map<String, dynamic> orderData,
    required bool isManualAssignment,
  }) async {
    try {
      final String orderNumber = orderData['dailyOrderNumber']?.toString() ?? orderId.substring(0, 6).toUpperCase();
      final String title = isManualAssignment ? '🎯 Order Assigned' : '📦 New Order Available';

      // Since this is standard FCM logic, we use standard message structure
      await FirebaseMessaging.instance.sendMessage(
        data: {
          'type': isManualAssignment ? 'manual_assignment' : 'auto_assignment',
          'orderId': orderId,
          'orderNumber': orderNumber,
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
      );
    } catch (e) {
      debugPrint('FCM Error: $e');
    }
  }
}