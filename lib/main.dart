import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'Screens/ConnectionUtils.dart';
import 'Screens/LoginScreen.dart';
import 'Screens/MainScreen.dart';
import 'Widgets/Authorization.dart';
import 'Widgets/RestaurantStatusService.dart';
import 'Widgets/notification.dart';
import 'Widgets/FCM_Service.dart';
import 'firebase_options.dart';
import 'Screens/OfflineScreen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ---------------------------------------------------------------------------
// ✅ TOP-LEVEL BACKGROUND HANDLER (For Terminated/Background State)
// ---------------------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final data = message.data;
  final String? orderId = data['orderId'];

  if (orderId != null) {
    // ✅ Stable ID Generator (Prevents duplicates)
    final int notificationId = getStableId(orderId);

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'New Order Notifications',
      channelDescription: 'Important order notifications',
      importance: Importance.max,
      priority: Priority.high,
      color: Colors.deepPurple,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(presentSound: true),
    );

    await flutterLocalNotificationsPlugin.show(
      notificationId,
      data['title'] ?? 'New Order',
      data['body'] ?? 'Check your dashboard',
      platformDetails,
      payload: orderId,
    );
  }
}

// ✅ HELPER: Must be top-level for the background handler
int getStableId(String id) {
  int hash = 5381;
  for (int i = 0; i < id.length; i++) {
    hash = ((hash << 5) + hash) + id.codeUnitAt(i);
  }
  return hash & 0x7FFFFFFF;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ✅ Register Background Handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider<UserScopeService>(create: (_) => UserScopeService()),
        ChangeNotifierProvider<OrderNotificationService>(create: (_) => OrderNotificationService()),
        ChangeNotifierProvider<RestaurantStatusService>(create: (_) => RestaurantStatusService()),
        ChangeNotifierProvider(create: (_) => BadgeCountProvider()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Branch Admin App',
        theme: ThemeData(
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
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            backgroundColor: Colors.white,
            selectedItemColor: Colors.deepPurple,
            unselectedItemColor: Colors.grey,
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
        builder: (context, child) {
          return OfflineBanner(child: child!);
        },
        home: const AuthWrapper(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class ScopeLoader extends StatefulWidget {
  final User user;
  const ScopeLoader({super.key, required this.user});

  @override
  State<ScopeLoader> createState() => _ScopeLoaderState();
}

class _ScopeLoaderState extends State<ScopeLoader> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScope();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadScope() async {
    final scopeService = context.read<UserScopeService>();
    final notificationService = context.read<OrderNotificationService>();
    final statusService = context.read<RestaurantStatusService>();
    final authService = context.read<AuthService>();

    final bool isSuccess = await scopeService.loadUserScope(widget.user, authService);

    if (isSuccess && mounted) {
      if (scopeService.branchId.isNotEmpty) {
        String restaurantName = "Branch ${scopeService.branchId}";
        if (scopeService.userEmail.isNotEmpty) {
          restaurantName = "Restaurant (${scopeService.userEmail.split('@').first})";
        }
        statusService.initialize(scopeService.branchId, restaurantName: restaurantName);
      }

      // ✅ Initialize Notification Services (FCM Only)
      notificationService.init(scopeService, navigatorKey);
      await FcmService().init(scopeService.userEmail);

      debugPrint('🎯 SYSTEM READY: FCM-Only Mode Active');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scopeService = context.watch<UserScopeService>();
    if (!scopeService.isLoaded) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Verifying credentials..."),
            ],
          ),
        ),
      );
    }
    return const HomeScreen();
  }
}

// ... (UserScopeService class remains unchanged from your original file)
class UserScopeService with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  StreamSubscription? _scopeSubscription;

  String _role = 'unknown';
  List<String> _branchIds = [];
  Map<String, bool> _permissions = {};
  bool _isLoaded = false;
  String _userEmail = '';

  String get role => _role;
  List<String> get branchIds => _branchIds;
  String get branchId => _branchIds.isNotEmpty ? _branchIds.first : '';
  String get userEmail => _userEmail;
  bool get isLoaded => _isLoaded;
  bool get isSuperAdmin => _role == 'super_admin';
  Map<String, bool> get permissions => _permissions;

  bool can(String permissionKey) {
    if (isSuperAdmin) return true;
    return _permissions[permissionKey] ?? false;
  }

  Future<bool> loadUserScope(User user, AuthService authService) async {
    if (_isLoaded) return true;
    await _scopeSubscription?.cancel();
    _scopeSubscription = null;

    try {
      _userEmail = user.email ?? '';
      if (_userEmail.isEmpty) throw Exception('User email is null.');

      final staffSnap = await _db.collection('staff').doc(_userEmail).get();
      if (!staffSnap.exists) {
        await clearScope();
        return false;
      }
      final data = staffSnap.data();
      if (data?['isActive'] != true) {
        await clearScope();
        return false;
      }

      _role = data?['role'] as String? ?? 'unknown';
      _branchIds = List<String>.from(data?['branchIds'] ?? []);
      _permissions = Map<String, bool>.from(data?['permissions'] ?? {});
      _isLoaded = true;

      _scopeSubscription = _db
          .collection('staff')
          .doc(_userEmail)
          .snapshots()
          .listen(
            (snapshot) => _handleScopeUpdate(snapshot, authService),
        onError: (error) => _handleScopeError(error, authService),
      );

      notifyListeners();
      return true;
    } catch (e) {
      await clearScope();
      return false;
    }
  }

  void _handleScopeUpdate(DocumentSnapshot snapshot, AuthService authService) {
    if (!snapshot.exists) {
      authService.signOut();
      return;
    }
    final data = snapshot.data() as Map<String, dynamic>?;
    if (data?['isActive'] != true) {
      authService.signOut();
      return;
    }
    _role = data?['role'] as String? ?? 'unknown';
    _branchIds = List<String>.from(data?['branchIds'] ?? []);
    _permissions = Map<String, bool>.from(data?['permissions'] ?? {});
    notifyListeners();
  }

  void _handleScopeError(Object error, AuthService authService) {
    authService.signOut();
  }

  Future<void> clearScope() async {
    await _scopeSubscription?.cancel();
    _scopeSubscription = null;
    _role = 'unknown';
    _branchIds = [];
    _permissions = {};
    _isLoaded = false;
    _userEmail = '';
    notifyListeners();
  }
}