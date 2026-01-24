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
import '../main.dart';
import 'AnalyticsScreen.dart';
import 'BranchManagement.dart';
import 'CouponsScreen.dart';
import 'OrderHistory.dart';
import 'RestaurantTimingScreen.dart';
import 'TableManagement.dart';

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
                      'Administration', Icons.admin_panel_settings),
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
                                  const RestaurantTimingScreen()),
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
                              builder: (context) => const OrderHistoryScreen()),
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
                              builder: (context) =>
                                  const StaffManagementScreen()),
                        ),
                      ),
                    if (userScope.can(Permissions.canManageCoupons))
                      _SettingsItem(
                        icon: Icons.card_giftcard_rounded,
                        title: 'Coupon Management',
                        subtitle: 'Create discount codes',
                        iconColor: Colors.teal,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (context) =>
                                  const CouponManagementScreen()),
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
                                  const BranchManagementScreen()),
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
                              builder: (context) =>
                                  const TableManagementScreen()),
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
                              builder: (context) => const AnalyticsScreen()),
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
      UserScopeService userScope, AuthService authService) {
    // ✅ Support both email and phone users for initials
    final identifier = userScope.userEmail.isNotEmpty 
        ? userScope.userEmail 
        : userScope.userIdentifier;
    final initials = identifier.isNotEmpty
        ? identifier.substring(0, 2).toUpperCase()
        : 'U';
    
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
          colors: [
            Colors.deepPurple.shade50,
            Colors.white,
          ],
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
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
              child: Icon(Icons.edit_outlined, size: 20, color: Colors.grey[600]),
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
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : '')
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
                    color: Colors.grey[200]),
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
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey[400], size: 22),
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
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: child,
      ),
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
                child: Icon(Icons.arrow_forward_ios_rounded,
                    size: 16, color: Colors.grey[600]),
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
        content:
            const Text('Are you sure you want to sign out of your account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // -----------------------------------------------------------
              // ✅ CRITICAL FIX: Capture references BEFORE async gaps.
              // If we don't do this, 'context' might be deactivated/unstable
              // after 'await authService.signOut()', causing the crash.
              // -----------------------------------------------------------
              final navigator = Navigator.of(context);
              final userScope = context.read<UserScopeService>();

              // 1. Close the Dialog
              navigator.pop();

              // 2. Set State to 'logging out' immediately to prevent
              // the "Access Denied" widget from rendering during teardown.
              if (mounted) {
                setState(() {
                  _isLoggingOut = true;
                });
              }

              try {
                // 3. Clear scope first (safe to do since we captured the instance)
                await userScope.clearScope();

                // 4. Sign Out
                await authService.signOut();
              } catch (e) {
                debugPrint("Error during logout: $e");
              } finally {
                // 5. Force Navigate using captured navigator
                // We use pushAndRemoveUntil to clear the entire stack,
                // ensuring the user lands on AuthWrapper/LoginScreen clean.
                navigator.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const AuthWrapper()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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


// -----------------------------------------------------------------------------
// STAFF MANAGEMENT SCREEN (Unchanged from previous fix, included for completeness)
// -----------------------------------------------------------------------------

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Track if we had permission initially (to avoid flash during scope reload)
  bool? _hadPermissionOnInit;

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();

    // Cache the initial permission state
    if (_hadPermissionOnInit == null && userScope.isLoaded) {
      _hadPermissionOnInit =
          userScope.isSuperAdmin && userScope.can(Permissions.canManageStaff);
    }

    // Show loading indicator while scope is loading/reloading
    // This prevents flashing "Access Denied" during state transitions
    if (!userScope.isLoaded) {
      return Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.deepPurple),
          title: const Text(
            'Manage Staff',
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

    // Only show Access Denied if we genuinely don't have permission
    // and it's not just a transitional state
    if (!userScope.isSuperAdmin || !userScope.can(Permissions.canManageStaff)) {
      // If we had permission before and now don't, it might be a reload flash
      // Give it a moment - show loading briefly
      if (_hadPermissionOnInit == true) {
        return Scaffold(
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.deepPurple),
            title: const Text(
              'Manage Staff',
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

      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Text('❌ You do not have permission to manage staff.'),
        ),
      );
    }

    // Update cached permission state
    _hadPermissionOnInit = true;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: !(userScope.branchIds.length > 1), // Center if no selector
        iconTheme: const IconThemeData(color: Colors.deepPurple),
        title: const Text(
          'Manage Staff',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 24,
          ),
        ),
        actions: [
          if (userScope.branchIds.length > 1)
            // Reuse the selector widget logic or extract it.
            // Since it's private in other files, I'll inline a simple version or use a shared widget?
            // Ideally I should have made it a shared widget. I'll duplicate for safety now to avoid wide refactor.
            _buildBranchSelector(userScope, branchFilter),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              tooltip: 'Add New Staff',
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add, color: Colors.deepPurple),
              ),
              onPressed: () => _showAddStaffDialog(userScope.userEmail),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getStaffQuery(userScope, branchFilter),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final staffMembers = snapshot.data?.docs ?? [];

          // Separate list logic
          // 1. Fetch current user data (if not in list, we might need a separate stream,
          // but for now, we scan the list OR rely on the fact that SuperAdmins usually see themselves.
          // BUT if filter excludes me, I am not in `staffMembers`.

          // To guarantee "Me" shows up, we need a separate stream for "Me" if I'm not in the query results?
          // Or just query "Me" always.

          return CustomScrollView(
            slivers: [
              // 1. My Profile Section (Always Visible)
              SliverToBoxAdapter(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: _db
                      .collection('staff')
                      .doc(userScope.userEmail)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || !snapshot.data!.exists)
                      return const SizedBox.shrink();
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      child: _StaffCard(
                        staffId: userScope.userEmail!,
                        data: data,
                        isSelf: true,
                        onEdit: () => _showEditStaffDialog(
                            userScope.userEmail!, data, true),
                      ),
                    );
                  },
                ),
              ),

              // 2. Staff List (Filtered)
              if (staffMembers.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No staff members found matching filter',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final staff = staffMembers[index];
                      // Skip self because it's shown at top
                      if (staff.id == userScope.userEmail)
                        return const SizedBox.shrink();

                      final data = staff.data() as Map<String, dynamic>;
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            child: _StaffCard(
                              staffId: staff.id,
                              data: data,
                              isSelf: false,
                              onEdit: () =>
                                  _showEditStaffDialog(staff.id, data, false),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: staffMembers.length,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showAddStaffDialog(String currentUserEmail) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _StaffEditDialog(
        isEditing: false,
        isSelf: false,
        onSave: (staffData) => _addStaffMember(staffData),
      ),
    );
  }

  void _showEditStaffDialog(
      String staffId, Map<String, dynamic> currentData, bool isSelf) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _StaffEditDialog(
        isEditing: true,
        isSelf: isSelf,
        currentData: currentData,
        onSave: (staffData) => _updateStaffMember(staffId, staffData),
      ),
    );
  }

  Future<void> _addStaffMember(Map<String, dynamic> staffData) async {
    final String email = staffData['email'];

    try {
      final docRef = _db.collection('staff').doc(email);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        if (mounted) {
          _showSnackBar('❌ User with email $email already exists.',
              isError: true);
        }
        return;
      }

      // ✅ IMPROVED: Clean staff document structure
      // FCM tokens are stored in subcollection 'tokens', not at root level
      await docRef.set({
        // Core user info
        'name': staffData['name'],
        'email': email,
        'phone': staffData['phone'] ?? '', // ✅ Include phone
        'role': staffData['role'],
        'isActive': true,

        // Branch assignments
        'branchIds': staffData['branchIds'] ?? [],

        // Permissions
        'permissions': staffData['permissions'] ?? {},

        // Metadata
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': context.read<UserScopeService>().userEmail,
        'lastUpdated': FieldValue.serverTimestamp(),

        // NOTE: FCM tokens are now stored in subcollection 'staff/{email}/tokens'
        // No need to store fcmToken or fcmTokenUpdated at root level
      });

      if (mounted) {
        _showSnackBar('✅ Staff member "$email" added successfully');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error adding staff: $e', isError: true);
      }
    }
  }

  Future<void> _updateStaffMember(
      String staffId, Map<String, dynamic> staffData) async {
    try {
      final userScope = context.read<UserScopeService>();

      // ✅ IMPROVED: Explicitly update only allowed fields, add audit metadata
      await _db.collection('staff').doc(staffId).update({
        'name': staffData['name'],
        'phone': staffData['phone'] ?? '', // ✅ Include phone
        'role': staffData['role'],
        'isActive': staffData['isActive'],
        'branchIds': staffData['branchIds'] ?? [],
        'permissions': staffData['permissions'] ?? {},
        'lastUpdated': FieldValue.serverTimestamp(),
        'lastUpdatedBy': userScope.userEmail,
      });

      if (mounted) {
        _showSnackBar('✅ Staff member "$staffId" updated successfully');
      }
      // Note: No need to manually reload scope - the real-time Firestore listener
      // in UserScopeService automatically updates when the staff document changes
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error updating staff: $e', isError: true);
      }
    }
  }

  // Removed _reloadCurrentUserScope() - the UserScopeService has a real-time
  // Firestore listener that automatically updates when the staff document changes.
  // Manually calling clearScope() + loadUserScope() caused a flash of "Access Denied".

  // ✅ Query definition
  Stream<QuerySnapshot> _getStaffQuery(
      UserScopeService userScope, BranchFilterService branchFilter) {
    Query query = _db.collection('staff');

    // Always filter by branches - SuperAdmin sees only their assigned branches
    final filterBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);
    debugPrint(
        "DEBUG: _getStaffQuery called. FilterBranchIds: $filterBranchIds");

    if (filterBranchIds.isNotEmpty) {
      if (filterBranchIds.length == 1) {
        debugPrint(
            "DEBUG: Using arrayContains for single branch: ${filterBranchIds.first}");
        query = query.where('branchIds', arrayContains: filterBranchIds.first);
      } else {
        debugPrint("DEBUG: Using arrayContainsAny for: $filterBranchIds");
        query = query.where('branchIds', arrayContainsAny: filterBranchIds);
      }
    } else if (userScope.branchIds.isNotEmpty) {
      // Fall back to user's assigned branches
      if (userScope.branchIds.length == 1) {
        query =
            query.where('branchIds', arrayContains: userScope.branchIds.first);
      } else {
        query = query.where('branchIds', arrayContainsAny: userScope.branchIds);
      }
    } else {
      // User with no branches - return impossible query (empty result)
      query =
          query.where(FieldPath.documentId, isEqualTo: 'force_empty_result');
    }

    return query.snapshots();
  }

  // ✅ Branch Selector Widget
  Widget _buildBranchSelector(
      UserScopeService userScope, BranchFilterService branchFilter) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      child: PopupMenuButton<String>(
        offset: const Offset(0, 45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.store, size: 18, color: Colors.deepPurple),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 100),
                child: Text(
                  branchFilter.selectedBranchId == null
                      ? 'All Branches'
                      : branchFilter
                          .getBranchName(branchFilter.selectedBranchId!),
                  style: const TextStyle(
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, color: Colors.deepPurple, size: 20),
            ],
          ),
        ),
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: BranchFilterService.allBranchesValue,
            child: Row(children: [
              Icon(
                  branchFilter.selectedBranchId == null
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 18,
                  color: branchFilter.selectedBranchId == null
                      ? Colors.deepPurple
                      : Colors.grey),
              const SizedBox(width: 10),
              const Text('All Branches'),
            ]),
          ),
          const PopupMenuDivider(),
          ...userScope.branchIds.map((branchId) => PopupMenuItem<String>(
                value: branchId,
                child: Row(children: [
                  Icon(
                      branchFilter.selectedBranchId == branchId
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      size: 18,
                      color: branchFilter.selectedBranchId == branchId
                          ? Colors.deepPurple
                          : Colors.grey),
                  const SizedBox(width: 10),
                  Flexible(
                      child: Text(branchFilter.getBranchName(branchId),
                          overflow: TextOverflow.ellipsis)),
                ]),
              )),
        ],
        onSelected: (value) => branchFilter.selectBranch(value),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  final String staffId;
  final Map<String, dynamic> data;
  final VoidCallback onEdit;
  final bool isSelf;

  const _StaffCard({
    required this.staffId,
    required this.data,
    required this.onEdit,
    required this.isSelf,
  });

  @override
  Widget build(BuildContext context) {
    final String name = data['name'] ?? 'No Name';
    final String email = data['email'] ?? staffId;
    final String role = data['role'] ?? 'No Role';
    final bool isActive = data['isActive'] ?? false;
    final List<dynamic> branchIds = data['branchIds'] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isSelf ? Colors.deepPurple.withOpacity(0.03) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isSelf
            ? Border.all(color: Colors.deepPurple.withOpacity(0.3))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isSelf ? Colors.deepPurple : Colors.grey[300],
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: isSelf ? Colors.white : Colors.grey[700],
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSelf)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'YOU',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.edit_outlined, color: Colors.deepPurple),
                  onPressed: onEdit,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatusBadge(
                    label: _formatRole(role),
                    color: Colors.blue,
                    icon: Icons.security,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatusBadge(
                    label: isActive ? 'Active' : 'Inactive',
                    color: isActive ? Colors.green : Colors.red,
                    icon: isActive ? Icons.check_circle : Icons.cancel,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatusBadge(
                    label: '${branchIds.length} Branches',
                    color: Colors.orange,
                    icon: Icons.store,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatRole(String role) {
    final normalized = role.toLowerCase().replaceAll('_', '');
    if (normalized == 'superadmin') return 'Super Admin';
    if (normalized == 'branchadmin') return 'Branch Admin';
    if (normalized == 'superadmin') return 'Super Admin';
    if (normalized == 'branchadmin') return 'Branch Admin';
    if (normalized == 'server') return 'Server';
    return role.toUpperCase();
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusBadge(
      {required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffEditDialog extends StatefulWidget {
  final bool isEditing;
  final bool isSelf;
  final Map<String, dynamic>? currentData;
  final Function(Map<String, dynamic>) onSave;

  const _StaffEditDialog({
    required this.isEditing,
    required this.isSelf,
    this.currentData,
    required this.onSave,
  });

  @override
  State<_StaffEditDialog> createState() => _StaffEditDialogState();
}

class _StaffEditDialogState extends State<_StaffEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController(); // ✅ NEW

  String _selectedRole = 'branch_admin';
  bool _isActive = true;
  List<String> _selectedBranches = [];

  // Email validation regex
  static final _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  final Map<String, bool> _permissions = {
    'canViewDashboard': true,
    'canManageOrders': true,
    'canManageInventory': false,
    'canManageRiders': false,
    'canManageSettings': false,
    'canManageStaff': false,
    'canManageCoupons': false,
  };

  @override
  void initState() {
    super.initState();
    if (widget.isEditing && widget.currentData != null) {
      _nameController.text = widget.currentData!['name'] ?? '';
      _emailController.text = widget.currentData!['email'] ?? '';
      _phoneController.text = widget.currentData!['phone'] ?? ''; // ✅ NEW

      String rawRole = widget.currentData!['role'] ?? 'branch_admin';
      if (rawRole == 'superadmin') rawRole = 'super_admin';
      if (rawRole == 'branchadmin') rawRole = 'branch_admin';

      if (['super_admin', 'branch_admin', 'server'].contains(rawRole)) {
        _selectedRole = rawRole;
      } else {
        _selectedRole = 'branch_admin';
      }

      _isActive = widget.currentData!['isActive'] ?? true;
      _selectedBranches =
          List<String>.from(widget.currentData!['branchIds'] ?? []);

      final currentPermissions = widget.currentData!['permissions'] ?? {};
      _permissions.forEach((key, value) {
        if (currentPermissions.containsKey(key)) {
          _permissions[key] = currentPermissions[key];
        }
      });
    } else {
      _permissions['canViewDashboard'] = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    widget.isEditing ? Icons.edit_note : Icons.person_add,
                    color: Colors.deepPurple,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.isEditing ? 'Edit Staff' : 'Add New Staff',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration:
                            _inputDecoration('Full Name', Icons.person_outline),
                        validator: (v) =>
                            (v?.trim().isEmpty ?? true) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        enabled: !widget.isEditing,
                        keyboardType: TextInputType.emailAddress,
                        textCapitalization: TextCapitalization.none,
                        autocorrect: false,
                        decoration: _inputDecoration(
                                'Email Address', Icons.email_outlined)
                            .copyWith(
                          filled: widget.isEditing,
                          hintText: 'user@example.com',
                        ),
                        validator: (v) {
                          if (v?.trim().isEmpty ?? true)
                            return 'Email is required';
                          final email = v!.trim().toLowerCase();
                          if (!_emailRegex.hasMatch(email)) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      if (widget.isEditing)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 12),
                          child: Text(
                            'Email cannot be changed after creation.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ),
                      const SizedBox(height: 16),

                      // ✅ NEW: Phone number field
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: _inputDecoration(
                                'Phone Number (Optional)', Icons.phone_outlined)
                            .copyWith(
                          hintText: '+974 XXXX XXXX',
                        ),
                        // Phone is optional, no validator needed
                      ),

                      const SizedBox(height: 24),
                      const Text('Role & Access',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        onChanged: widget.isSelf
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() {
                                    _selectedRole = value;
                                    // If 'server' is selected, clear all permissions by default
                                    if (_selectedRole == 'server') {
                                      for (var key in _permissions.keys) {
                                        _permissions[key] = false;
                                      }
                                    }
                                  });
                                }
                              },
                        decoration:
                            _inputDecoration('Select Role', Icons.security),
                        items: const [
                          DropdownMenuItem(
                              value: 'branch_admin',
                              child: Text('Branch Admin')),
                          DropdownMenuItem(
                              value: 'super_admin', child: Text('Super Admin')),
                          DropdownMenuItem(
                              value: 'server', child: Text('Server')),
                        ],
                      ),
                      if (widget.isSelf)
                        const Padding(
                          padding: EdgeInsets.only(top: 4, left: 12),
                          child: Text(
                            '🚫 You cannot change your own role.',
                            style: TextStyle(fontSize: 12, color: Colors.red),
                          ),
                        ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Account Active'),
                        subtitle: Text(_isActive
                            ? 'User can log in'
                            : 'User access revoked'),
                        value: _isActive,
                        activeColor: Colors.deepPurple,
                        onChanged: widget.isSelf
                            ? null
                            : (val) => setState(() => _isActive = val),
                      ),
                      const SizedBox(height: 16),
                      const Text('Assigned Branches',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      MultiBranchSelector(
                        selectedIds: _selectedBranches,
                        onChanged: (list) =>
                            setState(() => _selectedBranches = list),
                      ),
                      const SizedBox(height: 24),
                      const Text('Detailed Permissions',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: _permissions.keys.map((key) {
                            return CheckboxListTile(
                              title: Text(_formatPermission(key)),
                              value: _permissions[key],
                              activeColor: Colors.deepPurple,
                              onChanged: (val) =>
                                  setState(() => _permissions[key] = val!),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _validateAndSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child:
                        Text(widget.isEditing ? 'Save Changes' : 'Create User'),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void _validateAndSave() {
    if (_formKey.currentState!.validate()) {
      // Validation: Branch Admins must have at least one branch
      if (_selectedRole == 'branch_admin' && _selectedBranches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '⚠️ Branch Admins must be assigned to at least one branch.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Validation: Super Admins should also have branches for scope
      if (_selectedRole == 'super_admin' && _selectedBranches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '⚠️ Super Admins should be assigned to at least one branch.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final staffData = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim().toLowerCase(),
        'phone': _phoneController.text.trim(), // ✅ NEW: Include phone
        'role': _selectedRole,
        'isActive': _isActive,
        'branchIds': _selectedBranches,
        'permissions': _permissions,
      };

      widget.onSave(staffData);
      Navigator.pop(context);
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.grey[600]),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  String _formatPermission(String key) {
    return key
        .replaceFirst('can', '')
        .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(0)}')
        .trim();
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
        _selectedBranchId = widget.userScope.branchId;
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
            }
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
      final scheduleStatus = await RestaurantStatusService.checkBranchScheduleStatus(_selectedBranchId!);
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
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const RestaurantTimingScreen()),
                  );
                },
                icon: const Icon(Icons.edit_calendar, size: 16),
                label: const Text('Update Timings'),
                style:
                    ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
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
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
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
      final updateData = RestaurantStatusService.buildStatusUpdateData(newStatus, isScheduleOpen);

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
            content:
                Text('Branch ${newStatus ? "opened" : "closed"} successfully!'),
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
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
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
