import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Widgets/Permissions.dart';
import '../Widgets/RestaurantStatusService.dart';
// import '../Widgets/RiderAssignment.dart'; // No longer needed here
import '../main.dart';
import 'DashboardScreen.dart';
import 'MenuManagement.dart';
import 'ManualAssignmentScreen.dart'; // Import the new screen
import 'OrdersScreen.dart';
import 'RidersScreen.dart';
import 'SettingsScreen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  List<Widget> _screens = [];
  List<BottomNavigationBarItem> _navItems = [];
  Map<AppTab, AppScreen> _allScreens = {}; // Initialize as empty

  // Restaurant status
  bool _isRestaurantStatusInitialized = false;
  bool _isBuildingNavItems = false;
  // bool _didInitScreens = false; // No longer needed

  // --- FIX: Store the last known branchId to detect changes ---
  String? _lastKnownBranchId;

  // Callback method for tab changes from Dashboard
  void _onTabChange(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
    // initState is clean. All init logic is in didChangeDependencies.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final userScope = context.watch<UserScopeService>();
    final badgeProvider = context.read<BadgeCountProvider>();

    if (_allScreens.isEmpty || userScope.branchId != _lastKnownBranchId) {
      _lastKnownBranchId = userScope.branchId;

      // Initialize the badge stream
      badgeProvider.initializeStream(userScope);

      // Initialize screens
      _allScreens = {
        AppTab.dashboard: AppScreen(
          tab: AppTab.dashboard,
          permissionKey: Permissions.canViewDashboard,
          screen: DashboardScreen(onTabChange: _onTabChange),
          navItem: const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
        ),
        AppTab.inventory: AppScreen(
          tab: AppTab.inventory,
          permissionKey: Permissions.canManageInventory,
          screen: const InventoryScreen(),
          navItem: const BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2),
            label: 'Inventory',
          ),
        ),
        AppTab.orders: AppScreen(
          tab: AppTab.orders,
          permissionKey: Permissions.canManageOrders,
          screen:  OrdersScreen(),
          navItem: const BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
        ),
        AppTab.manualAssignment: AppScreen(
          tab: AppTab.manualAssignment,
          permissionKey: Permissions.canManageManualAssignment,
          screen: const ManualAssignmentScreen(),
          navItem: BottomNavigationBarItem(
            icon: ManualAssignmentBadge(isActive: false),
            activeIcon: ManualAssignmentBadge(isActive: true),
            label: 'Assign Rider',
          ),
        ),
        AppTab.riders: AppScreen(
          tab: AppTab.riders,
          permissionKey: Permissions.canManageRiders,
          screen: const RidersScreen(),
          navItem: const BottomNavigationBarItem(
            icon: Icon(Icons.delivery_dining_outlined),
            activeIcon: Icon(Icons.delivery_dining),
            label: 'Riders',
          ),
        ),
      };

      _buildNavItems();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _initializeRestaurantStatus();
        }
      });
    }
  }


  void _initializeRestaurantStatus() {
    // This context is safe to use now
    // We use context.read() because this is a one-time call.
    final scopeService = context.read<UserScopeService>();
    final statusService = context.read<RestaurantStatusService>();

    if (scopeService.branchId.isNotEmpty && !_isRestaurantStatusInitialized) {
      String restaurantName = "Branch ${scopeService.branchId}";
      if (scopeService.userEmail.isNotEmpty) {
        restaurantName =
        "Restaurant (${scopeService.userEmail.split('@').first})";
      }

      statusService.initialize(scopeService.branchId,
          restaurantName: restaurantName);
      _isRestaurantStatusInitialized = true;
    }
  }

  Widget _buildRestaurantToggle(RestaurantStatusService statusService) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (statusService.isLoading)
          Container(
            width: 50,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          Switch(
            value: statusService.isOpen,
            onChanged: (newValue) {
              _showStatusChangeConfirmation(newValue);
            },
            activeColor: Colors.green,
            activeTrackColor: Colors.green[100],
            inactiveThumbColor: Colors.red,
            inactiveTrackColor: Colors.red[100],
          ),
      ],
    );
  }

  void _showStatusChangeConfirmation(bool newValue) {
    final statusService = context.read<RestaurantStatusService>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              newValue ? Icons.storefront : Icons.storefront_outlined,
              color: newValue ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 12),
            Text(
              newValue ? 'Open Restaurant?' : 'Close Restaurant?',
              style: TextStyle(
                color: newValue ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          newValue
              ? 'The restaurant will be opened for business. New orders will be accepted and notifications will be enabled.'
              : 'The restaurant will be closed. No new orders will be accepted and background services will be stopped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await statusService.toggleRestaurantStatus(newValue);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        newValue
                            ? '✅ Restaurant is now OPEN - Background service started'
                            : '🛑 Restaurant is now CLOSED - Background service stopped',
                      ),
                      backgroundColor: newValue ? Colors.green : Colors.red,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Failed to update restaurant status: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: newValue ? Colors.green : Colors.red,
            ),
            child: Text(
              newValue ? 'Open Restaurant' : 'Close Restaurant',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _buildNavItems() {
    if (_isBuildingNavItems) return;
    _isBuildingNavItems = true;

    // We use context.read() here because the containing function
    // (didChangeDependencies) is already reacting to changes.
    final userScope = context.read<UserScopeService>();
    final List<AppScreen> allowedScreens = [];

    if (userScope.can(Permissions.canViewDashboard)) {
      allowedScreens.add(_allScreens[AppTab.dashboard]!);
    }
    if (userScope.can(Permissions.canManageInventory)) {
      allowedScreens.add(_allScreens[AppTab.inventory]!);
    }
    if (userScope.can(Permissions.canManageOrders)) {
      allowedScreens.add(_allScreens[AppTab.orders]!);
    }
    if (userScope.can(Permissions.canManageManualAssignment)) {
      allowedScreens.add(_allScreens[AppTab.manualAssignment]!);
    }
    if (userScope.can(Permissions.canManageRiders)) {
      allowedScreens.add(_allScreens[AppTab.riders]!);
    }

    if (mounted) {
      setState(() {
        _screens = allowedScreens.map((s) => s.screen).toList();
        _navItems = allowedScreens.map((s) => s.navItem).toList();
        if (_currentIndex >= _screens.length) {
          _currentIndex = 0;
        }
        _isBuildingNavItems = false;
      });
    }
  }

  @override
  void dispose() {
    debugPrint('🛑 HomeScreen disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // We watch userScope and statusService here to rebuild the AppBar
    // when their values change.
    final userScope = context.watch<UserScopeService>();
    final statusService = context.watch<RestaurantStatusService>();
    final String appBarTitle = userScope.isSuperAdmin
        ? 'Super Admin'
        : userScope.branchId.isNotEmpty
        ? userScope.branchId.replaceAll('_', ' ')
        : 'Admin Panel';

    // If nav items are empty, it means the first didChangeDependencies
    // hasn't completed. Show a loader.
    if (_navItems.isEmpty || _screens.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_currentIndex >= _screens.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusService.isOpen
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusService.isOpen ? Colors.green : Colors.red,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    statusService.isOpen ? 'OPEN' : 'CLOSED',
                    style: TextStyle(
                      color: statusService.isOpen ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildRestaurantToggle(statusService),
                const SizedBox(width: 8),
              ],
            ),
          ),
          if (userScope.can(Permissions.canManageSettings))
            IconButton(
              tooltip: 'Settings',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              icon: Icon(
                Icons.settings_rounded,
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      ),
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: _navItems,
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey[600],
        showUnselectedLabels: true,
        selectedFontSize: 12,
        unselectedFontSize: 12,
      ),
    );
  }
}

// --- Dedicated stateful widget for the badge ---

/// A dedicated widget to display the manual assignment icon and badge.
/// This isolates the Firestore stream from the parent screen's build cycle,
/// preventing flickering and unnecessary rebuilds.
class ManualAssignmentBadge extends StatelessWidget {
  final bool isActive;
  const ManualAssignmentBadge({super.key, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    final count = context.watch<BadgeCountProvider>().manualAssignmentCount;

    debugPrint('ManualAssignmentBadge building with count: $count');

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          isActive ? Icons.person_pin_circle : Icons.person_pin_circle_outlined,
          color: isActive ? Colors.deepPurple : Colors.grey[600],
        ),
        if (count > 0)
          Positioned(
            top: -4,
            right: -8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              child: Text(
                count > 9 ? '9+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class BadgeCountProvider with ChangeNotifier {
  int _manualAssignmentCount = 0;
  int get manualAssignmentCount => _manualAssignmentCount;

  StreamSubscription<QuerySnapshot>? _subscription;
  String? _currentBranchId;

  void initializeStream(UserScopeService userScope) {
    final branchId = userScope.isSuperAdmin ? null : userScope.branchId;

    // Only reinitialize if branch changed
    if (_currentBranchId == branchId && _subscription != null) return;

    _currentBranchId = branchId;
    _subscription?.cancel();

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    Query query = FirebaseFirestore.instance
        .collection('Orders')
        .where('status', isEqualTo: 'needs_rider_assignment')
    // --- FIX: Query on 'timestamp' instead of 'needsAssignmentAt' ---
        .where('timestamp', isGreaterThanOrEqualTo: startOfToday)
        .where('timestamp', isLessThan: endOfToday);

    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: branchId);
    }

    _subscription = query.snapshots().listen((snapshot) {
      final newCount = snapshot.docs.length;

      // --- FIX: Only notify if the count has actually changed ---
      if (newCount != _manualAssignmentCount) {
        debugPrint('BadgeCountProvider: Count updated from $_manualAssignmentCount to $newCount');
        _manualAssignmentCount = newCount;
        notifyListeners();
      }
      // --- End of FIX ---

    }, onError: (error) {
      debugPrint('BadgeCountProvider stream error: $error');
      // Optional: Reset count to 0 on error
      if (_manualAssignmentCount != 0) {
        _manualAssignmentCount = 0;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}