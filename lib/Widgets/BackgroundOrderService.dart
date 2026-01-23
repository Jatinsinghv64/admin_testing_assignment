// import 'dart:async';
// import 'package:flutter/cupertino.dart';
// import 'package:flutter_background_service/flutter_background_service.dart';
// import 'package:flutter_background_service_android/flutter_background_service_android.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:audioplayers/audioplayers.dart';
// import 'package:vibration/vibration.dart';
// import 'package:firebase_core/firebase_core.dart';
// import '../firebase_options.dart';
//
// @pragma('vm:entry-point')
// class BackgroundOrderService {
//   static const String _channelId = 'order_background_service';
//   static const String _channelName = 'Order Listener Service';
//   static const String _channelDesc = 'Maintains the restaurant state';
//   static const String _orderChannelId = 'high_importance_channel';
//   static const String _orderChannelName = 'New Order Notifications';
//   static const String _orderChannelDesc = 'This channel is used for important order notifications.';
//
//   @pragma('vm:entry-point')
//   static Future<void> initializeService() async {
//     final service = FlutterBackgroundService();
//
//     // Create the Notification Channel for the Foreground Service itself
//     const AndroidNotificationChannel channel = AndroidNotificationChannel(
//       _channelId,
//       _channelName,
//       description: _channelDesc,
//       importance: Importance.low, // Silent for the "Service Running" notification
//     );
//
//     final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
//     FlutterLocalNotificationsPlugin();
//
//     await flutterLocalNotificationsPlugin
//         .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
//         ?.createNotificationChannel(channel);
//
//     await service.configure(
//       androidConfiguration: AndroidConfiguration(
//         onStart: onStart,
//         autoStart: false, // We start it manually in main.dart
//         isForegroundMode: true,
//         notificationChannelId: _channelId,
//         initialNotificationTitle: 'Restaurant Service',
//         initialNotificationContent: 'Monitoring orders...',
//         foregroundServiceNotificationId: 888,
//       ),
//       iosConfiguration: IosConfiguration(
//         autoStart: false,
//         onForeground: onStart,
//         onBackground: onIosBackground,
//       ),
//     );
//   }
//
//   @pragma('vm:entry-point')
//   static Future<bool> onIosBackground(ServiceInstance service) async {
//     return true;
//   }
//
//   @pragma('vm:entry-point')
//   static Future<void> onStart(ServiceInstance service) async {
//     // 1. Initialize Firebase
//     if (Firebase.apps.isEmpty) {
//       await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
//     }
//
//     final FirebaseFirestore db = FirebaseFirestore.instance;
//     final AudioPlayer audioPlayer = AudioPlayer();
//     final Set<String> processedOrderIds = {};
//     StreamSubscription? orderListener;
//     bool isAppInForeground = true;
//
//     // 2. Initialize Local Notifications (For alerting)
//     final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
//     await localNotifications.initialize(
//       const InitializationSettings(
//         android: AndroidInitializationSettings('@mipmap/ic_launcher'),
//         iOS: DarwinInitializationSettings(),
//       ),
//     );
//
//     // Create the High Importance Channel
//     const AndroidNotificationChannel orderChannel = AndroidNotificationChannel(
//       _orderChannelId,
//       _orderChannelName,
//       description: _orderChannelDesc,
//       importance: Importance.max,
//       playSound: true,
//       enableVibration: true,
//     );
//
//     await localNotifications
//         .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
//         ?.createNotificationChannel(orderChannel);
//
//     // 3. Listen for UI Lifecycle Events
//     service.on('appInForeground').listen((_) => isAppInForeground = true);
//     service.on('appInBackground').listen((_) => isAppInForeground = false);
//
//     // 4. Main Branch Listener Logic
//     service.on('updateBranchIds').listen((event) async {
//       if (event is Map<String, dynamic>) {
//         final List<String> branchIds = List<String>.from(event['branchIds'] ?? []);
//
//         // Reset Listener
//         orderListener?.cancel();
//         orderListener = null;
//         processedOrderIds.clear();
//
//         if (branchIds.isEmpty) {
//           service.invoke('updateNotification', {'title': 'Restaurant Closed', 'content': 'Idle'});
//           return;
//         }
//
//         service.invoke('updateNotification', {
//           'title': 'Restaurant Open',
//           'content': 'Monitoring ${branchIds.length} branches'
//         });
//
//         final query = db
//             .collection('Orders')
//             .where('status', isEqualTo: 'pending')
//             .where('branchIds', arrayContainsAny: branchIds);
//
//         orderListener = query.snapshots().listen((snapshot) async {
//           for (var doc in snapshot.docs) {
//             final orderId = doc.id;
//
//             // Only process new orders we haven't seen in this session
//             if (!processedOrderIds.contains(orderId)) {
//               processedOrderIds.add(orderId);
//               debugPrint('🎯 Service: New Order detected: $orderId');
//
//               // A. If App Background: Show Notification & Play Sound
//               if (!isAppInForeground) {
//                 await _showOrderNotification(doc, localNotifications);
//                 await _playNotificationSound(audioPlayer);
//                 await _vibrate();
//               }
//
//               // B. Always Invoke UI (In case app is open)
//               final data = doc.data();
//               data['orderId'] = orderId;
//               service.invoke('new_order', _sanitizeDataForInvoke(data));
//             }
//           }
//         });
//       }
//     });
//
//     service.invoke('updateBranchIds', {'branchIds': []});
//   }
//
//   static Future<void> _showOrderNotification(
//       QueryDocumentSnapshot doc, FlutterLocalNotificationsPlugin plugin) async {
//     try {
//       final data = doc.data() as Map<String, dynamic>;
//       final orderNumber = data['dailyOrderNumber']?.toString() ?? doc.id.substring(0, 6).toUpperCase();
//       final customerName = data['customerName'] ?? 'Guest';
//
//       const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
//         _orderChannelId,
//         _orderChannelName,
//         channelDescription: _orderChannelDesc,
//         importance: Importance.max,
//         priority: Priority.high,
//         fullScreenIntent: true,
//         color: Color(0xFF673AB7),
//       );
//
//       // ✅ CRITICAL FIX: Use Stable ID
//       final int notificationId = getStableId(doc.id);
//
//       await plugin.show(
//         notificationId,
//         'New Order #$orderNumber',
//         'From: $customerName',
//         const NotificationDetails(android: androidDetails),
//       );
//     } catch (e) {
//       debugPrint('❌ Notification Error: $e');
//     }
//   }
//
//   static Future<void> _playNotificationSound(AudioPlayer player) async {
//     try {
//       await player.setReleaseMode(ReleaseMode.loop);
//       await player.play(AssetSource('notification.mp3'));
//       Future.delayed(const Duration(seconds: 10), () {
//         player.stop();
//         player.setReleaseMode(ReleaseMode.release);
//       });
//     } catch (e) {
//       debugPrint('❌ Sound Error: $e');
//     }
//   }
//
//   static Future<void> _vibrate() async {
//     if (await Vibration.hasVibrator() ?? false) {
//       Vibration.vibrate(pattern: [500, 1000, 500, 1000]);
//     }
//   }
//
//   static Map<String, dynamic> _sanitizeDataForInvoke(Map<String, dynamic> data) {
//     final sanitizedMap = <String, dynamic>{};
//
//     data.forEach((key, value) {
//       if (value is Timestamp) {
//         sanitizedMap[key] = value.millisecondsSinceEpoch;
//       } else if (value is GeoPoint) {
//         sanitizedMap[key] = {'latitude': value.latitude, 'longitude': value.longitude};
//       } else if (value is Map) {
//         sanitizedMap[key] = _sanitizeDataForInvoke(value as Map<String, dynamic>);
//       } else if (value is List) {
//         sanitizedMap[key] = value.map((item) {
//           if (item is Timestamp) return item.millisecondsSinceEpoch;
//           if (item is GeoPoint) return {'latitude': item.latitude, 'longitude': item.longitude};
//           return item.toString();
//         }).toList();
//       } else {
//         sanitizedMap[key] = value;
//       }
//     });
//     return sanitizedMap;
//   }
//
//   static Future<void> startService() async {
//     await FlutterBackgroundService().startService();
//   }
//
//   static Future<void> updateListener(List<String> branchIds) async {
//     FlutterBackgroundService().invoke('updateBranchIds', {'branchIds': branchIds});
//   }
//
//   static Future<bool> isServiceRunning() async {
//     try {
//       final service = FlutterBackgroundService();
//       return await service.isRunning();
//     } catch (e) {
//       return false;
//     }
//   }
//
//   // ✅ HELPER: Duplicated here to be accessible within the Isolate
//   static int getStableId(String id) {
//     int hash = 5381;
//     for (int i = 0; i < id.length; i++) {
//       hash = ((hash << 5) + hash) + id.codeUnitAt(i);
//     }
//     return hash & 0x7FFFFFFF;
//   }
// }