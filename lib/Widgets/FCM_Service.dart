import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../Screens/MainScreen.dart';
import 'Authorization.dart';
import 'notification.dart';

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  String? _currentEmail;

  Future<void> init(String adminEmail) async {
    if (_isInitialized) return;
    _currentEmail = adminEmail;

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

      // 3. Save Token (Strict Subcollection Mode)
      final token = await _fcm.getToken();
      if (token != null && adminEmail.isNotEmpty) {
        await _saveTokenToDatabase(adminEmail, token);

        // Listen for token refreshes
        _fcm.onTokenRefresh.listen((newToken) {
          _saveTokenToDatabase(adminEmail, newToken);
        });
      }

      // 4. Setup Message Handlers
      _setupMessageHandlers();

      _isInitialized = true;
      debugPrint("✅ FCM Service: Initialized (Strict Subcollection Mode)");
    } catch (e) {
      debugPrint("❌ FCM Init error: $e");
    }
  }

  void _setupMessageHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🔵 FCM Foreground Message: ${message.messageId}');
      final context = navigatorKey.currentContext;
      if (context != null) {
        final notifService = Provider.of<OrderNotificationService>(context, listen: false);
        final scopeService = Provider.of<UserScopeService>(context, listen: false);
        notifService.handleFCMOrder(message.data, scopeService);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🟡 FCM Notification Tapped (Background)');
      _handleNotificationTap(message.data);
    });

    _fcm.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('🔴 FCM Notification Tapped (Terminated)');
        Future.delayed(const Duration(seconds: 1), () {
          _handleNotificationTap(message.data);
        });
      }
    });
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final orderId = data['orderId'];
    if (orderId != null) {
      debugPrint("🚀 Notification Tapped. Navigating to Order: $orderId");
      final context = navigatorKey.currentContext;
      if (context != null) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthWrapper()),
              (route) => false,
        );

        final notifService = Provider.of<OrderNotificationService>(context, listen: false);
        final scopeService = Provider.of<UserScopeService>(context, listen: false);

        if (scopeService.isLoaded) {
          notifService.handleFCMOrder(data, scopeService);
        } else {
          void listener() {
            if (scopeService.isLoaded) {
              scopeService.removeListener(listener);
              notifService.handleFCMOrder(data, scopeService);
            }
          }
          scopeService.addListener(listener);
          Future.delayed(const Duration(seconds: 15), () {
            scopeService.removeListener(listener);
          });
        }
      }
    }
  }

  // ✅ STRICT FIX: Save ONLY to Subcollection 'tokens'
  Future<void> _saveTokenToDatabase(String adminEmail, String token) async {
    try {
      await _db
          .collection('staff')
          .doc(adminEmail)
          .collection('tokens')
          .doc(token)
          .set({
        'token': token,
        'lastUpdated': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.toString(),
      });
      debugPrint('✅ FCM Token saved to subcollection: ...${token.substring(token.length - 6)}');
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
    }
  }

  // ✅ NEW: Delete Token on Sign Out
  Future<void> deleteToken() async {
    if (_currentEmail == null) return;
    try {
      String? token = await _fcm.getToken();
      if (token != null) {
        await _db
            .collection('staff')
            .doc(_currentEmail)
            .collection('tokens')
            .doc(token)
            .delete();
        debugPrint("🗑️ FCM Token deleted from subcollection.");
      }
      _isInitialized = false;
      _currentEmail = null;
    } catch (e) {
      debugPrint("❌ Error deleting FCM token: $e");
    }
  }
}