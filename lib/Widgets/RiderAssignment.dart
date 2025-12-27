import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

class RiderAssignmentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ========== MAIN ASSIGNMENT METHODS ==========

  /// Triggers the server-side auto-assignment workflow by updating the order status.
  /// The actual logic (finding riders, timers) now lives in Firebase Cloud Functions.
  static Future<bool> autoAssignRider({
    required String orderId,
    required String branchId,
  }) async {
    print('🚀 AUTO-ASSIGNMENT REQUESTED FOR ORDER: $orderId');

    try {
      final orderDoc = await _firestore.collection('Orders').doc(orderId).get();
      if (!orderDoc.exists) {
        print('❌ Order $orderId not found');
        return false;
      }

      final data = orderDoc.data() as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';
      final currentRider = data['riderId'] as String? ?? '';

      // 1. Validation
      if (currentRider.isNotEmpty) {
        print('⚠️ Order already has a rider: $currentRider');
        return false;
      }

      // 2. Trigger Logic
      // If the order is 'pending', moving it to 'preparing' will TRIGGER the Cloud Function.
      if (status == 'pending') {
        await _firestore.collection('Orders').doc(orderId).update({
          'status': 'preparing',
          'autoAssignStarted': FieldValue.serverTimestamp(), // UI indicator
          'lastAssignmentUpdate': FieldValue.serverTimestamp(),
        });
        print('✅ Order status updated to "preparing". Server workflow triggered.');
        return true;
      }

      // 3. If already preparing/prepared
      // The Cloud Function should already be running.
      if (status == 'preparing' || status == 'prepared') {
        print('ℹ️ Order is already in "$status" state. Server should be handling it.');
        // We update a timestamp just to ensure the UI knows we tried
        await _firestore.collection('Orders').doc(orderId).update({
          'lastAssignmentAttempt': FieldValue.serverTimestamp(),
        });
        return true;
      }

      print('⚠️ Order status "$status" is not valid for auto-assignment start.');
      return false;

    } catch (e) {
      print('❌ Error in autoAssignRider: $e');
      return false;
    }
  }

  /// Manually assigns a specific rider to an order.
  /// This bypasses the server algorithm and forces the assignment.
  static Future<bool> manualAssignRider({
    required String orderId,
    required String riderId,
    required BuildContext context,
  }) async {
    try {
      // 1. Clean up any running auto-assignments first
      await _cleanupAssignment(orderId);

      // 2. Fetch Data
      final orderDoc = await _firestore.collection('Orders').doc(orderId).get();
      final orderData = orderDoc.data() as Map<String, dynamic>? ?? {};

      final riderDoc = await _firestore.collection('Drivers').doc(riderId).get();
      final riderData = riderDoc.data() as Map<String, dynamic>? ?? {};
      final String? riderFcmToken = riderData['fcmToken'];
      final String riderName = riderData['name'] ?? 'Rider';

      // 3. Perform Updates (Batch for safety)
      final batch = _firestore.batch();

      final orderRef = _firestore.collection('Orders').doc(orderId);
      batch.update(orderRef, {
        'riderId': riderId,
        'status': 'rider_assigned',
        'timestamps.riderAssigned': FieldValue.serverTimestamp(),
        'assignmentNotes': 'Manually assigned by admin',
        'autoAssignStarted': FieldValue.delete(), // Stop any UI loaders
        'lastAssignmentUpdate': FieldValue.serverTimestamp(),
      });

      final riderRef = _firestore.collection('Drivers').doc(riderId);
      batch.update(riderRef, {
        'assignedOrderId': orderId,
        'isAvailable': false,
      });

      await batch.commit();

      // 4. Send Notification
      // Since this is a manual override, we send the notification from the client
      // because the Cloud Function 'startAssignmentWorkflow' might not trigger here.
      if (riderFcmToken != null && riderFcmToken.isNotEmpty) {
        await _sendRiderAssignmentNotification(
          fcmToken: riderFcmToken,
          orderId: orderId,
          riderName: riderName,
          orderData: orderData,
          isManualAssignment: true,
        );
      } else {
        print('⚠️ No FCM token found for rider $riderId, notification not sent');
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rider $riderName assigned successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }

      print('✅ MANUAL ASSIGNMENT SUCCESSFUL: Rider $riderId assigned to order $orderId');
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to assign rider: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('❌ MANUAL ASSIGNMENT FAILED: $e');
      return false;
    }
  }

  // ========== UTILITY METHODS ==========

  static Stream<QuerySnapshot> getOrdersNeedingAssignment() {
    return _firestore
        .collection('Orders')
        .where('status', isEqualTo: 'needs_rider_assignment')
        .snapshots();
  }

  static Future<void> cancelAutoAssignment(String orderId) async {
    try {
      // This stops the UI spinner.
      // Note: If the Cloud Task is already scheduled on the server, 
      // it will run but fail to find the 'rider_assignments' doc if we delete it here.
      await _firestore.collection('Orders').doc(orderId).update({
        'autoAssignStarted': FieldValue.delete(),
        'assignmentNotes': 'Auto-assignment cancelled by admin',
      });
      await _cleanupAssignment(orderId);
      print('🛑 AUTO-ASSIGNMENT CANCELLED: Order $orderId');
    } catch (e) {
      print('❌ ERROR cancelling auto-assignment: $e');
    }
  }

  static Future<bool> isAutoAssigning(String orderId) async {
    try {
      final orderDoc = await _firestore.collection('Orders').doc(orderId).get();
      final orderData = orderDoc.data() as Map<String, dynamic>?;
      return orderData != null && orderData.containsKey('autoAssignStarted');
    } catch (e) {
      return false;
    }
  }

  // Helper to remove temporary assignment documents
  static Future<void> _cleanupAssignment(String orderId) async {
    try {
      await _firestore.collection('rider_assignments').doc(orderId).delete();
      print('🧹 CLEANUP: Removed assignment documents for order $orderId');
    } catch (e) {
      print('❌ ERROR during cleanup: $e');
    }
  }

  // Helper to mark order as failed/needs manual help
  static Future<void> _markOrderAsNeedsManualAssignment(String orderId, String reason) async {
    try {
      await _firestore.collection('Orders').doc(orderId).update({
        'status': 'needs_rider_assignment',
        'assignmentNotes': reason,
        'needsAssignmentAt': FieldValue.serverTimestamp(),
        'autoAssignStarted': FieldValue.delete(),
      });
      await _cleanupAssignment(orderId);
    } catch (e) {
      print('❌ ERROR marking for manual assignment: $e');
    }
  }

  // Helper to send FCM (Kept primarily for Manual Assignment)
  static Future<void> _sendRiderAssignmentNotification({
    required String fcmToken,
    required String orderId,
    required String riderName,
    required Map<String, dynamic> orderData,
    required bool isManualAssignment,
  }) async {
    try {
      final String orderNumber = orderData['dailyOrderNumber']?.toString() ?? orderId.substring(0, 6).toUpperCase();
      final double totalAmount = (orderData['totalAmount'] as num?)?.toDouble() ?? 0.0;
      final String customerName = orderData['customerName'] ?? 'Customer';
      final String orderType = orderData['Order_type'] ?? 'delivery';
      final String deliveryAddress = orderData['deliveryAddress']?['street'] ?? '';

      final String title = isManualAssignment ? '🎯 Order Assigned' : '📦 New Order Available';
      final String body = isManualAssignment
          ? 'You have been assigned to Order #$orderNumber'
          : 'New $orderType Order - QAR ${totalAmount.toStringAsFixed(2)}';

      final Map<String, dynamic> notificationPayload = {
        'message': {
          'token': fcmToken,
          'notification': {
            'title': title,
            'body': body,
          },
          'data': {
            'type': isManualAssignment ? 'manual_assignment' : 'auto_assignment',
            'orderId': orderId,
            'orderNumber': orderNumber,
            'riderId': riderName,
            'totalAmount': totalAmount.toString(),
            'customerName': customerName,
            'orderType': orderType,
            'deliveryAddress': deliveryAddress,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
          'android': {
            'priority': 'high',
            'notification': {
              'channel_id': 'order_assignments',
              'sound': 'default',
            },
          },
        }
      };

      await FirebaseMessaging.instance.sendMessage(
        data: notificationPayload['message']['data'],
      );

      print('📱 NOTIFICATION SENT: To rider $riderName');
    } catch (e) {
      print('❌ FCM ERROR: $e');
    }
  }

  static void dispose() {
    // No active timers to dispose anymore!
  }
}