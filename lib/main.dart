import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

// Import your screens
import 'Screens/ConnectionUtils.dart';
import 'Screens/LoginScreen.dart';
import 'Screens/MainScreen.dart'; // Contains BadgeCountProvider
import 'Widgets/Authorization.dart';
import 'Widgets/BackgroundOrderService.dart';
import 'Widgets/RestaurantStatusService.dart';
import 'Widgets/notification.dart';
import 'Widgets/FCM_Service.dart'; // ✅ NEW: Import FCM Service
import 'firebase_options.dart';

// Import the offline screen
import 'Screens/OfflineScreen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // --- START: ROBUST SERVICE LAUNCH ---
  // 1. Initialize the Background Service configuration (Local Notifications channels etc.)
  await BackgroundOrderService.initializeService();

  // 2. Check if the service is already running. If not, start it.
  final service = FlutterBackgroundService();
  bool isRunning = await service.isRunning();

  if (!isRunning) {
    debugPrint("🚀 MAIN: Service is not running. Starting it.");
    await BackgroundOrderService.startService();
  } else {
    debugPrint("✅ MAIN: Service is already running. Initialization complete.");
  }
  // --- END: ROBUST SERVICE LAUNCH ---

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
        // BadgeCountProvider is defined in Screens/MainScreen.dart
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

        // ✅ OFFLINE BANNER: Wraps the entire app to show red banner when internet is lost
        builder: (context, child) {
          return OfflineBanner(child: child!);
        },

        home: const AuthWrapper(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ScopeLoader & UserScopeService
// ---------------------------------------------------------------------------

class ScopeLoader extends StatefulWidget {
  final User user;
  const ScopeLoader({super.key, required this.user});

  @override
  State<ScopeLoader> createState() => _ScopeLoaderState();
}

class _ScopeLoaderState extends State<ScopeLoader> with WidgetsBindingObserver {
  final _service = FlutterBackgroundService();

  @override
  void initState() {
    super.initState();
    // ✅ Lifecycle Observation: Tell the background service if we are in Foreground
    WidgetsBinding.instance.addObserver(this);
    _service.invoke('appInForeground');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScope();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _service.invoke('appInForeground');
    } else {
      // Treat inactive, paused, detached as background
      _service.invoke('appInBackground');
    }
    debugPrint('App changed state: $state');
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
      // 1. Initialize restaurant status service
      if (scopeService.branchId.isNotEmpty) {
        String restaurantName = "Branch ${scopeService.branchId}";
        if (scopeService.userEmail.isNotEmpty) {
          restaurantName =
          "Restaurant (${scopeService.userEmail.split('@').first})";
        }

        statusService.initialize(scopeService.branchId,
            restaurantName: restaurantName);

        // Short delay to allow status to propagate
        await Future.delayed(const Duration(seconds: 1));
      }

      // 2. Initialize In-App Dialog Service (Listens to Background Service)
      notificationService.init(scopeService, navigatorKey);

      // 3. ✅ NEW: Initialize FCM Service (The Safety Net)
      // This is the critical "Hybrid" step. We initialize FCM now that we have the email.
      // It ensures that if the app is killed, the High Priority FCM will still reach us.
      await FcmService().init(scopeService.userEmail);

      debugPrint(
          '🎯 SYSTEM READY: User Scope Loaded + Background Service Linked + FCM Initialized');
    } else {
      debugPrint('❌ Failed to load user scope');
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
      if (_userEmail.isEmpty) {
        throw Exception('User email is null.');
      }

      debugPrint('🎯 Loading user scope for: $_userEmail');

      final staffSnap = await _db.collection('staff').doc(_userEmail).get();

      if (!staffSnap.exists) {
        debugPrint('❌ Scope Error: No staff document found for $_userEmail.');
        await clearScope();
        return false;
      }

      final data = staffSnap.data();
      final bool isActive = data?['isActive'] ?? false;

      if (!isActive) {
        debugPrint('❌ Scope Error: Staff member $_userEmail is not active.');
        await clearScope();
        return false;
      }

      _role = data?['role'] as String? ?? 'unknown';
      _branchIds = List<String>.from(data?['branchIds'] ?? []);
      _permissions = Map<String, bool>.from(data?['permissions'] ?? {});
      _isLoaded = true;

      debugPrint(
          '✅ Scope Loaded: $_userEmail | Role: $_role | Branches: $_branchIds | Permissions: $_permissions');

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
      debugPrint('❌ Error loading user scope: $e');
      await clearScope();
      return false;
    }
  }

  void _handleScopeUpdate(DocumentSnapshot snapshot, AuthService authService) {
    if (!snapshot.exists) {
      debugPrint('User scope document was deleted. Signing out.');
      authService.signOut();
      return;
    }

    final data = snapshot.data() as Map<String, dynamic>?;
    final bool isActive = data?['isActive'] ?? false;

    if (!isActive) {
      debugPrint('User is no longer active. Signing out.');
      authService.signOut();
      return;
    }

    _role = data?['role'] as String? ?? 'unknown';
    _branchIds = List<String>.from(data?['branchIds'] ?? []);
    _permissions = Map<String, bool>.from(data?['permissions'] ?? {});

    notifyListeners();
  }

  void _handleScopeError(Object error, AuthService authService) {
    debugPrint('Error listening to user scope: $error. Signing out.');
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