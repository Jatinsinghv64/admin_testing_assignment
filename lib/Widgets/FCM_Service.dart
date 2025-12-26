import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart'; // For navigatorKey
import '../Screens/MainScreen.dart'; // For HomeScreen

class FcmService {
  // Singleton pattern to ensure we only have one instance
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// Initialize the FCM Service
  /// Call this from main.dart or after user login
  Future<void> init(String adminEmail) async {
    if (_isInitialized) return;

    try {
      // 1. Initialize Local Notifications
      const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings();

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsDarwin,
      );

      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          if (response.payload != null) {
            _handleNotificationTap(jsonDecode(response.payload!));
          }
        },
      );

      // 2. Request FCM Permissions
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('FCM Permission: ${settings.authorizationStatus}');

      // 3. Save Token
      final token = await _fcm.getToken();
      if (token != null && adminEmail.isNotEmpty) {
        await _saveTokenToDatabase(adminEmail, token);
        _fcm.onTokenRefresh.listen((newToken) {
          _saveTokenToDatabase(adminEmail, newToken);
        });
      }

      // 4. Setup Message Handlers
      _setupMessageHandlers();

      _isInitialized = true;
      debugPrint("✅ FCM Service: Initialized (Safety Net Active)");
    } catch (e) {
      debugPrint("❌ FCM Init error: $e");
    }
  }

  void _setupMessageHandlers() {
    // 1. Foreground Messages
    // Note: In Hybrid approach, BackgroundService usually catches this first.
    // We rely on 'hashCode' deduplication to prevent double alerts.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🔵 FCM Foreground Message: ${message.messageId}');
      _showNotification(message);
    });

    // 2. Background Message Tapped (App opens from background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🟡 FCM Notification Tapped (Background)');
      _handleNotificationTap(message.data);
    });

    // 3. Terminated State (App opens from closed)
    _fcm.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('🔴 FCM Notification Tapped (Terminated)');
        Future.delayed(const Duration(seconds: 1), () {
          _handleNotificationTap(message.data);
        });
      }
    });
  }

  /// Displays the notification using LocalNotifications
  /// CRITICAL: Uses orderId.hashCode as the ID to match BackgroundOrderService
  Future<void> _showNotification(RemoteMessage message) async {
    final data = message.data;

    // ✅ FIX: Prioritize Data fields, fallback to Notification fields (which will be null now)
    String title = data['title'] ?? message.notification?.title ?? 'New Order';
    String body = data['body'] ?? message.notification?.body ?? 'You have a new order';

    final String? orderId = data['orderId'];

    // ✅ DEDUPLICATION MAGIC
    // Uses the same Integer ID as BackgroundOrderService.
    final int notificationId = orderId != null
        ? orderId.hashCode
        : DateTime.now().millisecondsSinceEpoch.remainder(100000);

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'high_importance_channel', // Must match BackgroundOrderService
      'New Order Notifications', // Must match BackgroundOrderService
      channelDescription: 'Important order notifications',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      color: Colors.deepPurple,
      visibility: NotificationVisibility.public,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: DarwinNotificationDetails(presentSound: true),
    );

    await flutterLocalNotificationsPlugin.show(
      notificationId,
      title,
      body,
      platformChannelSpecifics,
      payload: jsonEncode(data),
    );
  }
  void _handleNotificationTap(Map<String, dynamic> data) {
    final orderId = data['orderId'];
    if (orderId != null) {
      debugPrint("🚀 Navigating to Order: $orderId");
      final context = navigatorKey.currentContext;
      if (context != null) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
              (route) => false,
        );
        // Note: Ideally, pass the orderId to HomeScreen to open the specific order
      }
    }
  }

  Future<void> _saveTokenToDatabase(String adminEmail, String token) async {
    try {
      await _db.collection('staff').doc(adminEmail).set({
        'fcmToken': token,
        'fcmTokenUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
    }
  }
}