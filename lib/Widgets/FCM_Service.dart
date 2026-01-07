import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';

import '../main.dart';
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

  // ✅ NEW: Store pending notification for cold start scenarios
  static Map<String, dynamic>? _pendingNotificationData;
  
  /// Check if there's a pending notification to be processed
  static bool get hasPendingNotification => _pendingNotificationData != null;
  
  /// Get and clear pending notification data
  static Map<String, dynamic>? consumePendingNotification() {
    final data = _pendingNotificationData;
    _pendingNotificationData = null;
    return data;
  }

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

      // 4. ✅ CRITICAL FIX: Check for initial message SYNCHRONOUSLY before setting up handlers
      // This ensures we capture cold-start notifications before init() returns
      final RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('🔴 FCM: Cold start notification found during init');
        _pendingNotificationData = initialMessage.data;
      }

      // 5. Setup Message Handlers for foreground/background (but NOT initial - already handled)
      _setupMessageHandlers();

      _isInitialized = true;
      debugPrint("✅ FCM Service: Initialized (Strict Subcollection Mode)");
    } catch (e) {
      debugPrint("❌ FCM Init error: $e");
    }
  }

  void _setupMessageHandlers() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🔵 FCM Foreground Message: ${message.messageId}');
      final context = navigatorKey.currentContext;
      if (context != null) {
        final notifService = Provider.of<OrderNotificationService>(context, listen: false);
        final scopeService = Provider.of<UserScopeService>(context, listen: false);
        notifService.handleFCMOrder(message.data, scopeService);
      }
    });

    // Handle background notification tap (app was in background, not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🟡 FCM Notification Tapped (Background)');
      _handleNotificationTap(message.data);
    });
    
    // NOTE: getInitialMessage() for terminated state is now handled in init()
    // to ensure synchronous capture before init() returns
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final orderId = data['orderId'];
    if (orderId == null) return;
    
    debugPrint("🚀 Notification Tapped. Order: $orderId");
    
    final context = navigatorKey.currentContext;
    
    // If no context available (should not happen for background tap, but just in case)
    if (context == null) {
      debugPrint("📦 No context - storing notification for later processing");
      _pendingNotificationData = data;
      return;
    }
    
    // ✅ For background tap (onMessageOpenedApp), services should already be available
    // Try to show the dialog directly
    try {
      final notifService = Provider.of<OrderNotificationService>(context, listen: false);
      final scopeService = Provider.of<UserScopeService>(context, listen: false);
      
      if (scopeService.isLoaded && notifService.isInitialized) {
        debugPrint("✅ Services ready - showing order dialog directly");
        notifService.handleFCMOrder(data, scopeService);
      } else {
        // Services not ready, store for when they are
        debugPrint("⏳ Services not ready - storing for later");
        _pendingNotificationData = data;
      }
    } catch (e) {
      debugPrint("⚠️ Error accessing services: $e - storing notification");
      _pendingNotificationData = data;
    }
  }
  
  /// Process any pending notification. Call this after full app initialization.
  /// Returns true if a notification was processed.
  static bool processPendingNotification(
    OrderNotificationService notifService,
    UserScopeService scopeService,
  ) {
    final data = consumePendingNotification();
    if (data == null) return false;
    
    final orderId = data['orderId'];
    if (orderId == null) return false;
    
    debugPrint("🔔 Processing pending notification for order: $orderId");
    
    if (scopeService.isLoaded) {
      notifService.handleFCMOrder(data, scopeService);
      return true;
    } else {
      debugPrint("⚠️ Scope not loaded yet - notification may be handled by backup listener");
      return false;
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