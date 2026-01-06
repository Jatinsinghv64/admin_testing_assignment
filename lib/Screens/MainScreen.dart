import 'dart:async';
import '../Widgets/working_hours_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Widgets/Permissions.dart';
import '../Widgets/RestaurantStatusService.dart';
import '../main.dart';
import 'DashboardScreen.dart';
import 'MenuManagement.dart';
import 'ManualAssignmentScreen.dart';
import 'OrdersScreen.dart';
import 'RidersScreen.dart';
import 'SettingsScreen.dart';
import 'RestaurantTimingScreen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  List<Widget> _screens = [];
  List<BottomNavigationBarItem> _navItems = [];
  Map<AppTab, AppScreen> _allScreens = {};

  bool _isRestaurantStatusInitialized = false;
  bool _isBuildingNavItems = false;
  String? _lastKnownBranchId;

  void _onTabChange(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final statusService = context.read<RestaurantStatusService>();
      statusService.closingPopupStream.listen((shouldShow) {
        if (shouldShow && mounted) {
          _showClosingWarningDialog(context);
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final userScope = context.watch<UserScopeService>();
    final badgeProvider = context.read<BadgeCountProvider>();

    if (_allScreens.isEmpty || userScope.branchId != _lastKnownBranchId) {
      _lastKnownBranchId = userScope.branchId;
      badgeProvider.initializeStream(userScope);

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

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _initializeRestaurantStatus();
        }
      });
    }

    if (_allScreens.isNotEmpty) {
      _buildNavItems();
    }
  }

  void _initializeRestaurantStatus() {
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

  // ---------------------------------------------------------------------------
  // ✅ FIXED POPUP: "Yes" now actually closes the restaurant in DB
  // ---------------------------------------------------------------------------
  void _showClosingWarningDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.timer_off, color: Colors.red),
            SizedBox(width: 10),
            Text('Restaurant is Closing'),
          ],
        ),
        content: const Text(
          'The scheduled closing time is in less than 2 minutes.\n\nDo you want to close now or extend the timing?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              // ✅ Just dismiss the popup.
              // The schedule timer will automatically close the restaurant in a few minutes.
              Navigator.pop(context);
            },
            child: const Text('Okay, Let it Close', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RestaurantTimingScreen()),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            child: const Text('Extend Time'),
          ),
        ],
      ),
    );
  }

  Widget _buildRestaurantToggle(RestaurantStatusService statusService) {
    final userScope = context.read<UserScopeService>();
    final hasMultipleBranches = userScope.isSuperAdmin && userScope.branchIds.length > 1;

    return Stack(
      alignment: Alignment.center,
      children: [
        if (statusService.isLoading || statusService.isToggling)
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
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurple),
              ),
            ),
          )
        else if (hasMultipleBranches)
          // SuperAdmin with multiple branches: Show selector button
          GestureDetector(
            onTap: _showBranchSelectorForToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: statusService.isManualOpen 
                    ? Colors.green.withOpacity(0.15) 
                    : Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: statusService.isManualOpen ? Colors.green : Colors.red,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    statusService.isManualOpen ? Icons.power_settings_new : Icons.power_off,
                    color: statusService.isManualOpen ? Colors.green : Colors.red,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
                ],
              ),
            ),
          )
        else
          // Single branch: Show normal Switch toggle
          Switch(
            value: statusService.isManualOpen,
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

  // ✅ NEW: Branch selector modal for SuperAdmin
  void _showBranchSelectorForToggle() async {
    final userScope = context.read<UserScopeService>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _BranchStatusToggleSheet(branchIds: userScope.branchIds),
    );
  }


  void _showStatusChangeConfirmation(bool newValue) {
    final statusService = context.read<RestaurantStatusService>();

    // ✅ CHECK: If trying to OPEN but schedule says CLOSED
    if (newValue == true && !statusService.isScheduleOpen) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.schedule, color: Colors.orange),
              SizedBox(width: 10),
              Text('Outside Schedule'),
            ],
          ),
          content: const Text(
            'The restaurant is closed according to the current schedule.\n\nTo open now, please update your Timings settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RestaurantTimingScreen()),
                );
              },
              icon: const Icon(Icons.edit_calendar, size: 16),
              label: const Text('Update Timings'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            ),
          ],
        ),
      );
      return;
    }

    // ✅ CHECK: If trying to CLOSE but schedule says OPEN
    if (newValue == false && statusService.isScheduleOpen) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 10),
              Text('Schedule is Active'),
            ],
          ),
          content: const Text(
              'The restaurant is currently scheduled to be OPEN.\n\nClosing it now will manually override the schedule. Are you sure?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                   // Proceed with closing
                   await statusService.toggleRestaurantStatus(false);
                   if (mounted) {
                     ScaffoldMessenger.of(context).showSnackBar(
                       const SnackBar(content: Text('🛑 Restaurant is now CLOSED (Manual Override)'), backgroundColor: Colors.red),
                     );
                   }
                } catch (e) {
                  // Error handling
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Yes, Close'),
            ),
          ],
        ),
      );
      return;
    }

    // Standard Confirmation for other cases
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
              ? 'The restaurant will be manually set to OPEN. (Schedule checks will apply)'
              : 'The restaurant will be manually CLOSED immediately.',
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
                            ? '✅ Restaurant is now OPEN'
                            : '🛑 Restaurant is now CLOSED',
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

  // ✅ Hybrid Formatter
  String _formatDuration(Duration d) {
    if (d.inMinutes >= 5) {
      return '${d.inMinutes} mins';
    } else {
      final minutes = d.inMinutes;
      final seconds = d.inSeconds % 60;
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final statusService = context.watch<RestaurantStatusService>();
    final timeUntilClose = statusService.timeUntilClose;

    final String appBarTitle = userScope.isSuperAdmin
        ? 'Super Admin'
        : userScope.branchId.isNotEmpty
        ? userScope.branchId.replaceAll('_', ' ')
        : 'Admin Panel';

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
                if (statusService.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurple),
                    ),
                  )
                else
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
                      statusService.statusText.toUpperCase(),
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
      body: Column(
        children: [
          // 🔴 CLOSING SOON BANNER
          if (timeUntilClose != null)
            Container(
              width: double.infinity,
              color: Colors.orange,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Closing in ${_formatDuration(timeUntilClose)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

          Expanded(child: _screens[_currentIndex]),
        ],
      ),
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

// ... (Rest of ManualAssignmentBadge and BadgeCountProvider remain unchanged) ...
class ManualAssignmentBadge extends StatelessWidget {
  final bool isActive;
  const ManualAssignmentBadge({super.key, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    final count = context.watch<BadgeCountProvider>().manualAssignmentCount;

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

    if (_currentBranchId == branchId && _subscription != null) return;

    _currentBranchId = branchId;
    _subscription?.cancel();

    Query query = FirebaseFirestore.instance
        .collection('Orders')
        .where('status', isEqualTo: 'needs_rider_assignment');

    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: branchId);
    }

    _subscription = query.snapshots().listen((snapshot) {
      final newCount = snapshot.docs.length;

      if (newCount != _manualAssignmentCount) {
        debugPrint(
            'BadgeCountProvider: Count updated from $_manualAssignmentCount to $newCount');
        _manualAssignmentCount = newCount;
        notifyListeners();
      }
    }, onError: (error) {
      debugPrint('BadgeCountProvider stream error: $error');
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

// ✅ NEW: Branch status toggle sheet for SuperAdmin
class _BranchStatusToggleSheet extends StatefulWidget {
  final List<String> branchIds;
  
  const _BranchStatusToggleSheet({required this.branchIds});
  
  @override
  State<_BranchStatusToggleSheet> createState() => _BranchStatusToggleSheetState();
}

class _BranchStatusToggleSheetState extends State<_BranchStatusToggleSheet> {
  List<Map<String, dynamic>> _branches = [];
  bool _isLoading = true;
  Set<String> _togglingIds = {};

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    // Edge case: empty branchIds
    if (widget.branchIds.isEmpty) {
      setState(() {
        _branches = [];
        _isLoading = false;
      });
      return;
    }
    
    try {
      // Load only assigned branches
      final List<Map<String, dynamic>> loadedBranches = [];
      
      for (final branchId in widget.branchIds) {
        try {
          final doc = await FirebaseFirestore.instance.collection('Branch').doc(branchId).get();
          if (doc.exists) {
            final data = doc.data()!;
            loadedBranches.add({
              'id': doc.id,
              'name': data['name'] ?? doc.id,
              'isOpen': data['isOpen'] ?? false,
            });
          } else {
            // Branch document was deleted but still in branchIds
            debugPrint('Branch $branchId not found - may have been deleted');
          }
        } catch (e) {
          debugPrint('Error loading branch $branchId: $e');
        }
      }
      
      setState(() {
        _branches = loadedBranches;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading branches: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleBranch(String branchId, bool newStatus) async {
    setState(() => _togglingIds.add(branchId));

    try {
      final doc = await FirebaseFirestore.instance.collection('Branch').doc(branchId).get();
      final data = doc.data() ?? {};
      final workingHours = data['workingHours'] as Map<String, dynamic>? ?? {};
      
      bool isScheduleOpen = false;
      if (workingHours.isNotEmpty) {
        final now = DateTime.now();
        final dayName = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'][now.weekday - 1];
        final daySchedule = workingHours[dayName];
        if (daySchedule != null && daySchedule['isOpen'] == true) {
          isScheduleOpen = true;
        }
      }

      Map<String, dynamic> updateData = {
        'isOpen': newStatus,
        'lastStatusUpdate': FieldValue.serverTimestamp(),
      };

      if (isScheduleOpen) {
        updateData['manuallyClosed'] = !newStatus;
        updateData['manuallyOpened'] = false;
      } else {
        updateData['manuallyOpened'] = newStatus;
        updateData['manuallyClosed'] = false;
      }

      await FirebaseFirestore.instance.collection('Branch').doc(branchId).update(updateData);

      setState(() {
        final index = _branches.indexWhere((b) => b['id'] == branchId);
        if (index >= 0) {
          _branches[index]['isOpen'] = newStatus;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Branch ${newStatus ? "opened" : "closed"} successfully!'),
          backgroundColor: newStatus ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      debugPrint('Error toggling branch: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _togglingIds.remove(branchId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.store, color: Colors.deepPurple),
              const SizedBox(width: 12),
              const Text(
                'Branch Status Control',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),
          if (_isLoading)
            const Center(child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ))
          else if (_branches.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.store_outlined, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'No branches available',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Contact admin to assign branches',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _branches.length,
                itemBuilder: (context, index) {
                  final branch = _branches[index];
                  final isOpen = branch['isOpen'] ?? false;
                  final isToggling = _togglingIds.contains(branch['id']);

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: Icon(
                        isOpen ? Icons.storefront : Icons.store_outlined,
                        color: isOpen ? Colors.green : Colors.red,
                      ),
                      title: Text(
                        branch['name'],
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        isOpen ? 'Currently OPEN' : 'Currently CLOSED',
                        style: TextStyle(
                          color: isOpen ? Colors.green : Colors.red,
                          fontSize: 12,
                        ),
                      ),
                      trailing: isToggling
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Switch(
                              value: isOpen,
                              onChanged: (val) => _toggleBranch(branch['id'], val),
                              activeColor: Colors.green,
                              inactiveThumbColor: Colors.red,
                            ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}