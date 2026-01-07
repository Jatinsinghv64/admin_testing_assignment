import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../constants.dart';

/// Result type for manual rider assignment
enum RiderAssignmentResult {
  success,
  timeout,
  orderNotFound,
  riderNotFound,
  orderAlreadyCompleted,
  unknownError,
}

/// Extension to get error message from RiderAssignmentResult
extension RiderAssignmentResultExtension on RiderAssignmentResult {
  String get message {
    switch (this) {
      case RiderAssignmentResult.success:
        return 'Rider assigned successfully';
      case RiderAssignmentResult.timeout:
        return 'Request timed out. Please check and retry.';
      case RiderAssignmentResult.orderNotFound:
        return 'Order not found';
      case RiderAssignmentResult.riderNotFound:
        return 'Rider not found';
      case RiderAssignmentResult.orderAlreadyCompleted:
        return 'Order is already completed. Assignment blocked.';
      case RiderAssignmentResult.unknownError:
        return 'Failed to assign rider. Please try again.';
    }
  }
  
  bool get isSuccess => this == RiderAssignmentResult.success;
  
  Color get backgroundColor {
    switch (this) {
      case RiderAssignmentResult.success:
        return Colors.green;
      case RiderAssignmentResult.timeout:
        return Colors.orange;
      default:
        return Colors.red;
    }
  }
}

class RiderAssignmentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Starts the auto-assignment workflow by updating the order.
  /// This triggers the Cloud Function 'startAssignmentWorkflowV2'.
  static Future<bool> autoAssignRider({
    required String orderId,
    required String branchId,
  }) async {
    try {
      final orderDoc = await _firestore
          .collection(AppConstants.collectionOrders)
          .doc(orderId)
          .get()
          .timeout(AppConstants.firestoreTimeout);
      
      if (!orderDoc.exists) return false;

      final data = orderDoc.data() as Map<String, dynamic>;
      final status = AppConstants.normalizeStatus(data['status'] as String? ?? '');
      final currentRider = data['riderId'] as String? ?? '';

      // Prevent triggering if already assigned or in a terminal state
      if (currentRider.isNotEmpty) return false;
      if (AppConstants.isTerminalStatus(status) ||
          status == AppConstants.statusRiderAssigned) {
        return false;
      }

      // Mark the order to start the background search loop in Cloud Functions
      await _firestore
          .collection(AppConstants.collectionOrders)
          .doc(orderId)
          .update({
            'autoAssignStarted': FieldValue.serverTimestamp(),
            'lastAssignmentUpdate': FieldValue.serverTimestamp(),
          })
          .timeout(AppConstants.firestoreWriteTimeout);
      
      return true;
    } on TimeoutException {
      debugPrint("Timeout starting auto-assignment for order $orderId");
      return false;
    } catch (e) {
      debugPrint("Error starting auto-assignment: $e");
      return false;
    }
  }

  /// Transaction-based Manual Assignment.
  /// Returns a RiderAssignmentResult to let the caller handle UI feedback.
  /// This avoids context issues when the calling widget is disposed.
  static Future<RiderAssignmentResult> manualAssignRider({
    required String orderId,
    required String riderId,
  }) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final orderRef = _firestore.collection(AppConstants.collectionOrders).doc(orderId);
        final riderRef = _firestore.collection(AppConstants.collectionDrivers).doc(riderId);
        final assignmentRef = _firestore.collection(AppConstants.collectionRiderAssignments).doc(orderId);

        // ✅ ALL READS MUST COME FIRST (Firestore transaction rule)
        final orderDoc = await transaction.get(orderRef);
        final riderDoc = await transaction.get(riderRef);
        final assignmentDoc = await transaction.get(assignmentRef);

        if (!orderDoc.exists) throw Exception("ORDER_NOT_FOUND");
        if (!riderDoc.exists) throw Exception("RIDER_NOT_FOUND");

        final orderData = orderDoc.data() as Map<String, dynamic>;
        final String currentStatus = AppConstants.normalizeStatus(orderData['status'] ?? '');

        // Block assignment if the order is already finished or cancelled
        if (AppConstants.isTerminalStatus(currentStatus)) {
          throw Exception("ORDER_COMPLETED");
        }

        // Simplified status flow: pending -> preparing -> rider_assigned
        // When a rider is manually assigned, advance to rider_assigned
        String statusToSet;
        if (currentStatus == AppConstants.statusPending) {
          // If pending, move to rider_assigned (rider will wait for food)
          statusToSet = AppConstants.statusRiderAssigned;
        } else if (currentStatus == AppConstants.statusPreparing ||
                   currentStatus == AppConstants.statusNeedsAssignment) {
          // Preparing or needs assignment - advance to rider_assigned
          statusToSet = AppConstants.statusRiderAssigned;
        } else if (currentStatus == AppConstants.statusRiderAssigned) {
          // Already assigned - don't change status
          statusToSet = currentStatus;
        } else {
          // For any other status, don't change it
          statusToSet = currentStatus;
        }

        // ✅ ALL WRITES COME AFTER ALL READS
        // 1. Update Order: Attach rider
        transaction.update(orderRef, {
          'riderId': riderId,
          'status': statusToSet,
          'timestamps.riderAssigned': FieldValue.serverTimestamp(),
          'assignmentNotes': 'Manually assigned by admin',
          'autoAssignStarted': FieldValue.delete(),
          'lastAssignmentUpdate': FieldValue.serverTimestamp(),
        });

        // 2. Update Driver: Mark as busy
        transaction.update(riderRef, {
          'assignedOrderId': orderId,
          'isAvailable': false,
        });

        // 3. Cleanup: Delete assignment record if it exists
        if (assignmentDoc.exists) {
          transaction.delete(assignmentRef);
        }
      }).timeout(AppConstants.firestoreWriteTimeout);

      // Send notification to the rider after the DB update succeeds
      _notifyRiderViaCloudFunction(orderId, riderId);

      return RiderAssignmentResult.success;
    } on TimeoutException {
      return RiderAssignmentResult.timeout;
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains("ORDER_NOT_FOUND")) {
        return RiderAssignmentResult.orderNotFound;
      } else if (errorStr.contains("RIDER_NOT_FOUND")) {
        return RiderAssignmentResult.riderNotFound;
      } else if (errorStr.contains("ORDER_COMPLETED")) {
        return RiderAssignmentResult.orderAlreadyCompleted;
      }
      debugPrint("Manual assignment error: $e");
      return RiderAssignmentResult.unknownError;
    }
  }

  /// Send FCM notification via Cloud Function (correct approach)
  /// Client-side FirebaseMessaging.sendMessage is for UPSTREAM messages only
  static Future<void> _notifyRiderViaCloudFunction(String orderId, String riderId) async {
    try {
      final callable = _functions.httpsCallable('sendRiderNotification');
      await callable.call({
        'riderId': riderId,
        'orderId': orderId,
        'title': '🎯 Order Assigned',
        'body': 'You have been assigned a new order. Tap to view details.',
      }).timeout(const Duration(seconds: 10));
      
      debugPrint('FCM notification sent via Cloud Function for order $orderId');
    } on TimeoutException {
      debugPrint('FCM notification call timed out for order $orderId');
    } catch (e) {
      // Don't fail the assignment if notification fails
      debugPrint('FCM notification via Cloud Function failed: $e');
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
      // Update order first
      await _firestore
          .collection(AppConstants.collectionOrders)
          .doc(orderId)
          .update({
            'autoAssignStarted': FieldValue.delete(),
            'assignmentNotes': 'Auto-assignment cancelled by admin',
          })
          .timeout(AppConstants.firestoreWriteTimeout);
      
      // Check if assignment record exists before deleting
      final assignmentDoc = await _firestore
          .collection(AppConstants.collectionRiderAssignments)
          .doc(orderId)
          .get()
          .timeout(AppConstants.firestoreTimeout);
      
      if (assignmentDoc.exists) {
        await _firestore
            .collection(AppConstants.collectionRiderAssignments)
            .doc(orderId)
            .delete()
            .timeout(AppConstants.firestoreWriteTimeout);
      }
    } on TimeoutException {
      debugPrint('Timeout cancelling auto-assignment for order $orderId');
    } catch (e) {
      debugPrint('Error cancelling auto-assignment: $e');
    }
  }
}