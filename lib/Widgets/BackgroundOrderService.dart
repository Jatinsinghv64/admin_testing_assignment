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
  static const String _orderChannelDesc =
      'This channel is used for important order notifications.';

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

  @pragma('vm:entry-point')
  static Map<String, dynamic> _sanitizeDataForInvoke(
      Map<String, dynamic> data) {
    final sanitizedMap = <String, dynamic>{};

    data.forEach((key, value) {
      if (value is Timestamp) {
        sanitizedMap[key] = value.millisecondsSinceEpoch;
      } else if (value is GeoPoint) {
        sanitizedMap[key] = {
          'latitude': value.latitude,
          'longitude': value.longitude,
        };
      } else if (value is Map) {
        sanitizedMap[key] =
            _sanitizeDataForInvoke(value as Map<String, dynamic>);
      } else if (value is List) {
        sanitizedMap[key] = value.map((item) {
          if (item is Map) {
            return _sanitizeDataForInvoke(item as Map<String, dynamic>);
          } else if (item is Timestamp) {
            return item.millisecondsSinceEpoch;
          } else if (item is GeoPoint) {
            return {'latitude': item.latitude, 'longitude': item.longitude};
          } else if (item is String ||
              item is num ||
              item is bool ||
              item == null) {
            return item;
          }
          return item.toString();
        }).toList();
      } else if (value is String ||
          value is num ||
          value is bool ||
          value == null) {
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

    bool isAppInForeground = true;

    final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();
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
    debugPrint('✅ Background Service: Local Notifications Initialized');

    service.on('appInForeground').listen((_) {
      isAppInForeground = true;
      debugPrint('✅ Background Service: App is FOREGROUND');
    });

    service.on('appInBackground').listen((_) {
      isAppInForeground = false;
      debugPrint('✅ Background Service: App is BACKGROUND');
    });

    service.on('updateBranchIds').listen((event) async {
      if (event is Map<String, dynamic>) {
        final List<String> branchIds =
        List<String>.from(event['branchIds'] ?? []);
        orderListener?.cancel();
        orderListener = null;
        processedOrderIds.clear();
        if (branchIds.isEmpty) {
          debugPrint(
              '🛑 Background Service: Branch list is empty. Listener stopped.');
          service.invoke('updateNotification', {
            'title': 'Restaurant Closed',
            'content': 'Service is idle. Tap to open app.'
          });
          return;
        }
        debugPrint(
            '🎯 Background Service: Starting listener for branches: $branchIds');
        service.invoke('updateNotification', {
          'title': 'Restaurant Open',
          'content': 'Monitoring orders for ${branchIds.join(', ')}'
        });

        try {
          final query = db
              .collection('Orders')
              .where('status', isEqualTo: 'pending')
              .where('branchIds', arrayContainsAny: branchIds);

          orderListener = query.snapshots().listen((snapshot) async {
            service.invoke('updateNotification', {
              'title': 'Restaurant Open',
              'content': 'Monitoring orders for ${branchIds.join(', ')}'
            });

            for (var change in snapshot.docChanges) {
              final doc = change.doc;
              final orderId = doc.id;

              if (change.type == DocumentChangeType.added) {
                if (!processedOrderIds.contains(orderId)) {
                  processedOrderIds.add(orderId);
                  debugPrint(
                      '🎯 Background Service: New order detected: $orderId');

                  if (!isAppInForeground) {
                    debugPrint('App is background, showing local notification.');
                    await _showOrderNotification(doc, localNotifications);
                    await _playNotificationSound(audioPlayer);
                    await _vibrate();
                  } else {
                    debugPrint(
                        'App is foreground, skipping local notification.');
                  }

                  final data = doc.data();
                  // doc.data() for DocumentSnapshot returns T?, so we check for null
                  if (data != null) {
                    data['orderId'] = orderId;
                    data['id'] = orderId;
                    final sanitizedData = _sanitizeDataForInvoke(data);
                    service.invoke('new_order', sanitizedData);
                  }
                }
              } else if (change.type == DocumentChangeType.removed) {
                processedOrderIds.remove(orderId);
              }
            }
          }, onError: (error) {
            debugPrint('❌❌❌ Background Service: LISTENER FAILED: $error');
            service.invoke('updateNotification', {
              'title': 'LISTENER FAILED',
              'content': 'Tap to open app and restart.'
            });
            orderListener = null;
          });
        } catch (e) {
          debugPrint('❌ Background Service: Firestore query setup error: $e');
          service.invoke('updateNotification', {
            'title': 'LISTENER FAILED',
            'content': 'Query error. Tap to open app.'
          });
        }
      }
    });

    service.invoke('updateBranchIds', {'branchIds': []});
  }

  // ✅ FIXED: Changed parameter to DocumentSnapshot to accept both types
  static Future<void> _showOrderNotification(
      DocumentSnapshot<Map<String, dynamic>> doc,
      FlutterLocalNotificationsPlugin plugin) async {
    try {
      final data = doc.data();

      // ✅ FIXED: Added null check because DocumentSnapshot data can technically be null
      if (data == null) return;

      final orderNumber = data['dailyOrderNumber']?.toString() ??
          doc.id.substring(0, 6).toUpperCase();
      final customerName = data['customerName']?.toString() ?? 'N/A';
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
        _orderChannelId,
        _orderChannelName,
        channelDescription: _orderChannelDesc,
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        playSound: true,
        enableVibration: true,
      );
      const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);
      await plugin.show(
        doc.id.hashCode,
        'New Order #$orderNumber',
        'From: $customerName',
        platformChannelSpecifics,
      );
      debugPrint(
          '📢 Background Service: Notification shown for order $orderNumber');
    } catch (e) {
      debugPrint('❌ Background Service: Notification error: $e');
    }
  }

  static Future<void> _playNotificationSound(AudioPlayer audioPlayer) async {
    try {
      await audioPlayer.setReleaseMode(ReleaseMode.loop);
      await audioPlayer.play(AssetSource('notification.mp3'));
      debugPrint('🔊 Background Service: Playing sound loop');

      Future.delayed(const Duration(seconds: 5), () {
        audioPlayer.stop();
        audioPlayer.setReleaseMode(ReleaseMode.release);
        debugPrint('🔊 Background Service: Stopping loop');
      });
    } catch (e) {
      debugPrint('❌ Error playing sound: $e');
      debugPrint(
          '🔔 Please ensure "assets/notification.mp3" is in your pubspec.yaml');
    }
  }

  static Future<void> _vibrate() async {
    try {
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [500, 1000, 500, 1000]);
        debugPrint('📳 Background Service: Vibrating');
      }
    } catch (e) {
      debugPrint('❌ Background Service: Vibration error: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<void> startService() async {
    final service = FlutterBackgroundService();
    try {
      await service.startService();
      service.invoke('updateBranchIds', {'branchIds': []});
      debugPrint("🚀 Background Service: Main service started successfully.");
    } catch (e) {
      debugPrint("❌ Error starting service in startService(): $e");
    }
  }

  static Future<void> updateListener(List<String> branchIds) async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('updateBranchIds', {'branchIds': branchIds});
      debugPrint(
          '🚀 Background Service: Sending updateListener with branches: $branchIds');
    } catch (e) {
      debugPrint('❌ Error updating listener: $e');
    }
  }

  static Future<bool> isServiceRunning() async {
    try {
      final service = FlutterBackgroundService();
      return await service.isRunning();
    } catch (e) {
      debugPrint('❌ Error checking service status: $e');
      return false;
    }
  }
}