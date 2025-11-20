import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

@pragma('vm:entry-point')
class BackgroundOrderService {
  static const String _channelId = 'order_background_service';
  static const String _channelName = 'Order Listener Service';
  static const String _channelDesc = 'Maintains the restaurant state';
  static const String _orderChannelId = 'high_importance_channel';
  static const String _orderChannelName = 'New Order Notifications';
  static const String _orderChannelDesc = 'This channel is used for important order notifications.';

  @pragma('vm:entry-point')
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.low,
    );
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _channelId,
        initialNotificationTitle: 'Restaurant Service',
        initialNotificationContent: 'Initializing...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  // Helper to make Firestore data safe for passing between isolates (invoking events)
  @pragma('vm:entry-point')
  static Map<String, dynamic> _sanitizeDataForInvoke(Map<String, dynamic> data) {
    final sanitizedMap = <String, dynamic>{};

    data.forEach((key, value) {
      if (value is Timestamp) {
        sanitizedMap[key] = value.millisecondsSinceEpoch;
      } else if (value is GeoPoint) {
        sanitizedMap[key] = {'latitude': value.latitude, 'longitude': value.longitude};
      } else if (value is Map) {
        sanitizedMap[key] = _sanitizeDataForInvoke(value as Map<String, dynamic>);
      } else if (value is List) {
        sanitizedMap[key] = value.map((item) {
          if (item is Map) {
            return _sanitizeDataForInvoke(item as Map<String, dynamic>);
          } else if (item is Timestamp) {
            return item.millisecondsSinceEpoch;
          } else if (item is GeoPoint) {
            return {'latitude': item.latitude, 'longitude': item.longitude};
          } else if (item is String || item is num || item is bool || item == null) {
            return item;
          }
          return item.toString();
        }).toList();
      } else if (value is String || value is num || value is bool || value == null) {
        sanitizedMap[key] = value;
      } else {
        sanitizedMap[key] = value.toString();
      }
    });
    return sanitizedMap;
  }

  @pragma('vm:entry-point')
  static Future<void> onStart(ServiceInstance service) async {
    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        debugPrint('✅ Background Service: Firebase initialized successfully');
      } catch (e) {
        debugPrint('❌ Background Service: Firebase initialization failed: $e');
        return;
      }
    }

    final FirebaseFirestore db = FirebaseFirestore.instance;
    final AudioPlayer audioPlayer = AudioPlayer();
    final Set<String> processedOrderIds = {};
    StreamSubscription? orderListener;

    // Tracks if the UI is visible. Defaults to true to avoid spamming on launch.
    bool isAppInForeground = true;

    final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
    await localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    const AndroidNotificationChannel orderChannel = AndroidNotificationChannel(
      _orderChannelId,
      _orderChannelName,
      description: _orderChannelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(orderChannel);

    // Listen for UI state changes
    service.on('appInForeground').listen((_) {
      isAppInForeground = true;
      debugPrint('✅ Background Service: App is FOREGROUND');
    });

    service.on('appInBackground').listen((_) {
      isAppInForeground = false;
      debugPrint('✅ Background Service: App is BACKGROUND');
    });

    // Listen for Branch ID updates to start monitoring
    service.on('updateBranchIds').listen((event) async {
      if (event is Map<String, dynamic>) {
        final List<String> branchIds = List<String>.from(event['branchIds'] ?? []);
        orderListener?.cancel();
        orderListener = null;
        processedOrderIds.clear();

        if (branchIds.isEmpty) {
          service.invoke('updateNotification', {
            'title': 'Restaurant Closed',
            'content': 'Service is idle.'
          });
          return;
        }

        service.invoke('updateNotification', {
          'title': 'Restaurant Open',
          'content': 'Monitoring orders for ${branchIds.join(', ')}'
        });

        try {
          // Monitor pending orders for specific branches
          final query = db
              .collection('Orders')
              .where('status', isEqualTo: 'pending')
              .where('branchIds', arrayContainsAny: branchIds);

          orderListener = query.snapshots().listen((snapshot) async {
            for (var change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final doc = change.doc;
                final orderId = doc.id;

                if (!processedOrderIds.contains(orderId)) {
                  processedOrderIds.add(orderId);
                  debugPrint('🎯 Background Service: New order detected: $orderId');

                  final data = doc.data();
                  if (data != null) {
                    // 1. If App is BACKGROUND, show System Notification
                    if (!isAppInForeground) {
                      debugPrint('App is background, showing local notification.');
                      await _showOrderNotification(doc, localNotifications);
                      await _playNotificationSound(audioPlayer);
                      await _vibrate();
                    } else {
                      // App is FOREGROUND: The UI dialog will handle sound/vibration
                      debugPrint('App is foreground, skipping local notification.');
                    }

                    // 2. ALWAYS Invoke event to UI (invokes OrderNotificationService listener)
                    data['orderId'] = orderId;
                    final sanitizedData = _sanitizeDataForInvoke(data);
                    service.invoke('new_order', sanitizedData);
                  }
                }
              } else if (change.type == DocumentChangeType.removed) {
                processedOrderIds.remove(change.doc.id);
              }
            }
          }, onError: (error) {
            debugPrint('❌ Background Service Listener Error: $error');
            orderListener = null;
          });
        } catch (e) {
          debugPrint('❌ Background Service Query Error: $e');
        }
      }
    });

    // Initial invoke to reset
    service.invoke('updateBranchIds', {'branchIds': []});
  }

  static Future<void> _showOrderNotification(
      DocumentSnapshot<Map<String, dynamic>> doc,
      FlutterLocalNotificationsPlugin plugin) async {
    try {
      final data = doc.data();
      if (data == null) return;

      final orderNumber = data['dailyOrderNumber']?.toString() ?? doc.id.substring(0, 6).toUpperCase();
      final customerName = data['customerName']?.toString() ?? 'N/A';

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        _orderChannelId,
        _orderChannelName,
        channelDescription: _orderChannelDesc,
        importance: Importance.max,
        priority: Priority.high,
        fullScreenIntent: true, // Important for immediate attention
        showWhen: true,
        playSound: true,
      );

      await plugin.show(
        doc.id.hashCode,
        'New Order #$orderNumber',
        'From: $customerName',
        const NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('❌ Background Service Notification Error: $e');
    }
  }

  static Future<void> _playNotificationSound(AudioPlayer audioPlayer) async {
    try {
      // Play sound in a loop for a few seconds
      await audioPlayer.setReleaseMode(ReleaseMode.loop);
      await audioPlayer.play(AssetSource('notification.mp3'));

      Future.delayed(const Duration(seconds: 5), () {
        audioPlayer.stop();
        audioPlayer.setReleaseMode(ReleaseMode.release);
      });
    } catch (e) {
      debugPrint('❌ Error playing sound: $e');
    }
  }

  static Future<void> _vibrate() async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(pattern: [500, 1000, 500, 1000]);
      }
    } catch (e) {
      debugPrint('❌ Vibration error: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<void> startService() async {
    final service = FlutterBackgroundService();
    if (!(await service.isRunning())) {
      await service.startService();
    }
    // Reset branches on start
    service.invoke('updateBranchIds', {'branchIds': []});
  }

  static Future<void> updateListener(List<String> branchIds) async {
    final service = FlutterBackgroundService();
    service.invoke('updateBranchIds', {'branchIds': branchIds});
  }

  // ✅ RESTORED: This method was missing
  static Future<bool> isServiceRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }
}