//
//
// import 'dart:async';
// import 'dart:math';
//
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter/material.dart';
//
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter/material.dart';
// import 'dart:async';
// import 'dart:math';
//
// class RiderAssignmentService {
//   static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
//   static final Map<String, StreamSubscription> _activeSubscriptions = {};
//   static final Map<String, Timer> _activeTimers = {};
//
//   // Calculate distance between two coordinates using Haversine formula
//   static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
//     const double earthRadius = 6371; // kilometers
//     double dLat = _toRadians(lat2 - lat1);
//     double dLon = _toRadians(lon2 - lon1);
//     double a = sin(dLat / 2) * sin(dLat / 2) +
//         cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
//     double c = 2 * atan2(sqrt(a), sqrt(1 - a));
//     return earthRadius * c;
//   }
//
//   static double _toRadians(double degree) {
//     return degree * pi / 180;
//   }
//
//   // Get restaurant location for a branch
//   static Future<GeoPoint> _getRestaurantLocation(String branchId) async {
//     try {
//       final doc = await _firestore.collection('Branch').doc(branchId).get();
//       final data = doc.data() as Map<String, dynamic>?;
//
//       if (data != null && data['location'] != null) {
//         return data['location'] as GeoPoint;
//       }
//
//       print("⚠️ Warning: No location found for branch '$branchId'. Using default.");
//       return const GeoPoint(25.2614, 51.5651);
//     } catch (e) {
//       print('❌ Error getting restaurant location for branch $branchId: $e');
//       return const GeoPoint(25.2614, 51.5651);
//     }
//   }
//
//   // Find nearest riders for a specific branch
//   static Future<List<Map<String, dynamic>>> _findNearestRiders(
//       GeoPoint restaurantLocation,
//       int limit,
//       String branchId,
//       ) async {
//     try {
//       Query query = _firestore
//           .collection('Drivers')
//           .where('isAvailable', isEqualTo: true)
//           .where('status', isEqualTo: 'online')
//           .where('branchIds', arrayContains: branchId);
//
//       final QuerySnapshot snapshot = await query.get();
//
//       final List<Map<String, dynamic>> ridersWithDistance = [];
//
//       for (var doc in snapshot.docs) {
//         final data = doc.data() as Map<String, dynamic>;
//         final GeoPoint? riderLocation = data['currentLocation'] as GeoPoint?;
//
//         if (riderLocation != null) {
//           final double distance = _calculateDistance(
//             restaurantLocation.latitude,
//             restaurantLocation.longitude,
//             riderLocation.latitude,
//             riderLocation.longitude,
//           );
//
//           ridersWithDistance.add({
//             'riderId': doc.id,
//             'distance': distance,
//             'data': data,
//             'location': riderLocation,
//           });
//         }
//       }
//
//       ridersWithDistance.sort((a, b) => a['distance'].compareTo(b['distance']));
//       return ridersWithDistance.take(limit).toList();
//     } catch (e) {
//       print('❌ Error finding nearest riders for branch $branchId: $e');
//       return [];
//     }
//   }
//
//   // Send assignment request to a rider
//   static Future<bool> _sendAssignmentRequest({
//     required String orderId,
//     required String riderId,
//     required int timeoutSeconds,
//     required Set<String> triedRiders,
//     required String branchId,
//   }) async {
//     try {
//       final updatedTriedRiders = triedRiders.toSet()..add(riderId);
//       final attemptNumber = updatedTriedRiders.length;
//
//       print('📋 CREATING IMMEDIATE ASSIGNMENT: Order $orderId -> Rider $riderId (Attempt #$attemptNumber)');
//
//       await _firestore.collection('rider_assignments').doc(orderId).set({
//         'orderId': orderId,
//         'riderId': riderId,
//         'status': 'pending',
//         'createdAt': FieldValue.serverTimestamp(),
//         'expiresAt': Timestamp.fromDate(DateTime.now().add(Duration(seconds: timeoutSeconds))),
//         'timeoutSeconds': timeoutSeconds,
//         'triedRiders': updatedTriedRiders.toList(),
//         'assignmentAttempt': attemptNumber,
//         'notificationSent': false,
//         'assignedAt': FieldValue.serverTimestamp(),
//         'branchId': branchId,
//       });
//
//       print('✅ IMMEDIATE ASSIGNMENT SENT: Rider $riderId for order $orderId (Attempt #$attemptNumber)');
//
//       _startAssignmentTimeout(orderId, riderId, timeoutSeconds, updatedTriedRiders, branchId);
//       return true;
//     } catch (e) {
//       print('❌ ERROR sending immediate assignment request: $e');
//       return false;
//     }
//   }
//
//   // Start timeout for rider response
//   static void _startAssignmentTimeout(String orderId, String riderId, int timeoutSeconds, Set<String> triedRiders, String branchId) {
//     final assignmentDoc = _firestore.collection('rider_assignments').doc(orderId);
//
//     _cancelExistingSubscription(orderId);
//     bool handled = false;
//
//     final StreamSubscription subscription = assignmentDoc.snapshots().listen((snapshot) async {
//       if (!snapshot.exists || handled) return;
//
//       final data = snapshot.data() as Map<String, dynamic>?;
//       final status = data?['status'] as String?;
//       final currentRiderId = data?['riderId'] as String?;
//
//       print('📢 RIDER ASSIGNMENT UPDATE: Order $orderId, Rider $currentRiderId, Status: $status');
//
//       if (currentRiderId != riderId) {
//         print('⚠️ RIDER ID MISMATCH: Expected $riderId, got $currentRiderId. Ignoring update.');
//         return;
//       }
//
//       if (status == 'accepted') {
//         handled = true;
//         print('✅ RIDER ACCEPTED: Rider $riderId accepted order $orderId');
//         _cancelExistingSubscription(orderId);
//         await _completeAssignment(orderId, riderId);
//       } else if (status == 'rejected') {
//         handled = true;
//         print('❌ RIDER REJECTED: Rider $riderId rejected order $orderId');
//         _cancelExistingSubscription(orderId);
//         await _handleAssignmentRejection(orderId, triedRiders, branchId);
//       } else if (status == 'timeout') {
//         handled = true;
//         print('⏰ RIDER TIMEOUT: Rider $riderId timed out for order $orderId');
//         _cancelExistingSubscription(orderId);
//         await _handleAssignmentRejection(orderId, triedRiders, branchId);
//       }
//     }, onError: (error) {
//       print('❌ STREAM ERROR for order $orderId: $error');
//       if (!handled) {
//         handled = true;
//         _handleAssignmentRejection(orderId, triedRiders, branchId);
//       }
//     });
//
//     _activeSubscriptions[orderId] = subscription;
//
//     final timer = Timer(Duration(seconds: timeoutSeconds), () async {
//       if (!handled) {
//         handled = true;
//         _cancelExistingSubscription(orderId);
//
//         print('⏰ 2-MINUTE TIMEOUT: Rider $riderId did not respond to order $orderId');
//
//         try {
//           await assignmentDoc.update({'status': 'timeout'});
//         } catch (e) {
//           print('⚠️ Could not update assignment status to timeout: $e');
//         }
//
//         await _handleAssignmentRejection(orderId, triedRiders, branchId);
//       }
//     });
//     _activeTimers[orderId] = timer;
//   }
//
//   // Handle assignment rejection and try next rider
//   static Future<void> _handleAssignmentRejection(String orderId, Set<String> previousTriedRiders, String branchId) async {
//     print('🔄 HANDLING REJECTION: Order $orderId, Branch $branchId, Previous tried riders: $previousTriedRiders');
//
//     try {
//       await _cleanupAssignment(orderId).timeout(const Duration(seconds: 3), onTimeout: () {
//         print('⚠️ Cleanup timeout, continuing with next rider assignment');
//       });
//
//       final orderSnap = await _firestore.collection('Orders').doc(orderId).get();
//       final data = orderSnap.data() as Map<String, dynamic>? ?? {};
//       final currentStatus = (data['status'] as String?) ?? '';
//       final currentRider = (data['riderId'] as String?) ?? '';
//
//       if ((currentStatus != 'preparing' && currentStatus != 'prepared') || currentRider.isNotEmpty) {
//         print('⚠️ ORDER NO LONGER NEEDS ASSIGNMENT: Order $orderId - Status: $currentStatus, Rider: $currentRider');
//         await _cleanupAssignment(orderId);
//         return;
//       }
//
//       final GeoPoint restaurantLocation = await _getRestaurantLocation(branchId)
//           .timeout(const Duration(seconds: 3), onTimeout: () {
//         print('⚠️ Restaurant location timeout, using default');
//         return const GeoPoint(25.2614, 51.5651);
//       });
//
//       final List<Map<String, dynamic>> nearestRiders = await _findNearestRiders(restaurantLocation, 15, branchId)
//           .timeout(const Duration(seconds: 5), onTimeout: () {
//         print('⚠️ Rider search timeout, returning empty list');
//         return [];
//       });
//
//       if (nearestRiders.isEmpty) {
//         print('❌ NO AVAILABLE RIDERS: No riders found for order $orderId after rejection');
//         await _markOrderAsNeedsManualAssignment(orderId, 'No available riders found');
//         return;
//       }
//
//       String? nextRiderId;
//       double? nextDistance;
//       String? nextRiderName;
//
//       for (final rider in nearestRiders) {
//         final riderId = rider['riderId'] as String;
//         if (!previousTriedRiders.contains(riderId)) {
//           nextRiderId = riderId;
//           nextDistance = rider['distance'] as double;
//           nextRiderName = (rider['data'] as Map<String, dynamic>)['name'] ?? 'Unknown';
//           break;
//         }
//       }
//
//       if (nextRiderId != null) {
//         print('🎯 IMMEDIATELY ASSIGNING TO NEXT RIDER: $nextRiderName ($nextRiderId) - ${nextDistance!.toStringAsFixed(2)} km away');
//
//         final requestSent = await _sendAssignmentRequest(
//           orderId: orderId,
//           riderId: nextRiderId,
//           timeoutSeconds: 120,
//           triedRiders: previousTriedRiders,
//           branchId: branchId,
//         );
//
//         if (requestSent) {
//           print('✅ NEXT RIDER ASSIGNMENT STARTED: Rider $nextRiderName notified immediately');
//           return;
//         } else {
//           print('❌ FAILED TO SEND TO NEXT RIDER: $nextRiderId, trying next available...');
//           await Future.delayed(const Duration(milliseconds: 100));
//           await _handleAssignmentRejection(orderId, previousTriedRiders, branchId);
//           return;
//         }
//       }
//
//       print('❌ ALL RIDERS EXHAUSTED: All ${nearestRiders.length} available riders have been tried for order $orderId');
//       await _markOrderAsNeedsManualAssignment(orderId, 'All ${nearestRiders.length} available riders failed to accept the assignment');
//
//     } catch (e) {
//       print('❌ ERROR in rejection handler: $e');
//       await _cleanupAssignment(orderId);
//     }
//   }
//
//   // Complete the assignment when rider accepts
//   static Future<void> _completeAssignment(String orderId, String riderId) async {
//     try {
//       final orderDoc = await _firestore.collection('Orders').doc(orderId).get();
//       final orderData = orderDoc.data() as Map<String, dynamic>? ?? {};
//       final currentStatus = orderData['status'] as String? ?? '';
//       final currentRider = orderData['riderId'] as String? ?? '';
//
//       if ((currentStatus != 'preparing' && currentStatus != 'prepared') || currentRider.isNotEmpty) {
//         print('⚠️ ORDER ALREADY ASSIGNED: Order $orderId - Status: $currentStatus, Rider: $currentRider');
//         await _cleanupAssignment(orderId);
//         return;
//       }
//
//       final batch = _firestore.batch();
//
//       final orderRef = _firestore.collection('Orders').doc(orderId);
//       batch.update(orderRef, {
//         'riderId': riderId,
//         'status': 'rider_assigned',
//         'timestamps.riderAssigned': FieldValue.serverTimestamp(),
//         'autoAssignStarted': FieldValue.delete(),
//         'assignmentNotes': FieldValue.delete(),
//         'lastAssignmentUpdate': FieldValue.serverTimestamp(),
//       });
//
//       final riderRef = _firestore.collection('Drivers').doc(riderId);
//       batch.update(riderRef, {
//         'assignedOrderId': orderId,
//         'isAvailable': false,
//       });
//
//       await batch.commit();
//       await _cleanupAssignment(orderId);
//       _cancelExistingSubscription(orderId);
//
//       print('🎉 ASSIGNMENT COMPLETED: Rider $riderId successfully assigned to order $orderId');
//
//     } catch (e) {
//       print('❌ ERROR completing assignment: $e');
//       await _markOrderAsNeedsManualAssignment(orderId, 'Assignment completion failed: $e');
//     }
//   }
//
//   // ========== NOTIFICATION METHODS ==========
//
//   // Unified notification method for both auto and manual assignments
// // Unified notification method for both auto and manual assignments
//   static Future<void> _sendRiderAssignmentNotification({
//     required String fcmToken,
//     required String orderId,
//     required String riderName,
//     required Map<String, dynamic> orderData,
//     required bool isManualAssignment,
//   }) async {
//     try {
//       final String orderNumber = orderData['dailyOrderNumber']?.toString() ?? orderId.substring(0, 6).toUpperCase();
//       final double totalAmount = (orderData['totalAmount'] as num?)?.toDouble() ?? 0.0;
//       final String customerName = orderData['customerName'] ?? 'Customer';
//       final String orderType = orderData['Order_type'] ?? 'delivery';
//       final String deliveryAddress = orderData['deliveryAddress']?['street'] ?? '';
//
//       String formatOrderType(String type) {
//         switch (type) {
//           case 'delivery': return 'Delivery';
//           case 'takeaway': return 'Takeaway';
//           case 'pickup': return 'Pickup';
//           case 'dine_in': return 'Dine-in';
//           default: return 'Order';
//         }
//       }
//
//       final String title = isManualAssignment ? '🎯 Order Assigned' : '📦 New Order Available';
//       final String body = isManualAssignment
//           ? 'You have been assigned to Order #$orderNumber'
//           : 'New ${formatOrderType(orderType)} Order - QAR ${totalAmount.toStringAsFixed(2)}';
//
//       // For older Firebase Messaging versions, use HTTP API directly
//       final Map<String, dynamic> notificationPayload = {
//         'message': {
//           'token': fcmToken,
//           'notification': {
//             'title': title,
//             'body': body,
//           },
//           'data': {
//             'type': isManualAssignment ? 'manual_assignment' : 'auto_assignment',
//             'orderId': orderId,
//             'orderNumber': orderNumber,
//             'riderId': riderName,
//             'totalAmount': totalAmount.toString(),
//             'customerName': customerName,
//             'orderType': orderType,
//             'deliveryAddress': deliveryAddress,
//             'isManualAssignment': isManualAssignment.toString(),
//             'click_action': 'FLUTTER_NOTIFICATION_CLICK',
//           },
//           'android': {
//             'priority': 'high',
//             'notification': {
//               'channel_id': 'order_assignments',
//               'sound': 'default',
//             },
//           },
//           'apns': {
//             'payload': {
//               'aps': {
//                 'contentAvailable': true,
//                 'badge': 1,
//                 'sound': 'default',
//                 'priority': 5,
//               },
//             },
//           },
//         }
//       };
//
//       // Send using the new API
//       await FirebaseMessaging.instance.sendMessage(
//         data: notificationPayload['message']['data'],
//         // For newer versions, you might need to set notification separately
//       );
//
//       print('📱 ${isManualAssignment ? 'MANUAL' : 'AUTO'} ASSIGNMENT NOTIFICATION SENT: To rider $riderName for order $orderId');
//
//       // Log the notification
//       await _firestore.collection('notifications').add({
//         'type': isManualAssignment ? 'manual_assignment' : 'auto_assignment',
//         'riderId': riderName,
//         'orderId': orderId,
//         'orderNumber': orderNumber,
//         'fcmToken': fcmToken,
//         'sentAt': FieldValue.serverTimestamp(),
//         'status': 'sent',
//         'title': title,
//         'body': body,
//       });
//
//     } catch (e) {
//       print('❌ FCM NOTIFICATION ERROR: Failed to send ${isManualAssignment ? 'manual' : 'auto'} assignment notification: $e');
//
//       await _firestore.collection('notification_errors').add({
//         'type': isManualAssignment ? 'manual_assignment' : 'auto_assignment',
//         'orderId': orderId,
//         'riderId': riderName,
//         'error': e.toString(),
//         'timestamp': FieldValue.serverTimestamp(),
//       });
//     }
//   }
//
//   // ========== MAIN ASSIGNMENT METHODS ==========
//
//   // Auto assign rider to order
//   static Future<bool> autoAssignRider({
//     required String orderId,
//     required String branchId,
//   }) async {
//     print('🚀 STARTING AUTO-ASSIGNMENT PROCESS FOR ORDER: $orderId, BRANCH: $branchId');
//
//     try {
//       final orderDoc = await _firestore.collection('Orders').doc(orderId).get();
//       final orderData = orderDoc.data() as Map<String, dynamic>?;
//
//       if (orderData == null) {
//         print('❌ ORDER VALIDATION FAILED: Order $orderId not found in database');
//         return false;
//       }
//
//       final currentStatus = orderData['status'] as String? ?? '';
//       final validStatuses = ['preparing', 'prepared'];
//       if (!validStatuses.contains(currentStatus)) {
//         print('❌ ORDER VALIDATION FAILED: Order $orderId is not ready for rider assignment. Current status: "$currentStatus". Required status: ${validStatuses.join(" or ")}');
//         return false;
//       }
//
//       final currentRider = orderData['riderId'] as String? ?? '';
//       if (currentRider.isNotEmpty) {
//         print('❌ ORDER VALIDATION FAILED: Order $orderId already has a rider assigned: $currentRider');
//         return false;
//       }
//
//       final isAutoAssigning = orderData.containsKey('autoAssignStarted');
//       if (isAutoAssigning) {
//         print('⚠️ AUTO-ASSIGNMENT ALREADY IN PROGRESS: Auto-assignment already running for order $orderId');
//
//         final autoAssignStarted = orderData['autoAssignStarted'] as Timestamp?;
//         if (autoAssignStarted != null) {
//           final difference = DateTime.now().difference(autoAssignStarted.toDate()).inMinutes;
//
//           if (difference > 10) {
//             print('🕒 CLEANING STUCK ASSIGNMENT: Auto-assignment has been running for $difference minutes, cleaning up...');
//             await _firestore.collection('Orders').doc(orderId).update({
//               'autoAssignStarted': FieldValue.delete(),
//               'assignmentNotes': 'Auto-assignment timed out after $difference minutes',
//             });
//             await _cleanupAssignment(orderId);
//           } else {
//             print('⏳ AUTO-ASSIGNMENT IN PROGRESS: Running for $difference minutes, waiting...');
//             return true;
//           }
//         }
//       }
//
//       final Set<String> triedRiders = await _getTriedRiders(orderId);
//       if (triedRiders.isNotEmpty) {
//         print('📝 PREVIOUS ATTEMPTS: Found ${triedRiders.length} previously tried riders: $triedRiders');
//       }
//
//       await _firestore.collection('Orders').doc(orderId).update({
//         'autoAssignStarted': FieldValue.serverTimestamp(),
//         'lastAssignmentAttempt': FieldValue.serverTimestamp(),
//       });
//
//       print('✅ AUTO-ASSIGNMENT INITIATED: Marked order $orderId for auto-assignment');
//
//       final GeoPoint restaurantLocation = await _getRestaurantLocation(branchId)
//           .timeout(const Duration(seconds: 5), onTimeout: () {
//         print('⚠️ Restaurant location timeout, using default location');
//         return const GeoPoint(25.2614, 51.5651);
//       });
//
//       print('📍 RESTAURANT LOCATION: Lat: ${restaurantLocation.latitude}, Lng: ${restaurantLocation.longitude}');
//
//       final List<Map<String, dynamic>> nearestRiders = await _findNearestRiders(restaurantLocation, 15, branchId)
//           .timeout(const Duration(seconds: 10), onTimeout: () {
//         print('⚠️ Rider search timeout, returning empty list');
//         return [];
//       });
//
//       print('👥 RIDER SEARCH: Found ${nearestRiders.length} total available riders for branch $branchId');
//
//       if (nearestRiders.isEmpty) {
//         print('❌ NO RIDERS AVAILABLE: No available riders found for order $orderId');
//         await _markOrderAsNeedsManualAssignment(orderId, 'No available riders found for automatic assignment');
//         return false;
//       }
//
//       final availableRiders = nearestRiders.where((rider) {
//         final riderId = rider['riderId'] as String;
//         return !triedRiders.contains(riderId);
//       }).toList();
//
//       print('🎯 FILTERED RIDERS: ${availableRiders.length} available riders after filtering out ${triedRiders.length} tried riders');
//
//       if (availableRiders.isEmpty) {
//         print('❌ ALL RIDERS TRIED: All ${nearestRiders.length} available riders have already been tried');
//         await _markOrderAsNeedsManualAssignment(orderId, 'All ${nearestRiders.length} available riders failed to accept the assignment');
//         return false;
//       }
//
//       print('📊 AVAILABLE RIDERS DETAILS:');
//       for (int i = 0; i < availableRiders.length; i++) {
//         final rider = availableRiders[i];
//         final riderId = rider['riderId'] as String;
//         final distance = rider['distance'] as double;
//         final riderData = rider['data'] as Map<String, dynamic>;
//         final riderName = riderData['name'] ?? 'Unknown';
//         final riderPhone = riderData['phone'] ?? 'No phone';
//
//         print('   ${i + 1}. $riderName ($riderId)');
//         print('     📱 $riderPhone | 📍 ${distance.toStringAsFixed(2)} km away');
//       }
//
//       final closestRider = availableRiders.first;
//       final riderId = closestRider['riderId'] as String;
//       final riderName = (closestRider['data'] as Map<String, dynamic>)['name'] ?? 'Unknown';
//       final distance = closestRider['distance'] as double;
//
//       print('🎯 ATTEMPTING ASSIGNMENT: Trying closest rider $riderName ($riderId) - ${distance.toStringAsFixed(2)} km away');
//
//       final requestSent = await _sendAssignmentRequest(
//         orderId: orderId,
//         riderId: riderId,
//         timeoutSeconds: 120,
//         triedRiders: triedRiders,
//         branchId: branchId,
//       );
//
//       if (requestSent) {
//         print('✅ ASSIGNMENT INITIATED: Successfully sent assignment request to rider $riderName');
//         print('⏰ TIMEOUT SET: 2 minutes (120 seconds) for rider response');
//         return true;
//       } else {
//         print('❌ ASSIGNMENT FAILED: Failed to send assignment request to $riderName');
//         await _markOrderAsNeedsManualAssignment(orderId, 'Failed to send assignment request to riders');
//         return false;
//       }
//
//     } catch (e, stackTrace) {
//       print('❌ CRITICAL ERROR in autoAssignRider: $e');
//       print('📋 Stack trace: $stackTrace');
//
//       try {
//         await _firestore.collection('Orders').doc(orderId).update({
//           'autoAssignStarted': FieldValue.delete(),
//           'assignmentNotes': 'Auto-assignment failed with error: $e',
//         });
//         await _cleanupAssignment(orderId);
//       } catch (cleanupError) {
//         print('❌ ERROR during emergency cleanup: $cleanupError');
//       }
//
//       return false;
//     }
//   }
//
//   // Manual rider assignment fallback with notification
//   static Future<bool> manualAssignRider({
//     required String orderId,
//     required String riderId,
//     required BuildContext context,
//   }) async {
//     try {
//       _cancelExistingSubscription(orderId);
//       await _cleanupAssignment(orderId);
//
//       // Get order details for the notification
//       final orderDoc = await _firestore.collection('Orders').doc(orderId).get();
//       final orderData = orderDoc.data() as Map<String, dynamic>? ?? {};
//
//       // Get rider details for FCM token
//       final riderDoc = await _firestore.collection('Drivers').doc(riderId).get();
//       final riderData = riderDoc.data() as Map<String, dynamic>? ?? {};
//       final String? riderFcmToken = riderData['fcmToken'];
//       final String riderName = riderData['name'] ?? 'Rider';
//
//       // Update order with rider assignment
//       await _firestore.collection('Orders').doc(orderId).update({
//         'riderId': riderId,
//         'status': 'rider_assigned',
//         'timestamps.riderAssigned': FieldValue.serverTimestamp(),
//         'assignmentNotes': 'Manually assigned by admin',
//         'autoAssignStarted': FieldValue.delete(),
//         'lastAssignmentUpdate': FieldValue.serverTimestamp(),
//       });
//
//       // Update rider status
//       await _firestore.collection('Drivers').doc(riderId).update({
//         'assignedOrderId': orderId,
//         'isAvailable': false,
//       });
//
//       // Send notification to rider
//       if (riderFcmToken != null && riderFcmToken.isNotEmpty) {
//         await _sendRiderAssignmentNotification(
//           fcmToken: riderFcmToken,
//           orderId: orderId,
//           riderName: riderName,
//           orderData: orderData,
//           isManualAssignment: true,
//         );
//       } else {
//         print('⚠️ No FCM token found for rider $riderId, notification not sent');
//       }
//
//       if (context.mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Rider $riderName assigned successfully to order $orderId'),
//             backgroundColor: Colors.green,
//           ),
//         );
//       }
//
//       print('✅ MANUAL ASSIGNMENT SUCCESSFUL: Rider $riderId assigned to order $orderId');
//       return true;
//     } catch (e) {
//       if (context.mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Failed to assign rider: $e'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//       print('❌ MANUAL ASSIGNMENT FAILED: $e');
//       return false;
//     }
//   }
//
//   // ========== HELPER METHODS ==========
//
//   // Helper method to mark order as needing manual assignment
//   static Future<void> _markOrderAsNeedsManualAssignment(String orderId, String reason) async {
//     print('📋 MARKING FOR MANUAL ASSIGNMENT: $reason');
//
//     try {
//       await _firestore.collection('Orders').doc(orderId).update({
//         'status': 'needs_rider_assignment',
//         'assignmentNotes': reason,
//         'needsAssignmentAt': FieldValue.serverTimestamp(),
//         'autoAssignStarted': FieldValue.delete(),
//         'lastAssignmentUpdate': FieldValue.serverTimestamp(),
//       });
//
//       await _cleanupAssignment(orderId);
//       _cancelExistingSubscription(orderId);
//
//       print('✅ SUCCESS: Order $orderId marked for manual assignment');
//     } catch (e) {
//       print('❌ ERROR marking for manual assignment: $e');
//     }
//   }
//
//   // Cancel existing subscription and timer for an order
//   static void _cancelExistingSubscription(String orderId) {
//     if (_activeSubscriptions.containsKey(orderId)) {
//       _activeSubscriptions[orderId]?.cancel();
//       _activeSubscriptions.remove(orderId);
//       print('🔇 CANCELLED SUBSCRIPTION for order $orderId');
//     }
//
//     if (_activeTimers.containsKey(orderId)) {
//       _activeTimers[orderId]?.cancel();
//       _activeTimers.remove(orderId);
//       print('⏹️ CANCELLED TIMER for order $orderId');
//     }
//   }
//
//   static Future<void> _cleanupAssignment(String orderId) async {
//     try {
//       await Future.any([
//         _performCleanup(orderId),
//         Future.delayed(const Duration(seconds: 3)).then((_) {
//           throw TimeoutException('Cleanup timeout for order $orderId');
//         })
//       ]);
//     } on TimeoutException {
//       print('⚠️ Cleanup timeout for order $orderId, continuing...');
//     } catch (e) {
//       print('❌ ERROR during cleanup: $e');
//     }
//   }
//
//   static Future<void> _performCleanup(String orderId) async {
//     await _firestore.collection('rider_assignments').doc(orderId).delete();
//     _cancelExistingSubscription(orderId);
//     print('🧹 CLEANUP: Removed assignment documents for order $orderId');
//   }
//
//   static Future<Set<String>> _getTriedRiders(String orderId) async {
//     try {
//       final assignmentDoc = await _firestore.collection('rider_assignments').doc(orderId).get();
//       if (assignmentDoc.exists) {
//         final data = assignmentDoc.data() as Map<String, dynamic>?;
//         final triedRiders = data?['triedRiders'] as List<dynamic>?;
//         return triedRiders?.map((rider) => rider.toString()).toSet() ?? <String>{};
//       }
//     } catch (e) {
//       print('❌ ERROR getting tried riders: $e');
//     }
//     return <String>{};
//   }
//
//   // ========== PUBLIC METHODS ==========
//
//   static Stream<QuerySnapshot> getOrdersNeedingAssignment() {
//     return _firestore
//         .collection('Orders')
//         .where('status', isEqualTo: 'needs_rider_assignment')
//         .snapshots();
//   }
//
//   static Future<void> cancelAutoAssignment(String orderId) async {
//     try {
//       await _firestore.collection('Orders').doc(orderId).update({
//         'autoAssignStarted': FieldValue.delete(),
//       });
//       await _cleanupAssignment(orderId);
//       _cancelExistingSubscription(orderId);
//       print('🛑 AUTO-ASSIGNMENT CANCELLED: Order $orderId');
//     } catch (e) {
//       print('❌ ERROR cancelling auto-assignment: $e');
//     }
//   }
//
//   static Future<bool> isAutoAssigning(String orderId) async {
//     try {
//       final orderDoc = await _firestore.collection('Orders').doc(orderId).get();
//       final orderData = orderDoc.data() as Map<String, dynamic>?;
//       return orderData != null && orderData.containsKey('autoAssignStarted');
//     } catch (e) {
//       print('❌ ERROR checking auto-assignment status: $e');
//       return false;
//     }
//   }
//
//   static void dispose() {
//     _activeSubscriptions.forEach((orderId, subscription) {
//       subscription.cancel();
//     });
//     _activeSubscriptions.clear();
//     _activeTimers.forEach((orderId, timer) {
//       timer.cancel();
//     });
//     _activeTimers.clear();
//     print('🧹 DISPOSED: All active subscriptions and timers cleared');
//   }
//
//   static Future<void> debugAssignmentState(String orderId) async {
//     try {
//       print('🔍 DEBUG: Checking assignment state for order $orderId');
//
//       final orderDoc = await _firestore.collection('Orders').doc(orderId).get();
//       final orderData = orderDoc.data() as Map<String, dynamic>? ?? {};
//       print('📋 Order status: ${orderData['status']}, Rider: ${orderData['riderId']}, AutoAssign: ${orderData.containsKey('autoAssignStarted')}');
//
//       final assignmentDoc = await _firestore.collection('rider_assignments').doc(orderId).get();
//       if (assignmentDoc.exists) {
//         final assignmentData = assignmentDoc.data() as Map<String, dynamic>? ?? {};
//         print('📋 Assignment - Rider: ${assignmentData['riderId']}, Status: ${assignmentData['status']}, Tried: ${assignmentData['triedRiders']}');
//       } else {
//         print('📋 No assignment document found');
//       }
//
//     } catch (e) {
//       print('❌ Debug error: $e');
//     }
//   }
// }


import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

// --- MODIFICATION ---
// This service is no longer responsible for auto-assignment.
// All logic (finding riders, timeouts, retries, completion)
// has been moved to your Firebase Cloud Functions (index.js).
//
// We have removed the following methods:
// - autoAssignRider
// - _findNearestRiders
// - _getRestaurantLocation
// - _calculateDistance
// - _sendAssignmentRequest
// - _startAssignmentTimeout
// - _handleAssignmentRejection
// - _completeAssignment
//
// This file is now much simpler. Its only remaining purpose
// might be for other utility functions (like _showErrorDialog)
// or for manual assignment if you choose to centralize that logic here
// (though ManualAssignmentScreen.dart already handles it).
// --- END MODIFICATION ---

class RiderAssignmentService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Utility function to show an error. This may or may not be used
  // elsewhere, so we will leave it just in case.
  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('An Error Occurred'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            child: Text('Okay'),
            onPressed: () {
              Navigator.of(ctx).pop();
            },
          )
        ],
      ),
    );
  }
}