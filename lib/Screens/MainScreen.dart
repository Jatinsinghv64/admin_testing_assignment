
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Widgets/RestaurantStatusService.dart';
import '../Widgets/ScopeLoader.dart';
import '../main.dart';
import 'DashboardScreen.dart';
import 'MenuManagement.dart';
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
  late Map<AppTab, AppScreen> _allScreens;

  // Restaurant status
  bool _isRestaurantStatusInitialized = false;
  bool _isBuildingNavItems = false;

  // Callback method for tab changes from Dashboard
  void _onTabChange(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();

    // ... (Your _allScreens map initialization is correct) ...
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
        screen: const OrdersScreen(),
        navItem: const BottomNavigationBarItem(
          icon: Icon(Icons.receipt_long_outlined),
          activeIcon: Icon(Icons.receipt_long),
          label: 'Orders',
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


    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buildNavItems();
      // ❌ REMOVED: _listenToBackgroundService();
      // This logic is now correctly in OrderNotificationService
      _initializeRestaurantStatus();
    });
  }

  void _initializeRestaurantStatus() {
    // ... (This function is correct, no changes needed) ...
    final scopeService = context.read<UserScopeService>();
    final statusService = context.read<RestaurantStatusService>();

    if (scopeService.branchId.isNotEmpty && !_isRestaurantStatusInitialized) {
      String restaurantName = "Branch ${scopeService.branchId}";
      if (scopeService.userEmail.isNotEmpty) {
        restaurantName = "Restaurant (${scopeService.userEmail.split('@').first})";
      }

      statusService.initialize(scopeService.branchId, restaurantName: restaurantName);
      _isRestaurantStatusInitialized = true;
    }
  }

  // ❌ REMOVED: _listenToBackgroundService()
  // ❌ REMOVED: _showInAppOrderDialog()
  // ❌ REMOVED: _handleOrderAcceptance()
  // ❌ REMOVED: _updateOrderStatus()

  // ✅ KEPT: All functions for Restaurant Status Toggle
  Widget _buildRestaurantToggle(RestaurantStatusService statusService) {
    // ... (This function is correct, no changes needed) ...
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
    // ... (This function is correct, no changes needed) ...
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
    // ... (This function is correct, no changes needed) ...
    if (_isBuildingNavItems) return;
    _isBuildingNavItems = true;

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
    if (userScope.can(Permissions.canManageRiders)) {
      allowedScreens.add(_allScreens[AppTab.riders]!);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    });
  }


  @override
  void didChangeDependencies() {
    // ... (This function is correct, no changes needed) ...
    super.didChangeDependencies();

    final userScope = context.watch<UserScopeService>();
    if (!_isBuildingNavItems) {
      _buildNavItems();
    }

    if (!_isRestaurantStatusInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeRestaurantStatus();
      });
    }
  }


  @override
  void dispose() {
    // ❌ REMOVED: _backgroundServiceSubscription?.cancel();
    // ❌ REMOVED: _processedOrderIds.clear();
    debugPrint('🛑 HomeScreen disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ... (This function is correct, no changes needed) ...
    final userScope = context.watch<UserScopeService>();
    final statusService = context.watch<RestaurantStatusService>();
    final String appBarTitle = userScope.isSuperAdmin
        ? 'Super Admin'
        : userScope.branchId.isNotEmpty
        ? userScope.branchId.replaceAll('_', ' ')
        : 'Admin Panel';

    if (_screens.isEmpty || _navItems.isEmpty) {
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusService.isOpen ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
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
      ),
    );
  }
}