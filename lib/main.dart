
// ❌ REMOVED: import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
// ❌ REMOVED: import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
// ❌ REMOVED: import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_background_service/flutter_background_service.dart'; // Import service

// Import your screens
import 'Screens/MainScreen.dart';
import 'Widgets/Authorization.dart';
import 'Widgets/BackgroundOrderService.dart';
import 'Widgets/RestaurantStatusService.dart';
import 'Widgets/ScopeLoader.dart';
import 'Widgets/notification.dart';
import 'firebase_options.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();



void _navigateToOrder(String orderId) {
  // This function is still used by notification.dart (via the dialog)
  final context = navigatorKey.currentContext;
  if (context != null) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => HomeScreen()),
          (route) => false,
    );
    debugPrint("Should navigate to order: $orderId");
  } else {
    debugPrint("❌ Cannot navigate! Navigator context is null.");
  }
}

// ❌ REMOVED: _initializeLocalNotifications

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // --- START: ROBUST SERVICE LAUNCH ---
  final service = FlutterBackgroundService();

  // ✅ ALWAYS initialize (configure) the service first.
  await BackgroundOrderService.initializeService();

  // Now, check if it's running.
  bool isRunning = await service.isRunning();

  if (!isRunning) {
    debugPrint(
        "🚀 MAIN: Service is not running. Starting it.");
    await BackgroundOrderService.startService();
  } else {
    debugPrint(
        "✅ MAIN: Service is already running. Initialization complete.");
  }
  // --- END: ROBUST SERVICE LAUNCH ---

  // ❌ REMOVED: await _initializeLocalNotifications();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(
          create: (_) => AuthService(),
        ),
        ChangeNotifierProvider<UserScopeService>(
          create: (_) => UserScopeService(),
        ),
        ChangeNotifierProvider<OrderNotificationService>(
          create: (_) => OrderNotificationService(),
        ),
        ChangeNotifierProvider<RestaurantStatusService>(
          create: (_) => RestaurantStatusService(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Branch Admin App',
        theme: ThemeData(
          // ... Your theme data ...
          primarySwatch: Colors.deepPurple,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          scaffoldBackgroundColor: Colors.grey[50],
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            elevation: 0,
            iconTheme: IconThemeData(color: Colors.deepPurple),
            titleTextStyle: TextStyle(
              color: Colors.deepPurple,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          bottomNavigationBarTheme: BottomNavigationBarThemeData(
            backgroundColor: Colors.white,
            selectedItemColor: Colors.deepPurple,
            unselectedItemColor: Colors.grey[600],
            elevation: 10,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
            ),
          ),
        ),
        home: const AuthWrapper(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class Permissions {
  static const String canViewDashboard = 'canViewDashboard';
  static const String canManageInventory = 'canManageInventory';
  static const canViewAnalytics = 'canViewAnalytics';
  static const String canManageOrders = 'canManageOrders';
  static const String canManageRiders = 'canManageRiders';
  static const String canManageSettings = 'canManageSettings';
  static const String canManageStaff = 'canManageStaff';
  static const String canManageCoupons = 'canManageCoupons';
}

class AppScreen {
  final AppTab tab;
  final String permissionKey;
  final Widget screen;
  final BottomNavigationBarItem navItem;
  AppScreen({
    required this.tab,
    required this.permissionKey,
    required this.screen,
    required this.navItem,
  });
}

enum AppTab { dashboard, inventory, orders, riders, analytics, settings }