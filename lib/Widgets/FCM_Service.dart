import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';

import '../main.dart'; // For navigatorKey, UserScopeService
import '../Screens/MainScreen.dart'; // For HomeScreen
import 'Authorization.dart'; // ✅ IMPORT AUTHORIZATION FOR AUTHWRAPPER
import 'notification.dart';

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

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
            try {
              final decoded = jsonDecode(response.payload!);
              if (decoded is Map<String, dynamic>) {
                _handleNotificationTap(decoded);
              }
            } catch (e) {
              debugPrint("Notification Payload Error: $e");
            }
          }
        },
      );

      // 2. Request FCM Permissions
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true, badge: true, sound: true, provisional: false,
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
      debugPrint("✅ FCM Service: Initialized (FCM-Only Mode)");
    } catch (e) {
      debugPrint("❌ FCM Init error: $e");
    }
  }

  void _setupMessageHandlers() {
    // 1. Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🔵 FCM Foreground Message: ${message.messageId}');

      final context = navigatorKey.currentContext;
      if (context != null) {
        final notifService = Provider.of<OrderNotificationService>(context, listen: false);
        final scopeService = Provider.of<UserScopeService>(context, listen: false);

        // Pass the FCM data to the notification service to spawn the dialog
        notifService.handleFCMOrder(message.data, scopeService);
      }
    });

    // 2. Background Message Tapped
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🟡 FCM Notification Tapped (Background)');
      _handleNotificationTap(message.data);
    });

    // 3. Terminated State
    _fcm.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('🔴 FCM Notification Tapped (Terminated)');
        Future.delayed(const Duration(seconds: 1), () {
          _handleNotificationTap(message.data);
        });
      }
    });
  }

  // ✅ FIX: Wait for Scope & Trigger Dialog
  void _handleNotificationTap(Map<String, dynamic> data) {
    final orderId = data['orderId'];
    if (orderId != null) {
      debugPrint("🚀 Notification Tapped. Navigating to Order: $orderId");
      final context = navigatorKey.currentContext;
      if (context != null) {

        // 1. Navigate to AuthWrapper (triggers ScopeLoader) instead of HomeScreen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthWrapper()),
              (route) => false,
        );

        // 2. TRIGGER THE DIALOG
        final notifService = Provider.of<OrderNotificationService>(context, listen: false);
        final scopeService = Provider.of<UserScopeService>(context, listen: false);

        // Check if user data is loaded (Critical for Cold Start)
        if (scopeService.isLoaded) {
          notifService.handleFCMOrder(data, scopeService);
        } else {
          debugPrint("⏳ Scope not loaded yet (Cold Start). Waiting...");

          // Listener to fire once scope loads
          void listener() {
            if (scopeService.isLoaded) {
              debugPrint("✅ Scope loaded. Triggering delayed dialog.");
              scopeService.removeListener(listener);
              notifService.handleFCMOrder(data, scopeService);
            }
          }

          scopeService.addListener(listener);

          // Safety timeout (remove listener after 15s if nothing happens)
          Future.delayed(const Duration(seconds: 15), () {
            scopeService.removeListener(listener);
          });
        }
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

  // Helper for consistent IDs
  int getStableId(String id) {
    int hash = 5381;
    for (int i = 0; i < id.length; i++) {
      hash = ((hash << 5) + hash) + id.codeUnitAt(i);
    }
    return hash & 0x7FFFFFFF;
  }
}