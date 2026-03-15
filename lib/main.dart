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
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_app_check/firebase_app_check.dart'; // ✅ App Check for security
import 'Screens/ConnectionUtils.dart';
import 'Screens/MainScreen.dart';
import 'Screens/SplashScreen.dart';
import 'Widgets/Authorization.dart';
import 'Widgets/RestaurantStatusService.dart';
import 'Widgets/notification.dart';
import 'Widgets/FCM_Service.dart';
import 'services/ingredients/IngredientService.dart';
import 'services/ingredients/RecipeService.dart';
import 'services/inventory/InventoryService.dart';
import 'services/inventory/PurchaseOrderService.dart';
import 'services/inventory/WasteService.dart';
import 'firebase_options.dart';
import 'constants.dart'; // ✅ Added
import 'Widgets/AccessDeniedWidget.dart'; // ✅ Added
import 'Widgets/BranchFilterService.dart'; // ✅ Branch filter for multi-branch users
import 'services/DashboardThemeService.dart'; // ✅ Added for Dashboard Dark/Light Theme

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ---------------------------------------------------------------------------
// ✅ UPDATED TOP-LEVEL BACKGROUND HANDLER
// ---------------------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: ${message.messageId}");

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'New Order Notifications',
    description: 'This channel is used for important order notifications.',
    importance: Importance.max,
    playSound: true,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  String title = message.data['title'] ??
      message.notification?.title ??
      "New Order Received";
  String body = message.data['body'] ??
      message.notification?.body ??
      "Open app to view details";

  await flutterLocalNotificationsPlugin.show(
    message.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        icon: '@mipmap/ic_launcher',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      ),
    ),
  );
}

int getStableId(String id) {
  int hash = 5381;
  for (int i = 0; i < id.length; i++) {
    hash = ((hash << 5) + hash) + id.codeUnitAt(i);
  }
  return hash & 0x7FFFFFFF;
}

void main() async {
  // Wrap entire app in error zone for global error handling
  runZonedGuarded<Future<void>>(
    () async {
      debugPrint('🚀 [DIAGNOSTIC] main() started');
      WidgetsFlutterBinding.ensureInitialized();
      debugPrint('🚀 [DIAGNOSTIC] WidgetsFlutterBinding initialized');

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('🚀 [DIAGNOSTIC] Firebase initialized');

      // ✅ Initialize Firebase App Check for security
      try {
        debugPrint('🚀 [DIAGNOSTIC] Initializing Firebase App Check...');
        await FirebaseAppCheck.instance.activate(
          androidProvider: kDebugMode
              ? AndroidProvider.debug
              : AndroidProvider.playIntegrity,
          appleProvider:
              kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
        );
        debugPrint('✅ [DIAGNOSTIC] Firebase App Check initialized');
      } catch (e) {
        debugPrint('⚠️ [DIAGNOSTIC] App Check not configured: $e');
      }

      // Initialize Crashlytics for error reporting
      FlutterError.onError = (errorDetails) {
        debugPrint(
            '🔴 [DIAGNOSTIC] Flutter Error: ${errorDetails.exceptionAsString()}');
      };

      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // ✅ Initialize DashboardThemeService before runApp
      final dashboardThemeService = DashboardThemeService();
      await dashboardThemeService.initialize();

      debugPrint('🚀 [DIAGNOSTIC] Calling runApp(MyApp())');
      runApp(MyApp(dashboardThemeService: dashboardThemeService));
      debugPrint('🚀 [DIAGNOSTIC] runApp() executed');
    },
    (error, stackTrace) {
      // Global error handler for async errors
      debugPrint('🔴 Unhandled Error: $error');
      debugPrint('Stack trace: $stackTrace');
      // In production, send to Crashlytics:
      // FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: true);
    },
  );
}

class MyApp extends StatelessWidget {
  final DashboardThemeService dashboardThemeService;

  const MyApp({super.key, required this.dashboardThemeService});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<IngredientService>(create: (_) => IngredientService()),
        Provider<RecipeService>(create: (_) => RecipeService()),
        Provider<InventoryService>(create: (_) => InventoryService()),
        Provider<PurchaseOrderService>(create: (_) => PurchaseOrderService()),
        Provider<WasteService>(create: (_) => WasteService()),
        ChangeNotifierProvider<UserScopeService>(
          create: (_) => UserScopeService(),
        ),
        ChangeNotifierProvider<OrderNotificationService>(
          create: (_) => OrderNotificationService(),
        ),
        ChangeNotifierProvider<RestaurantStatusService>(
          create: (_) => RestaurantStatusService(),
        ),
        ChangeNotifierProvider(create: (_) => BadgeCountProvider()),
        ChangeNotifierProxyProvider<UserScopeService, BranchFilterService>(
          create: (_) => BranchFilterService(),
          update: (_, userScope, branchFilter) {
            branchFilter ??= BranchFilterService();
            if (userScope.isLoaded) {
              branchFilter.validateSelection(userScope.branchIds);
              // Automatically load names for all accessible branches
              branchFilter.loadBranchNames(userScope.branchIds);
            }
            return branchFilter;
          },
        ),
        ChangeNotifierProvider<DashboardThemeService>.value(
          value: dashboardThemeService,
        ),
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
        home: const SplashScreen(),
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
  bool _showPermissionBanner = false;

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissionsStatusOnly();
    }
  }

  Future<void> _loadScope() async {
    final scopeService = context.read<UserScopeService>();
    final notificationService = context.read<OrderNotificationService>();
    final statusService = context.read<RestaurantStatusService>();
    final authService = context.read<AuthService>();

    final bool isSuccess = await scopeService.loadUserScope(
      widget.user,
      authService,
    );

    if (isSuccess && mounted) {
      if (scopeService.branchIds.isNotEmpty) {
        String restaurantName = "Branch ${scopeService.branchIds.first}";
        if (scopeService.userEmail.isNotEmpty) {
          restaurantName =
              "Restaurant (${scopeService.userEmail.split('@').first})";
        }
        statusService.initialize(
          scopeService.branchIds.first,
          restaurantName: restaurantName,
        );
      }

      notificationService.init(scopeService, navigatorKey);
      await FcmService().init(scopeService.userIdentifier);

      // ✅ CRITICAL FIX: Process any pending notification from cold start
      // This handles the case where user tapped notification while app was terminated
      if (FcmService.hasPendingNotification) {
        debugPrint("📬 Processing pending cold-start notification...");
        // Small delay to ensure UI is fully ready
        await Future.delayed(const Duration(milliseconds: 500));
        FcmService.processPendingNotification(
          notificationService,
          scopeService,
        );
      }

      await _requestInitialPermissions();

      debugPrint('🎯 SYSTEM READY: FCM-Only Mode Active');
    }
  }

  Future<void> _requestInitialPermissions() async {
    PermissionStatus status = await Permission.notification.status;

    if (status.isGranted) {
      if (mounted) setState(() => _showPermissionBanner = false);
      return;
    }

    if (!status.isPermanentlyDenied) {
      status = await Permission.notification.request();
    }

    if (mounted) {
      setState(() {
        _showPermissionBanner = !status.isGranted;
      });
    }
  }

  Future<void> _checkPermissionsStatusOnly() async {
    final status = await Permission.notification.status;
    if (mounted) {
      setState(() {
        _showPermissionBanner = !status.isGranted;
      });
    }
  }

  Widget _buildPermissionBanner() {
    return Container(
      color: Colors.orange[50],
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.notification_important, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: const Text(
              "Notifications are required to receive orders.",
              style: TextStyle(fontSize: 13, color: Colors.brown),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => openAppSettings(),
            style: TextButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text("Enable"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scopeService = context.watch<UserScopeService>();

    // ✅ FIX: Handle missing account cleanly without infinite logout loops
    if (scopeService.isAccountMissing) {
      return const Scaffold(
        body: AccessDeniedWidget(
          permission: "Account Record Missing. Please contact Admin.",
        ),
      );
    }

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

    return Scaffold(
      body: Column(
        children: [
          if (_showPermissionBanner)
            SafeArea(bottom: false, child: _buildPermissionBanner()),
          const Expanded(child: HomeScreen()),
        ],
      ),
    );
  }
}

class UserScopeService with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  StreamSubscription? _scopeSubscription;

  String _role = 'unknown';
  List<String> _branchIds = [];
  Map<String, bool> _permissions = {};
  bool _isLoaded = false;
  bool _isAccountMissing = false;
  String _userEmail = '';
  String _userIdentifier = '';

  String get role => _role;
  List<String> get branchIds => _branchIds;
  String get userEmail => _userEmail;
  String get userIdentifier => _userIdentifier;
  bool get isLoaded => _isLoaded;
  bool get isAccountMissing => _isAccountMissing;
  bool get isSuperAdmin => _isSuperAdminRole(_role);
  Map<String, bool> get permissions => _permissions;

  /// Normalized check for super_admin role
  bool _isSuperAdminRole(String? role) {
    if (role == null) return false;
    final r = role.toLowerCase().trim().replaceAll(' ', '_').replaceAll('-', '_');
    return r == 'super_admin' || r == 'superadmin';
  }

  Future<bool> loadUserScope(User user, AuthService authService) async {
    if (_isLoaded) return true;
    await _scopeSubscription?.cancel();
    _scopeSubscription = null;

    try {
      _userEmail = user.email ?? '';
      _userIdentifier = user.email ?? user.phoneNumber ?? '';
      if (_userIdentifier.isEmpty)
        throw Exception('User identifier (email or phone) is null.');

      final staffSnap = await _db
          .collection(AppConstants.collectionStaff)
          .doc(_userIdentifier)
          .get();

      if (!staffSnap.exists) {
        _isAccountMissing = true;
        notifyListeners();
        return false;
      }

      final data = staffSnap.data();
      if (data?['isActive'] != true) {
        _isAccountMissing = true;
        notifyListeners();
        return false;
      }

      await _applyData(data, notify: false);

      _scopeSubscription = _db
          .collection(AppConstants.collectionStaff)
          .doc(_userIdentifier)
          .snapshots()
          .listen(
            (snapshot) => _handleScopeUpdate(snapshot, authService),
            onError: (error) => _handleScopeError(error, authService),
          );

      _isLoaded = true;
      _isAccountMissing = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error loading user scope: $e');
      await clearScope();
      return false;
    }
  }

  /// Internal method to apply data from staff document, 
  /// handling SuperAdmin branch expansion.
  Future<void> _applyData(Map<String, dynamic>? data, {bool notify = true}) async {
    if (data == null) return;

    _role = data['role'] as String? ?? 'unknown';
    _permissions = Map<String, bool>.from(data['permissions'] ?? {});
    
    final List<String> explicitBranchIds = 
        List<String>.from(data['branchIds'] ?? []).toSet().toList();

    if (_isSuperAdminRole(_role)) {
      try {
        // Super Admins should have access to ALL branches
        final branchesSnap = await _db.collection(AppConstants.collectionBranch).get();
        final allIds = branchesSnap.docs.map((doc) => doc.id).toSet();
        
        // Combine explicitly assigned with all available
        final combined = explicitBranchIds.toSet()..addAll(allIds);
        _branchIds = combined.toList();
      } catch (e) {
        debugPrint('Error fetching all branches for super admin: $e');
        _branchIds = explicitBranchIds; // Fallback
      }
    } else {
      _branchIds = explicitBranchIds;
    }

    if (notify) notifyListeners();
  }

  void _handleScopeUpdate(DocumentSnapshot snapshot, AuthService authService) async {
    if (!snapshot.exists) {
      _isAccountMissing = true;
      _isLoaded = false;
      notifyListeners();
      return;
    }
    
    final data = snapshot.data() as Map<String, dynamic>?;
    if (data?['isActive'] != true) {
      _isAccountMissing = true;
      _isLoaded = false;
      notifyListeners();
      return;
    }

    _isAccountMissing = false;
    await _applyData(data, notify: true);
    _isLoaded = true;
  }

  bool can(String permissionKey) {
    if (isSuperAdmin) return true;
    return _permissions[permissionKey] ?? false;
  }

  void _handleScopeError(Object error, AuthService authService) {
    debugPrint("Scope Error: $error");
  }

  Future<void> clearScope() async {
    await _scopeSubscription?.cancel();
    _scopeSubscription = null;
    _role = 'unknown';
    _branchIds = [];
    _permissions = {};
    _isLoaded = false;
    _isAccountMissing = false;
    _userEmail = '';
    _userIdentifier = '';
    notifyListeners();
  }
}
