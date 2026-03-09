import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../Widgets/AccessDeniedWidget.dart';
import '../Widgets/Authorization.dart';
import '../Widgets/Permissions.dart';
import '../Widgets/notification.dart';
import '../Widgets/BranchFilterService.dart';
import '../Widgets/RestaurantStatusService.dart';
import '../utils/responsive_helper.dart'; // ✅ Added
import '../main.dart';
import '../services/DashboardThemeService.dart'; // ✅ Added
import 'AnalyticsScreen.dart';
import 'BranchManagement.dart';
import 'PromoSettingsScreen.dart';
import 'OrderHistory.dart';
import 'RestaurantTimingScreen.dart';
import 'StaffManagementScreen.dart'; // ✅ Added
import 'SettingsScreenLarge.dart'; // ✅ Added
import 'TableManagement.dart';
import 'settings/IngredientsAndRecipesScreen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // State to track logout process
  bool _isLoggingOut = false;

  // Cache permission state to prevent flash during scope reload
  bool? _hadPermissionOnInit;

  late OrderNotificationService _notificationService;

  @override
  void initState() {
    super.initState();
    _notificationService = context.read<OrderNotificationService>();
    // Load branch names immediately when settings screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userScope = context.read<UserScopeService>();
      final branchFilter = context.read<BranchFilterService>();
      if (userScope.branchIds.isNotEmpty) {
        branchFilter.loadBranchNames(userScope.branchIds);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // ✅ RESPONSIVE CHECK
    if (ResponsiveHelper.isDesktop(context)) {
      return const SettingsScreenLarge();
    }

    // Check if logging out FIRST to prevent Access Denied flicker
    if (_isLoggingOut) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.deepPurple),
              SizedBox(height: 16),
              Text("Signing out...", style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final userScope = context.watch<UserScopeService>();
    final authService = context.read<AuthService>();
    // Listen to branch filter changes to rebuild when names are loaded
    final branchFilter = context.watch<BranchFilterService>();

    // Cache permission state when first loaded
    if (_hadPermissionOnInit == null && userScope.isLoaded) {
      _hadPermissionOnInit = userScope.can(Permissions.canManageSettings);
    }

    // Show loading while scope is loading/reloading
    if (!userScope.isLoaded) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          centerTitle: true,
          title: const Text(
            'Settings',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
              fontSize: 24,
            ),
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.deepPurple),
              SizedBox(height: 16),
              Text('Loading...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    // Permission check - with flash prevention
    if (!userScope.can(Permissions.canManageSettings)) {
      // If we had permission before, show loading instead of Access Denied
      if (_hadPermissionOnInit == true) {
        return Scaffold(
          backgroundColor: Colors.grey[50],
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.white,
            centerTitle: true,
            title: const Text(
              'Settings',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
                fontSize: 24,
              ),
            ),
          ),
          body: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.deepPurple),
                SizedBox(height: 16),
                Text('Refreshing...', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        );
      }
      return const Scaffold(
        body: AccessDeniedWidget(permission: 'manage settings'),
      );
    }

    // Update cached permission state
    _hadPermissionOnInit = true;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 24,
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Card
                _buildProfileCard(userScope, authService),
                const SizedBox(height: 24),

                // Administration Section
                if (userScope.isSuperAdmin ||
                    userScope.can(Permissions.canManageCoupons)) ...[
                  _buildSectionTitle(
                    'Administration',
                    Icons.admin_panel_settings,
                  ),
                  const SizedBox(height: 12),
                  _buildGroupedSettingsCard([
                    if (userScope.isSuperAdmin)
                      _SettingsItem(
                        icon: Icons.access_time_rounded,
                        title: 'Restaurant Timings',
                        subtitle: 'Manage opening hours',
                        iconColor: Colors.orange,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                const RestaurantTimingScreen(),
                          ),
                        ),
                      ),
                    if (userScope.isSuperAdmin ||
                        userScope.role == 'branchadmin')
                      _SettingsItem(
                        icon: Icons.history_edu_rounded,
                        title: 'Order History',
                        subtitle: 'View past orders',
                        iconColor: Colors.blue,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const OrderHistoryScreen(),
                          ),
                        ),
                      ),
                    // Staff Management - Super Admin only
                    if (userScope.isSuperAdmin)
                      _SettingsItem(
                        icon: Icons.people_alt,
                        title: 'Staff Management',
                        subtitle: 'Manage team members',
                        iconColor: Colors.deepPurple,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const StaffManagementScreen(),
                          ),
                        ),
                      ),
                    if (userScope.can(Permissions.canManageCoupons))
                      _SettingsItem(
                        icon: Icons.local_offer_rounded,
                        title: 'Promotions & Deals',
                        subtitle: 'Coupons, Combos & Sales',
                        iconColor: Colors.pink,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const PromoSettingsScreen(),
                          ),
                        ),
                      ),
                    // Branch Settings - Super Admin only
                    if (userScope.isSuperAdmin)
                      _SettingsItem(
                        icon: Icons.business_outlined,
                        title: 'Branch Settings',
                        subtitle: 'Manage branches',
                        iconColor: Colors.indigo,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                const BranchManagementScreen(),
                          ),
                        ),
                      ),
                    if (userScope.isSuperAdmin ||
                        userScope.role == 'branch_admin')
                      _SettingsItem(
                        icon: Icons.table_restaurant_rounded,
                        title: 'Table Management',
                        subtitle: 'Manage restaurant tables',
                        iconColor: Colors.teal,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const TableManagementScreen(),
                          ),
                        ),
                      ),
                    if (userScope.isSuperAdmin)
                      _SettingsItem(
                        icon: Icons.analytics_outlined,
                        title: 'Business Analytics',
                        subtitle: 'View reports & insights',
                        iconColor: Colors.green,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const AnalyticsScreen(),
                          ),
                        ),
                      ),
                    if (userScope.isSuperAdmin)
                      _SettingsItem(
                        icon: Icons.blender_outlined,
                        title: 'Ingredients & Recipes',
                        subtitle: 'Manage ingredients, costs & recipes',
                        iconColor: Colors.deepOrange,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                const IngredientsAndRecipesScreen(),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 24),
                ],

                // App Preferences Section - Only Notifications
                _buildSectionTitle('App Preferences', Icons.tune_rounded),
                const SizedBox(height: 12),
                _buildGroupedSettingsCard([
                  _SettingsItem(
                    icon: context.watch<DashboardThemeService>().isDarkMode 
                        ? Icons.dark_mode_rounded 
                        : Icons.light_mode_rounded,
                    title: 'Dashboard Appearance',
                    subtitle: 'Toggle dark mode',
                    iconColor: Colors.amber,
                    onTap: () {}, // Handled by trailing switch
                    trailing: Switch(
                      value: context.watch<DashboardThemeService>().isDarkMode,
                      onChanged: (value) {
                        context.read<DashboardThemeService>().toggleDarkMode();
                      },
                      activeColor: Colors.deepPurple,
                    ),
                  ),
                  _SettingsItem(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    subtitle: 'Push alerts & sounds',
                    iconColor: Colors.red,
                    onTap: () => _showNotificationSettings(context),
                  ),
                ]),
                const SizedBox(height: 32),

                // Logout Button
                _buildLogoutButton(authService),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(
    UserScopeService userScope,
    AuthService authService,
  ) {
    // ✅ Support both email and phone users for initials
    final identifier = userScope.userEmail.isNotEmpty
        ? userScope.userEmail
        : userScope.userIdentifier;
    final initials =
        identifier.isNotEmpty ? identifier.substring(0, 2).toUpperCase() : 'U';

    // Get branch names
    final branchFilter = context.read<BranchFilterService>();
    String branchText = '';

    if (userScope.branchIds.isEmpty) {
      branchText = 'No Branch Assigned';
    } else if (userScope.branchIds.length == 1) {
      branchText = branchFilter.getBranchName(userScope.branchIds.first);
    } else {
      // Multiple branches
      final names = userScope.branchIds
          .map((id) => branchFilter.getBranchName(id))
          .toList();
      if (names.length > 2) {
        branchText = '${names.take(2).join(", ")} +${names.length - 2} more';
      } else {
        branchText = names.join(", ");
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.deepPurple.shade50, Colors.white],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.deepPurple.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C4DFF), Colors.deepPurple],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.deepPurple.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ Display email or phone number
                Text(
                  userScope.userEmail.isNotEmpty
                      ? userScope.userEmail
                      : userScope.userIdentifier,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getRoleColor(userScope.role).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _formatRole(userScope.role),
                    style: TextStyle(
                      color: _getRoleColor(userScope.role),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (userScope.branchIds.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.store, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          branchText,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Edit button - navigates to Staff Management
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const StaffManagementScreen(),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.edit_outlined,
                size: 20,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'super_admin':
        return Colors.deepPurple;
      case 'branch_admin':
        return Colors.blue;
      case 'manager':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _formatRole(String role) {
    return role
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) => word.isNotEmpty
              ? '${word[0].toUpperCase()}${word.substring(1)}'
              : '',
        )
        .join(' ');
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.deepPurple, size: 18),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildGroupedSettingsCard(List<_SettingsItem> items) {
    // Filter out null items
    final validItems = items.where((item) => true).toList();
    if (validItems.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: validItems.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isLast = index == validItems.length - 1;

          return Column(
            children: [
              _buildSettingsRow(item),
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 72,
                  endIndent: 16,
                  color: Colors.grey[200],
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSettingsRow(_SettingsItem item) {
    return InkWell(
      onTap: item.trailing != null ? null : item.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: item.iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: item.iconColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            if (item.trailing != null)
              item.trailing!
            else
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey[400],
                size: 22,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton(AuthService authService) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showLogoutDialog(context, authService),
          borderRadius: BorderRadius.circular(16),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout_rounded, color: Colors.white, size: 22),
                SizedBox(width: 12),
                Text(
                  'Sign Out',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _SettingsCard({required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(padding: const EdgeInsets.all(16.0), child: child),
    );
  }

  Widget buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.deepPurple, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
      ],
    );
  }

  Widget buildSettingsCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    Color? cardColor,
  }) {
    final effectiveIconColor = iconColor ?? Colors.deepPurple;
    final effectiveCardColor = cardColor ?? Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: effectiveCardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: effectiveIconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: effectiveIconColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Notification Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NotificationSettingItem(
                  title: 'Play Sound on Order',
                  subtitle: 'Play a sound for new orders',
                  value: _notificationService.playSound,
                  onChanged: (value) {
                    _notificationService.setPlaySound(value);
                    setState(() {});
                  },
                ),
                _NotificationSettingItem(
                  title: 'Vibrate on Order',
                  subtitle: 'Vibrate for new orders',
                  value: _notificationService.vibrate,
                  onChanged: (value) {
                    _notificationService.setVibrate(value);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ FIXED LOGOUT FUNCTION
  void _showLogoutDialog(BuildContext context, AuthService authService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              authService.signOut();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

class _NotificationSettingItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _NotificationSettingItem({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Colors.deepPurple,
      ),
    );
  }
}

// ✅ NEW: SuperAdmin-aware status card with branch selector
class _SuperAdminStatusCard extends StatefulWidget {
  final UserScopeService userScope;

  const _SuperAdminStatusCard({required this.userScope});

  @override
  State<_SuperAdminStatusCard> createState() => _SuperAdminStatusCardState();
}

class _SuperAdminStatusCardState extends State<_SuperAdminStatusCard> {
  List<Map<String, dynamic>> _branches = [];
  String? _selectedBranchId;
  bool _isLoading = true;
  bool _isToggling = false;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      // Check if SuperAdmin has multiple branches assigned
      final hasMultipleBranches = widget.userScope.isSuperAdmin &&
          widget.userScope.branchIds.length > 1;

      if (hasMultipleBranches) {
        // SuperAdmin with multiple branches - load only their assigned branches
        final branchIds = widget.userScope.branchIds;
        final List<Map<String, dynamic>> loadedBranches = [];

        for (final branchId in branchIds) {
          final doc = await FirebaseFirestore.instance
              .collection('Branch')
              .doc(branchId)
              .get();
          if (doc.exists) {
            final data = doc.data()!;
            loadedBranches.add({
              'id': doc.id,
              'name': data['name'] ?? doc.id,
              'isOpen': data['isOpen'] ?? false,
            });
          }
        }

        setState(() {
          _branches = loadedBranches;
          if (_branches.isNotEmpty) {
            _selectedBranchId = _branches.first['id'];
            _isOpen = _branches.first['isOpen'] ?? false;
          }
          _isLoading = false;
        });
      } else {
        // Regular admin OR SuperAdmin with single branch - use their primary branch
        _selectedBranchId = widget.userScope.branchIds.isNotEmpty ? widget.userScope.branchIds.first : null;
        final doc = await FirebaseFirestore.instance
            .collection('Branch')
            .doc(_selectedBranchId)
            .get();
        setState(() {
          _branches = [
            {
              'id': doc.id,
              'name': doc.data()?['name'] ?? doc.id,
              'isOpen': doc.data()?['isOpen'] ?? false,
            },
          ];
          _isOpen = doc.data()?['isOpen'] ?? false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading branches: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleStatus(bool newStatus) async {
    if (_selectedBranchId == null) return;

    setState(() => _isToggling = true);

    try {
      // Use centralized helper for accurate timezone-aware schedule check
      final scheduleStatus =
          await RestaurantStatusService.checkBranchScheduleStatus(
        _selectedBranchId!,
      );
      final isScheduleOpen = scheduleStatus['isScheduleOpen'] as bool;

      // CHECK: If trying to OPEN but schedule says CLOSED - show dialog
      if (newStatus == true && !isScheduleOpen) {
        setState(() => _isToggling = false);
        if (!mounted) return;

        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
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
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RestaurantTimingScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.edit_calendar, size: 16),
                label: const Text('Update Timings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                ),
              ),
            ],
          ),
        );
        return;
      }

      // CHECK: If trying to CLOSE but schedule says OPEN - show confirmation
      if (newStatus == false && isScheduleOpen) {
        setState(() => _isToggling = false);
        if (!mounted) return;

        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 10),
                Text('Schedule is Active'),
              ],
            ),
            content: const Text(
              'The restaurant is currently scheduled to be OPEN.\n\nClosing it now will manually override the schedule. Are you sure?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _executeToggle(false, isScheduleOpen);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Yes, Close'),
              ),
            ],
          ),
        );
        return;
      }

      // Standard case - execute toggle directly
      await _executeToggle(newStatus, isScheduleOpen);
    } catch (e) {
      debugPrint('Error in toggle status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isToggling = false);
    }
  }

  Future<void> _executeToggle(bool newStatus, bool isScheduleOpen) async {
    setState(() => _isToggling = true);

    try {
      // Use centralized helper to build correct update data
      final updateData = RestaurantStatusService.buildStatusUpdateData(
        newStatus,
        isScheduleOpen,
      );

      await FirebaseFirestore.instance
          .collection('Branch')
          .doc(_selectedBranchId)
          .update(updateData);

      setState(() {
        _isOpen = newStatus;
        // Update local cache
        final index = _branches.indexWhere((b) => b['id'] == _selectedBranchId);
        if (index >= 0) {
          _branches[index]['isOpen'] = newStatus;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Branch ${newStatus ? "opened" : "closed"} successfully!',
            ),
            backgroundColor: newStatus ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error toggling status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isToggling = false);
    }
  }

  void _onBranchChanged(String? branchId) {
    if (branchId == null) return;
    final branch = _branches.firstWhere((b) => b['id'] == branchId);
    setState(() {
      _selectedBranchId = branchId;
      _isOpen = branch['isOpen'] ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isOpen ? Icons.storefront : Icons.no_food_rounded,
                  color: _isOpen ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Restaurant Status',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Branch selector for SuperAdmin
            if (widget.userScope.isSuperAdmin && _branches.length > 1) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedBranchId,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down),
                    items: _branches.map((branch) {
                      final branchIsOpen = branch['isOpen'] ?? false;
                      return DropdownMenuItem<String>(
                        value: branch['id'],
                        child: Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 10,
                              color: branchIsOpen ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(branch['name']),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: _onBranchChanged,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Status toggle
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isOpen
                        ? 'Restaurant is OPEN and accepting orders'
                        : 'Restaurant is CLOSED',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ),
                _isToggling
                    ? const SizedBox(
                        width: 48,
                        height: 24,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : Switch(
                        value: _isOpen,
                        onChanged: _toggleStatus,
                        activeColor: Colors.green,
                        inactiveThumbColor: Colors.red,
                      ),
              ],
            ),
          ],
        ),
      ), // Close Padding
    ); // Close Card
  }
}

// Helper class for grouped settings items
class _SettingsItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    this.onTap,
    this.trailing,
  });
}
