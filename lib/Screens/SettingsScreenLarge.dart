import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Widgets/Authorization.dart'; // For AuthService
import '../Widgets/Permissions.dart'; // For permission constants
import '../Widgets/BranchFilterService.dart';
import '../main.dart'; // UserScopeService
import '../services/DashboardThemeService.dart'; // ✅ Added
import '../Widgets/notification.dart'; // ✅ Added

import 'analytics_screen_large.dart';
import 'promotions_screen_large.dart';
import 'branch_management_screen_large.dart';
import 'OrderHistory.dart';
import 'RestaurantTimingScreen.dart';
import 'staff_management_screen_large.dart';
import 'TableManagement.dart';
// Removal of unused ingredients import

class SettingsScreenLarge extends StatefulWidget {
  const SettingsScreenLarge({super.key});

  @override
  State<SettingsScreenLarge> createState() => _SettingsScreenLargeState();
}

class _SettingsScreenLargeState extends State<SettingsScreenLarge> {
  // Navigation State
  String _selectedSection = 'timings'; // Default section
  bool _isSidebarCollapsed = false; // ✅ Added

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final authService = context.read<AuthService>();
    final branchFilter = context.watch<BranchFilterService>();

    return Scaffold(
      backgroundColor: Colors.grey[50], // Neutral background
      body: Row(
        children: [
          // LEFT SIDEBAR (Navigation)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: _isSidebarCollapsed ? 80 : 280,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Column(
              children: [
                _buildProfileHeader(userScope, branchFilter),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    children: [
                      _buildSectionHeader('Administration'),
                      if (userScope.isSuperAdmin)
                        _NavItem(
                          icon: Icons.access_time_rounded,
                          label: 'Timings',
                          id: 'timings',
                          isSelected: _selectedSection == 'timings',
                          isCollapsed: _isSidebarCollapsed,
                          onTap: () =>
                              setState(() => _selectedSection = 'timings'),
                        ),
                      if (userScope.isSuperAdmin ||
                          userScope.role.toLowerCase().contains('branch'))
                        _NavItem(
                          icon: Icons.history_edu_rounded,
                          label: 'Order History',
                          id: 'history',
                          isSelected: _selectedSection == 'history',
                          isCollapsed: _isSidebarCollapsed,
                          onTap: () =>
                              setState(() => _selectedSection = 'history'),
                        ),
                      if (userScope.isSuperAdmin) ...[
                        _NavItem(
                          icon: Icons.people_alt,
                          label: 'Staff',
                          id: 'staff',
                          isSelected: _selectedSection == 'staff',
                          isCollapsed: _isSidebarCollapsed,
                          onTap: () =>
                              setState(() => _selectedSection = 'staff'),
                        ),
                        _NavItem(
                          icon: Icons.business_outlined,
                          label: 'Branches',
                          id: 'branches',
                          isSelected: _selectedSection == 'branches',
                          isCollapsed: _isSidebarCollapsed,
                          onTap: () =>
                              setState(() => _selectedSection = 'branches'),
                        ),
                        _NavItem(
                          icon: Icons.analytics_outlined,
                          label: 'Analytics',
                          id: 'analytics',
                          isSelected: _selectedSection == 'analytics',
                          isCollapsed: _isSidebarCollapsed,
                          onTap: () =>
                              setState(() => _selectedSection = 'analytics'),
                        ),

                      ],
                      if (userScope.can(Permissions.canManageCoupons))
                        _NavItem(
                          icon: Icons.local_offer_rounded,
                          label: 'Promotions',
                          id: 'promotions',
                          isSelected: _selectedSection == 'promotions',
                          isCollapsed: _isSidebarCollapsed,
                          onTap: () =>
                              setState(() => _selectedSection = 'promotions'),
                        ),
                      if (userScope.isSuperAdmin ||
                          userScope.role == 'branch_admin')
                        _NavItem(
                          icon: Icons.table_restaurant_rounded,
                          label: 'Tables',
                          id: 'tables',
                          isSelected: _selectedSection == 'tables',
                          isCollapsed: _isSidebarCollapsed,
                          onTap: () =>
                              setState(() => _selectedSection = 'tables'),
                        ),
                      const SizedBox(height: 24),
                      _buildSectionHeader('Preferences'),
                      _NavItem(
                        icon: context.watch<DashboardThemeService>().isDarkMode 
                            ? Icons.dark_mode_rounded 
                            : Icons.light_mode_rounded,
                        label: 'Dark Mode',
                        id: 'dark_mode',
                        isSelected: false,
                        isCollapsed: _isSidebarCollapsed,
                        iconColor: Colors.amber,
                        trailing: _isSidebarCollapsed ? null : Switch(
                          value: context.watch<DashboardThemeService>().isDarkMode,
                          onChanged: (value) {
                            context.read<DashboardThemeService>().toggleDarkMode();
                          },
                          activeColor: Colors.deepPurple,
                        ),
                        onTap: () {
                          context.read<DashboardThemeService>().toggleDarkMode();
                        },
                      ),
                      _NavItem(
                        icon: Icons.notifications_outlined,
                        label: 'Notifications',
                        id: 'notifications',
                        isSelected: false,
                        isCollapsed: _isSidebarCollapsed,
                        iconColor: Colors.red,
                        onTap: () => _showNotificationSettings(context),
                      ),
                      const SizedBox(height: 24),
                      _buildSectionHeader('Account'),
                      _NavItem(
                        icon: Icons.logout_rounded,
                        label: 'Sign Out',
                        id: 'logout',
                        isSelected: false,
                        isCollapsed: _isSidebarCollapsed,
                        iconColor: Colors.red,
                        textColor: Colors.red,
                        onTap: () => _showLogoutDialog(context, authService),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // RIGHT CONTENT PANE
          Expanded(
            child: Container(
              color: Colors.grey[50], // Match scaffold
              child: ClipRect(
                // Ensure content doesn't bleed
                child: _buildContent(userScope),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(UserScopeService userScope) {
    // We use a switching mechanism.
    // Ideally, we using IndexedStack for state preservation, but some screens utilize 'initState' to load data,
    // so creating them fresh might be safer for data consistency unless we want to cache.
    // Let's use a simple Switch for now.

    switch (_selectedSection) {
      case 'timings':
        return const RestaurantTimingScreen();
      case 'history':
        return const OrderHistoryScreen();
      // Placeholder for StaffManagementScreen check
      case 'staff':
        return const StaffManagementScreenLarge();
      case 'branches':
        return const BranchManagementScreenLarge();
      case 'analytics':
        return const AnalyticsScreenLarge();

      case 'promotions':
        return const PromotionsScreenLarge();
      case 'tables':
        return const TableManagementScreen();
      default:
        return const Center(child: Text('Select a section'));
    }
  }

  Widget _buildProfileHeader(
    UserScopeService userScope,
    BranchFilterService branchFilter,
  ) {
    // Reusing logic from SettingsScreen for visuals
    final identifier = userScope.userEmail.isNotEmpty
        ? userScope.userEmail
        : userScope.userIdentifier;
    final initials = identifier.isNotEmpty
        ? identifier.substring(0, 2).toUpperCase()
        : 'U';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isSidebarCollapsed ? 0 : 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: Row(
        mainAxisAlignment: _isSidebarCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          if (!_isSidebarCollapsed) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    identifier,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    userScope.role.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
          IconButton(
            onPressed: () => setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
            icon: Icon(
              _isSidebarCollapsed ? Icons.menu : Icons.menu_open,
              color: Colors.deepPurple,
              size: 26,
            ),
            tooltip: _isSidebarCollapsed ? 'Expand' : 'Collapse',
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    if (_isSidebarCollapsed) return const Divider(height: 32, indent: 16, endIndent: 16);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.grey[500],
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  void _showNotificationSettings(BuildContext context) {
    final notificationService = context.read<OrderNotificationService>();
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
                  value: notificationService.playSound,
                  onChanged: (value) {
                    notificationService.setPlaySound(value);
                    setState(() {});
                  },
                ),
                _NotificationSettingItem(
                  title: 'Vibrate on Order',
                  subtitle: 'Vibrate for new orders',
                  value: notificationService.vibrate,
                  onChanged: (value) {
                    notificationService.setVibrate(value);
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

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String id;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? iconColor;
  final Color? textColor;
  final bool isCollapsed; // ✅ Added

  const _NavItem({
    required this.icon,
    required this.label,
    required this.id,
    required this.isSelected,
    required this.onTap,
    this.trailing,
    this.iconColor,
    this.textColor,
    this.isCollapsed = false, // ✅ Added
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor =
        iconColor ?? (isSelected ? Colors.deepPurple : Colors.grey[600]);
    final effectiveTextColor =
        textColor ?? (isSelected ? Colors.deepPurple : Colors.black87);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: isCollapsed ? 0 : 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.deepPurple.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Colors.deepPurple.withValues(alpha: 0.2)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(icon, size: 24, color: effectiveIconColor),
              if (!isCollapsed) ...[
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: effectiveTextColor,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ],
          ),
        ),
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
