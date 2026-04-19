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
import 'Screens/core/ConnectionUtils.dart';
import 'Screens/core/MainScreen.dart';
import 'Screens/core/SplashScreen.dart';
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
import 'services/pos/pos_service.dart';
import 'services/staff/staff_service.dart';
import 'services/ai/ai_cache_service.dart';
import 'services/ai/gemini_service.dart';
import 'services/ai/ai_data_fetcher.dart';
import 'services/ai/ai_insights_service.dart';
import 'services/expenses/expense_service.dart'; // ✅ Added

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const Color _adminPurple = Color(0xFF4A148C);
const Color _adminPurpleMuted = Color(0x224A148C);
const Color _darkScaffold = Colors.black;
const Color _darkSurface = Color(0xFF101010);
const Color _darkSurfaceVariant = Color(0xFF181818);
const Color _darkOutline = Color(0xFF2A2A2A);

TextTheme _exactWhiteTextTheme(TextTheme base) {
  const white = Colors.white;
  return base.apply(bodyColor: white, displayColor: white).copyWith(
        displayLarge: base.displayLarge?.copyWith(color: white),
        displayMedium: base.displayMedium?.copyWith(color: white),
        displaySmall: base.displaySmall?.copyWith(color: white),
        headlineLarge: base.headlineLarge?.copyWith(color: white),
        headlineMedium: base.headlineMedium?.copyWith(color: white),
        headlineSmall: base.headlineSmall?.copyWith(color: white),
        titleLarge: base.titleLarge?.copyWith(color: white),
        titleMedium: base.titleMedium?.copyWith(color: white),
        titleSmall: base.titleSmall?.copyWith(color: white),
        bodyLarge: base.bodyLarge?.copyWith(color: white),
        bodyMedium: base.bodyMedium?.copyWith(color: white),
        bodySmall: base.bodySmall?.copyWith(color: white),
        labelLarge: base.labelLarge?.copyWith(color: white),
        labelMedium: base.labelMedium?.copyWith(color: white),
        labelSmall: base.labelSmall?.copyWith(color: white),
      );
}

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
        if (!kIsWeb) {
          await FirebaseAppCheck.instance.activate(
            androidProvider: kDebugMode
                ? AndroidProvider.debug
                : AndroidProvider.playIntegrity,
            appleProvider:
                kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
          );
          debugPrint('✅ [DIAGNOSTIC] Firebase App Check initialized');
        } else {
          debugPrint(
              'ℹ️ [DIAGNOSTIC] App Check skipped for Web (needs ReCaptcha configuration)');
        }
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
        ChangeNotifierProvider<ExpenseService>(
          create: (_) => ExpenseService(),
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
        ChangeNotifierProvider<PosService>(create: (_) => PosService()),
        Provider<StaffService>(create: (_) => StaffService()),
        ChangeNotifierProvider<AIInsightsService>(
          create: (_) => AIInsightsService(
            geminiService: GeminiService(),
            cacheService: AICacheService(),
            dataFetcher: AIDataFetcher(),
          ),
        ),
      ],
      builder: (context, child) {
        final themeService = context.watch<DashboardThemeService>();
        return MaterialApp(
          themeMode: themeService.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            primaryColor: themeService.primaryColor,
            colorScheme: ColorScheme.fromSeed(
              seedColor: themeService.primaryColor,
              brightness: Brightness.light,
            ),
            visualDensity: VisualDensity.adaptivePlatformDensity,
            scaffoldBackgroundColor: Colors.grey[50],
            cardColor: Colors.white,
            cardTheme: CardThemeData(
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              iconTheme: IconThemeData(color: themeService.primaryColor),
              titleTextStyle: TextStyle(
                color: themeService.primaryColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              backgroundColor: Colors.white,
              selectedItemColor: themeService.primaryColor,
              unselectedItemColor: Colors.grey,
              elevation: 10,
            ),
            drawerTheme: const DrawerThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              modalBackgroundColor: Colors.white,
            ),
            popupMenuTheme: PopupMenuThemeData(
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            menuTheme: MenuThemeData(
              style: MenuStyle(
                backgroundColor: WidgetStateProperty.all(Colors.white),
                surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
                side: WidgetStateProperty.all(BorderSide(color: Colors.grey[300]!)),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: themeService.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
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
                borderSide: BorderSide(color: themeService.primaryColor, width: 2),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: _darkScaffold,
            canvasColor: _darkScaffold,
            primaryColor: themeService.primaryColor,
            textTheme: _exactWhiteTextTheme(
                ThemeData.dark(useMaterial3: true).textTheme),
            primaryTextTheme: _exactWhiteTextTheme(
                ThemeData.dark(useMaterial3: true).primaryTextTheme),
            iconTheme: const IconThemeData(color: Colors.white),
            colorScheme: ColorScheme.dark(
              primary: themeService.primaryColor,
              onPrimary: Colors.white,
              secondary: themeService.primaryColor,
              onSecondary: Colors.white,
              surface: _darkSurface,
              onSurface: Colors.white,
              error: const Color(0xFFEF5350),
              onError: Colors.white,
              outline: _darkOutline,
              outlineVariant: const Color(0xFF242424),
            ),
            cardTheme: CardThemeData(
              color: _darkSurface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: _darkOutline),
              ),
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: _darkScaffold,
              foregroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              iconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              backgroundColor: _darkSurface,
              selectedItemColor: themeService.primaryColor,
              unselectedItemColor: Colors.grey,
              elevation: 10,
            ),
            drawerTheme: const DrawerThemeData(
              backgroundColor: _darkSurface,
              surfaceTintColor: Colors.transparent,
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: _darkSurface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: _darkSurface,
              surfaceTintColor: Colors.transparent,
              modalBackgroundColor: _darkSurface,
            ),
            popupMenuTheme: PopupMenuThemeData(
              color: _darkSurfaceVariant,
              surfaceTintColor: Colors.transparent,
              textStyle: const TextStyle(color: Colors.white),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: _darkOutline),
              ),
            ),
            menuTheme: MenuThemeData(
              style: MenuStyle(
                backgroundColor: WidgetStateProperty.all(_darkSurfaceVariant),
                surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
                side: WidgetStateProperty.all(
                    const BorderSide(color: _darkOutline)),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            dividerTheme: const DividerThemeData(
              color: _darkOutline,
              thickness: 1,
            ),
            listTileTheme: ListTileThemeData(
              iconColor: Colors.white,
              textColor: Colors.white,
              selectedColor: Colors.white,
              selectedTileColor: themeService.primaryColor,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: themeService.primaryColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: themeService.primaryColor.withValues(alpha: 0.13),
                side: BorderSide(color: themeService.primaryColor, width: 1.2),
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            chipTheme: ChipThemeData(
              backgroundColor: _darkSurfaceVariant,
              selectedColor: themeService.primaryColor,
              secondarySelectedColor: themeService.primaryColor,
              disabledColor: const Color(0xFF151515),
              labelStyle: const TextStyle(color: Colors.white),
              secondaryLabelStyle: const TextStyle(color: Colors.white),
              checkmarkColor: Colors.white,
              side: const BorderSide(color: _darkOutline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return const Color(0xFFBDBDBD);
              }),
              trackColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return themeService.primaryColor;
                }
                return _darkSurfaceVariant;
              }),
              trackOutlineColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return themeService.primaryColor;
                }
                return _darkOutline;
              }),
            ),
            checkboxTheme: CheckboxThemeData(
              fillColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return themeService.primaryColor;
                }
                return _darkSurfaceVariant;
              }),
              checkColor: WidgetStateProperty.all(Colors.white),
              side: const BorderSide(color: _darkOutline),
            ),
            radioTheme: RadioThemeData(
              fillColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return themeService.primaryColor;
                }
                return Colors.white;
              }),
            ),
            tabBarTheme: TabBarThemeData(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: themeService.primaryColor,
              dividerColor: _darkOutline,
            ),
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: Colors.white,
              selectionColor: themeService.primaryColor.withValues(alpha: 0.13),
              selectionHandleColor: themeService.primaryColor,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: _darkSurfaceVariant,
              hintStyle: const TextStyle(color: Colors.white70),
              labelStyle: const TextStyle(color: Colors.white),
              prefixIconColor: Colors.white70,
              suffixIconColor: Colors.white70,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _darkOutline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _darkOutline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: themeService.primaryColor, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFEF5350)),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFFEF5350), width: 2),
              ),
            ),
          ),
          builder: (context, child) {
            return OfflineBanner(child: child!);
          },
          home: const SplashScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
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
  bool _isPermissionBannerDismissed = false;

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
        if (status.isGranted)
          _isPermissionBannerDismissed = false; // Reset on fix
      });
    }
  }

  Future<void> _checkPermissionsStatusOnly() async {
    final status = await Permission.notification.status;
    if (mounted) {
      setState(() {
        _showPermissionBanner = !status.isGranted;
        if (status.isGranted)
          _isPermissionBannerDismissed = false; // Reset on fix
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
          IconButton(
            onPressed: () {
              setState(() {
                _isPermissionBannerDismissed = true;
              });
            },
            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
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
          if (_showPermissionBanner && !_isPermissionBannerDismissed)
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
    final r =
        role.toLowerCase().trim().replaceAll(' ', '_').replaceAll('-', '_');
    return r == 'super_admin' || r == 'superadmin';
  }

  Future<bool> loadUserScope(User? user, AuthService authService) async {
    if (user == null) return false;
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
  Future<void> _applyData(Map<String, dynamic>? data,
      {bool notify = true}) async {
    if (data == null) return;

    _role = data['role'] as String? ?? 'unknown';
    _permissions = Map<String, bool>.from(data['permissions'] ?? {});

    final List<String> explicitBranchIds =
        List<String>.from(data['branchIds'] ?? []).toSet().toList();

    if (_isSuperAdminRole(_role)) {
      try {
        // Super Admins should have access to ALL branches
        final branchesSnap =
            await _db.collection(AppConstants.collectionBranch).get();
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

  void _handleScopeUpdate(
      DocumentSnapshot snapshot, AuthService authService) async {
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
