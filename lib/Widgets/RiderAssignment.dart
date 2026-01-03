import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../constants.dart'; // ✅ Added

class RiderAssignmentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<bool> autoAssignRider({
    required String orderId,
    required String branchId,
  }) async {
    try {
      // ✅ Use Constant
      final orderDoc = await _firestore.collection(AppConstants.collectionOrders).doc(orderId).get();
      if (!orderDoc.exists) return false;

      final data = orderDoc.data() as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';
      final currentRider = data['riderId'] as String? ?? '';

      if (currentRider.isNotEmpty) return false;

      if ([AppConstants.statusPickedUp, 'on_the_way', AppConstants.statusDelivered, AppConstants.statusCancelled].contains(status)) {
        return false;
      }

      if (status == AppConstants.statusPending) {
        await _firestore.collection(AppConstants.collectionOrders).doc(orderId).update({
          'status': AppConstants.statusPreparing,
          'autoAssignStarted': FieldValue.serverTimestamp(),
          'lastAssignmentUpdate': FieldValue.serverTimestamp(),
        });
        return true;
      }

      if (status == AppConstants.statusPreparing || status == AppConstants.statusPrepared) {
        await _firestore.collection(AppConstants.collectionOrders).doc(orderId).update({
          'lastAssignmentAttempt': FieldValue.serverTimestamp(),
        });
        return true;
      }
      return false;

    } catch (e) {
      return false;
    }
  }

  static Future<bool> manualAssignRider({
    required String orderId,
    required String riderId,
    required BuildContext context,
  }) async {
    try {
      final orderDoc = await _firestore.collection(AppConstants.collectionOrders).doc(orderId).get();
      if (!orderDoc.exists) throw Exception("Order not found");

      final orderData = orderDoc.data() as Map<String, dynamic>;
      final String currentStatus = orderData['status'] ?? '';

      if ([AppConstants.statusPickedUp, 'on_the_way', AppConstants.statusDelivered, AppConstants.statusCancelled].contains(currentStatus)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot assign rider. Order is already $currentStatus.'), backgroundColor: Colors.red));
        }
        return false;
      }

      await _cleanupAssignment(orderId);

      // ✅ Use Constant
      final riderDoc = await _firestore.collection(AppConstants.collectionDrivers).doc(riderId).get();
      final riderData = riderDoc.data() as Map<String, dynamic>? ?? {};
      final String? riderFcmToken = riderData['fcmToken'];
      final String riderName = riderData['name'] ?? 'Rider';

      final batch = _firestore.batch();
      final orderRef = _firestore.collection(AppConstants.collectionOrders).doc(orderId);

      batch.update(orderRef, {
        'riderId': riderId,
        'status': AppConstants.statusRiderAssigned,
        'timestamps.riderAssigned': FieldValue.serverTimestamp(),
        'assignmentNotes': 'Manually assigned by admin',
        'autoAssignStarted': FieldValue.delete(),
        'lastAssignmentUpdate': FieldValue.serverTimestamp(),
      });

      final riderRef = _firestore.collection(AppConstants.collectionDrivers).doc(riderId);
      batch.update(riderRef, {
        'assignedOrderId': orderId,
        'isAvailable': false,
      });

      await batch.commit();

      if (riderFcmToken != null && riderFcmToken.isNotEmpty) {
        await _sendRiderAssignmentNotification(
          fcmToken: riderFcmToken,
          orderId: orderId,
          riderName: riderName,
          orderData: orderData,
          isManualAssignment: true,
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rider $riderName assigned successfully'), backgroundColor: Colors.green));
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to assign rider: $e'), backgroundColor: Colors.red));
      }
      return false;
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
      await _cleanupAssignment(orderId);
    } catch (e) {
      print('❌ ERROR cancelling auto-assignment: $e');
    }
  }

  static Future<bool> isAutoAssigning(String orderId) async {
    try {
      final orderDoc = await _firestore.collection(AppConstants.collectionOrders).doc(orderId).get();
      final orderData = orderDoc.data() as Map<String, dynamic>?;
      return orderData != null && orderData.containsKey('autoAssignStarted');
    } catch (e) {
      return false;
    }
  }

  static Future<void> _cleanupAssignment(String orderId) async {
    try {
      // ✅ Use Constant
      await _firestore.collection(AppConstants.collectionRiderAssignments).doc(orderId).delete();
    } catch (e) {
      print('❌ ERROR during cleanup: $e');
    }
  }

  // ... (_sendRiderAssignmentNotification remains unchanged) ...
  static Future<void> _sendRiderAssignmentNotification({
    required String fcmToken,
    required String orderId,
    required String riderName,
    required Map<String, dynamic> orderData,
    required bool isManualAssignment,
  }) async {
    // ... (Code same as original) ...
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
    } catch (e) {
      print('❌ FCM ERROR: $e');
    }
  }
}