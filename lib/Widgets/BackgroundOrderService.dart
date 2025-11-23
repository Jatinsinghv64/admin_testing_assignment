import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';

@pragma('vm:entry-point')
class BackgroundOrderService {
  static const String _channelId = 'order_background_service';
  static const String _channelName = 'Order Listener Service';
  static const String _channelDesc = 'Maintains the restaurant state';
  static const String _orderChannelId = 'high_importance_channel';
  static const String _orderChannelName = 'New Order Notifications';
  static const String _orderChannelDesc = 'This channel is used for important order notifications.';

  static const String _prefsBranchKey = 'monitored_branch_ids';

  @pragma('vm:entry-point')
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    // Channel for the Persistent Notification (Service running)
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
          'longitude': value.longitude
        };
      } else if (value is Map) {
        sanitizedMap[key] =
            _sanitizeDataForInvoke(Map<String, dynamic>.from(value));
      } else if (value is List) {
        sanitizedMap[key] = value.map((item) {
          if (item is Map) {
            return _sanitizeDataForInvoke(Map<String, dynamic>.from(item));
          } else if (item is Timestamp) {
            return item.millisecondsSinceEpoch;
          } else if (item is GeoPoint) {
            return {'latitude': item.latitude, 'longitude': item.longitude};
          }
          return item;
        }).toList();
      } else {
        sanitizedMap[key] = value;
      }
    });
    return sanitizedMap;
  }

  @pragma('vm:entry-point')
  static Future<void> onStart(ServiceInstance service) async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    final FirebaseFirestore db = FirebaseFirestore.instance;
    final AudioPlayer audioPlayer = AudioPlayer();
    final Set<String> processedOrderIds = {};

    StreamSubscription? arrayListener;
    StreamSubscription? singularListener;

    final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();

    await localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    // ✅ FIXED: Removed 'priority' and 'fullScreenIntent' from Channel definition
    // 'importance: Importance.max' handles the priority level for the channel
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

    Future<void> connectToFirestore(List<String> branchIds) async {
      await arrayListener?.cancel();
      await singularListener?.cancel();
      arrayListener = null;
      singularListener = null;

      if (branchIds.isEmpty) {
        service.invoke('updateNotification', {
          'title': 'Restaurant Closed',
          'content': 'No branches active.'
        });
        return;
      }

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Restaurant Active',
          content: 'Monitoring ${branchIds.length} branches...',
        );
      }

      service.invoke('updateNotification', {
        'title': 'Restaurant Active',
        'content': 'Monitoring ${branchIds.length} branches for orders'
      });

      debugPrint('✅ Background Service: Monitoring branches: $branchIds');

      Future<void> handleSnapshot(QuerySnapshot snapshot, String source) async {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final doc = change.doc;
            final orderId = doc.id;
            final data = doc.data() as Map<String, dynamic>?;

            if (data == null) continue;

            final String status = (data['status'] ?? '').toString().toLowerCase();

            if (status != 'pending') continue;

            if (!processedOrderIds.contains(orderId)) {
              processedOrderIds.add(orderId);
              debugPrint('🎯 NEW PENDING ORDER ($source): $orderId');

              if (data['branchIds'] == null) {
                data['branchIds'] = branchIds;
              }
              data['orderId'] = orderId;

              final sanitizedData = _sanitizeDataForInvoke(data);

              await _showOrderNotification(doc as DocumentSnapshot<Map<String, dynamic>>, localNotifications);
              await _playNotificationSound(audioPlayer);
              await _vibrate();

              service.invoke('new_order', sanitizedData);
            }
          } else if (change.type == DocumentChangeType.removed) {
            processedOrderIds.remove(change.doc.id);
          }
        }
      }

      try {
        final arrayQuery = db
            .collection('Orders')
            .where('branchIds', arrayContainsAny: branchIds)
            .where('status', isEqualTo: 'pending');

        arrayListener = arrayQuery.snapshots().listen(
              (snap) => handleSnapshot(snap, "Array Query"),
          onError: (e) => debugPrint('❌ Array Query Error: $e'),
        );
      } catch (e) {
        debugPrint('❌ Setup Array Query Error: $e');
      }

      try {
        final safeBranchIds = branchIds.take(10).toList();
        final singularQuery = db
            .collection('Orders')
            .where('branchId', whereIn: safeBranchIds)
            .where('status', isEqualTo: 'pending');

        singularListener = singularQuery.snapshots().listen(
              (snap) => handleSnapshot(snap, "Singular Query"),
          onError: (e) => debugPrint('❌ Singular Query Error: $e'),
        );
      } catch (e) {
        debugPrint('❌ Setup Singular Query Error: $e');
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? savedBranches = prefs.getStringList(_prefsBranchKey);

      if (savedBranches != null && savedBranches.isNotEmpty) {
        debugPrint("💾 RESTART DETECTED: Restored ${savedBranches.length} branches from storage.");
        await connectToFirestore(savedBranches);
      } else {
        debugPrint("⚠️ No persisted branches found. Waiting for UI update.");
      }
    } catch (e) {
      debugPrint("⚠️ Error loading saved branches: $e");
    }

    service.on('updateBranchIds').listen((event) async {
      if (event is Map<String, dynamic>) {
        final List<String> branchIds =
            (event['branchIds'] as List?)?.map((e) => e.toString()).toList() ??
                [];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_prefsBranchKey, branchIds);
        debugPrint("💾 Saved branches to storage for persistence.");

        await connectToFirestore(branchIds);
      }
    });
  }

  static Future<void> _showOrderNotification(
      DocumentSnapshot<Map<String, dynamic>> doc,
      FlutterLocalNotificationsPlugin plugin) async {
    final data = doc.data();
    if (data == null) return;

    final orderNumber = data['dailyOrderNumber']?.toString() ??
        doc.id.substring(0, 6).toUpperCase();
    final customerName = data['customerName']?.toString() ?? 'Guest';
    final double amount = (data['totalAmount'] as num?)?.toDouble() ?? 0.0;

    // ✅ FIXED: priority and fullScreenIntent belong here, in AndroidNotificationDetails
    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      _orderChannelId,
      _orderChannelName,
      channelDescription: _orderChannelDesc,
      importance: Importance.max,
      priority: Priority.high, // This allows the notification to pop up on screen
      fullScreenIntent: true, // This allows waking the screen
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      timeoutAfter: 60000,
      styleInformation: BigTextStyleInformation(''),
    );

    await plugin.show(
      doc.id.hashCode,
      '🔔 NEW ORDER #$orderNumber',
      'Total: QAR $amount\nFrom: $customerName',
      const NotificationDetails(android: androidDetails),
      payload: doc.id,
    );
  }

  static Future<void> _playNotificationSound(AudioPlayer audioPlayer) async {
    try {
      await audioPlayer.stop();
      await audioPlayer.setReleaseMode(ReleaseMode.stop);
      await audioPlayer.play(AssetSource('notification.mp3'));
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }
  }

  static Future<void> _vibrate() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500]);
    }
  }

  @pragma('vm:entry-point')
  static Future<void> startService() async {
    final service = FlutterBackgroundService();
    if (!(await service.isRunning())) {
      await service.startService();
    }
  }

  static Future<void> updateListener(List<String> branchIds) async {
    final service = FlutterBackgroundService();
    service.invoke('updateBranchIds', {'branchIds': branchIds});
  }

  static Future<bool> isServiceRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }
}