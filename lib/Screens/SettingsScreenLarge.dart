import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Widgets/Authorization.dart'; // For AuthService
import '../Widgets/Permissions.dart'; // For permission constants
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
  static const double _expandedSidebarWidth = 280;
  static const double _collapsedSidebarWidth = 88;
  static const double _sidebarExpandedThreshold = 220;

  String _selectedSection = 'timings';
  bool _isSidebarCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final authService = context.read<AuthService>();
    final allowedSections = _availableSections(userScope);
    final effectiveSelectedSection = allowedSections.contains(_selectedSection)
        ? _selectedSection
        : (allowedSections.isNotEmpty
            ? allowedSections.first
            : _selectedSection);

    _ensureValidSelectedSection(allowedSections);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Row(
          children: [
            ClipRect(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: _isSidebarCollapsed
                    ? _collapsedSidebarWidth
                    : _expandedSidebarWidth,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(right: BorderSide(color: Colors.grey[200]!)),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showExpanded =
                        constraints.maxWidth >= _sidebarExpandedThreshold;

                    return Column(
                      children: [
                        _buildProfileHeader(
                          userScope,
                          showExpanded: showExpanded,
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
                            children: [
                              _buildSectionHeader(
                                'Administration',
                                showExpanded: showExpanded,
                              ),
                              if (userScope.isSuperAdmin)
                                _NavItem(
                                  icon: Icons.access_time_rounded,
                                  label: 'Timings',
                                  id: 'timings',
                                  isSelected:
                                      effectiveSelectedSection == 'timings',
                                  isCollapsed: !showExpanded,
                                  onTap: () => setState(
                                    () => _selectedSection = 'timings',
                                  ),
                                ),
                              if (userScope.isSuperAdmin ||
                                  userScope.role
                                      .toLowerCase()
                                      .contains('branch'))
                                _NavItem(
                                  icon: Icons.history_edu_rounded,
                                  label: 'Order History',
                                  id: 'history',
                                  isSelected:
                                      effectiveSelectedSection == 'history',
                                  isCollapsed: !showExpanded,
                                  onTap: () => setState(
                                    () => _selectedSection = 'history',
                                  ),
                                ),
                              if (userScope.isSuperAdmin) ...[
                                _NavItem(
                                  icon: Icons.people_alt,
                                  label: 'Staff',
                                  id: 'staff',
                                  isSelected:
                                      effectiveSelectedSection == 'staff',
                                  isCollapsed: !showExpanded,
                                  onTap: () => setState(
                                    () => _selectedSection = 'staff',
                                  ),
                                ),
                                _NavItem(
                                  icon: Icons.business_outlined,
                                  label: 'Branches',
                                  id: 'branches',
                                  isSelected:
                                      effectiveSelectedSection == 'branches',
                                  isCollapsed: !showExpanded,
                                  onTap: () => setState(
                                    () => _selectedSection = 'branches',
                                  ),
                                ),
                                _NavItem(
                                  icon: Icons.analytics_outlined,
                                  label: 'Analytics',
                                  id: 'analytics',
                                  isSelected:
                                      effectiveSelectedSection == 'analytics',
                                  isCollapsed: !showExpanded,
                                  onTap: () => setState(
                                    () => _selectedSection = 'analytics',
                                  ),
                                ),
                              ],
                              if (userScope.can(Permissions.canManageCoupons))
                                _NavItem(
                                  icon: Icons.local_offer_rounded,
                                  label: 'Promotions',
                                  id: 'promotions',
                                  isSelected:
                                      effectiveSelectedSection == 'promotions',
                                  isCollapsed: !showExpanded,
                                  onTap: () => setState(
                                    () => _selectedSection = 'promotions',
                                  ),
                                ),
                              if (userScope.isSuperAdmin ||
                                  userScope.role == 'branch_admin')
                                _NavItem(
                                  icon: Icons.table_restaurant_rounded,
                                  label: 'Tables',
                                  id: 'tables',
                                  isSelected:
                                      effectiveSelectedSection == 'tables',
                                  isCollapsed: !showExpanded,
                                  onTap: () => setState(
                                    () => _selectedSection = 'tables',
                                  ),
                                ),
                              const SizedBox(height: 24),
                              _buildSectionHeader(
                                'Preferences',
                                showExpanded: showExpanded,
                              ),
                              _NavItem(
                                icon: context
                                        .watch<DashboardThemeService>()
                                        .isDarkMode
                                    ? Icons.dark_mode_rounded
                                    : Icons.light_mode_rounded,
                                label: 'Dark Mode',
                                id: 'dark_mode',
                                isSelected: false,
                                isCollapsed: !showExpanded,
                                iconColor: Colors.amber,
                                trailing: Switch(
                                  value: context
                                      .watch<DashboardThemeService>()
                                      .isDarkMode,
                                  onChanged: (value) {
                                    context
                                        .read<DashboardThemeService>()
                                        .toggleDarkMode();
                                  },
                                  activeColor: Colors.deepPurple,
                                ),
                                onTap: () {
                                  context
                                      .read<DashboardThemeService>()
                                      .toggleDarkMode();
                                },
                              ),
                              _NavItem(
                                icon: Icons.notifications_outlined,
                                label: 'Notifications',
                                id: 'notifications',
                                isSelected: false,
                                isCollapsed: !showExpanded,
                                iconColor: Colors.red,
                                onTap: () => _showNotificationSettings(context),
                              ),
                              const SizedBox(height: 24),
                              _buildSectionHeader(
                                'Account',
                                showExpanded: showExpanded,
                              ),
                              _NavItem(
                                icon: Icons.logout_rounded,
                                label: 'Sign Out',
                                id: 'logout',
                                isSelected: false,
                                isCollapsed: !showExpanded,
                                iconColor: Colors.red,
                                textColor: Colors.red,
                                onTap: () => _showLogoutDialog(
                                  context,
                                  authService,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.grey[50],
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: KeyedSubtree(
                            key: ValueKey(effectiveSelectedSection),
                            child: _buildContent(
                              userScope,
                              allowedSections,
                              effectiveSelectedSection,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _availableSections(UserScopeService userScope) {
    final sections = <String>[];

    if (userScope.isSuperAdmin) {
      sections.add('timings');
    }
    if (userScope.isSuperAdmin ||
        userScope.role.toLowerCase().contains('branch')) {
      sections.add('history');
    }
    if (userScope.isSuperAdmin) {
      sections.addAll(['staff', 'branches', 'analytics']);
    }
    if (userScope.can(Permissions.canManageCoupons)) {
      sections.add('promotions');
    }
    if (userScope.isSuperAdmin || userScope.role == 'branch_admin') {
      sections.add('tables');
    }

    return sections;
  }

  void _ensureValidSelectedSection(List<String> allowedSections) {
    if (allowedSections.isEmpty || allowedSections.contains(_selectedSection)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || allowedSections.isEmpty) {
        return;
      }

      setState(() {
        _selectedSection = allowedSections.first;
      });
    });
  }

  void _handleBackToHome() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  String _sectionTitle(String section) {
    switch (section) {
      case 'timings':
        return 'Restaurant Timings';
      case 'history':
        return 'Order History';
      case 'staff':
        return 'Staff Management';
      case 'branches':
        return 'Branch Settings';
      case 'analytics':
        return 'Analytics';
      case 'promotions':
        return 'Promotions';
      case 'tables':
        return 'Table Management';
      default:
        return 'Settings';
    }
  }

  String _sectionSubtitle(String section) {
    switch (section) {
      case 'timings':
        return 'Control open hours and service windows across branches.';
      case 'history':
        return 'Review historical orders with operational context and filters.';
      case 'staff':
        return 'Manage internal teams, permissions, and role assignments.';
      case 'branches':
        return 'Maintain branch-level configuration and business information.';
      case 'analytics':
        return 'Track operational performance and business trends.';
      case 'promotions':
        return 'Configure offers, campaigns, and discount rules.';
      case 'tables':
        return 'Adjust floor layout and dine-in table configuration.';
      default:
        return 'Operational settings for the admin platform.';
    }
  }

  Widget _buildContentHeader(String selectedSection) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _sectionTitle(selectedSection).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _sectionTitle(selectedSection),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _sectionSubtitle(selectedSection),
                  style: TextStyle(
                    color: Colors.grey[600],
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _handleBackToHome,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Back to Home'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.deepPurple,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              side: BorderSide(color: Colors.deepPurple.withValues(alpha: 0.2)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    UserScopeService userScope,
    List<String> allowedSections,
    String selectedSection,
  ) {
    if (allowedSections.isEmpty) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(
          child: Text('No settings sections available for this account.'),
        ),
      );
    }

    switch (selectedSection) {
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
        return const ColoredBox(
          color: Colors.white,
          child: Center(child: Text('Select a section')),
        );
    }
  }

  Widget _buildProfileHeader(UserScopeService userScope,
      {required bool showExpanded}) {
    final identifier = userScope.userEmail.isNotEmpty
        ? userScope.userEmail
        : userScope.userIdentifier;
    final initials =
        identifier.isNotEmpty ? identifier.substring(0, 2).toUpperCase() : 'U';

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: showExpanded ? 16 : 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: showExpanded
            ? Row(
                key: const ValueKey('settings-sidebar-expanded-header'),
                children: [
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
                          maxLines: 1,
                        ),
                        Text(
                          userScope.role.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(
                        () => _isSidebarCollapsed = !_isSidebarCollapsed),
                    icon: Icon(
                      _isSidebarCollapsed ? Icons.menu : Icons.menu_open,
                      color: Colors.deepPurple,
                      size: 26,
                    ),
                    tooltip: _isSidebarCollapsed ? 'Expand' : 'Collapse',
                  ),
                ],
              )
            : Column(
                key: const ValueKey('settings-sidebar-collapsed-header'),
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  const SizedBox(height: 10),
                  IconButton(
                    onPressed: () => setState(
                        () => _isSidebarCollapsed = !_isSidebarCollapsed),
                    icon: Icon(
                      _isSidebarCollapsed ? Icons.menu : Icons.menu_open,
                      color: Colors.deepPurple,
                      size: 26,
                    ),
                    tooltip: _isSidebarCollapsed ? 'Expand' : 'Collapse',
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {required bool showExpanded}) {
    if (!showExpanded) {
      return const Divider(height: 32, indent: 16, endIndent: 16);
    }
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showLabel = !isCollapsed && constraints.maxWidth >= 140;
              final showTrailing =
                  showLabel && trailing != null && constraints.maxWidth >= 210;

              return ClipRect(
                child: Row(
                  mainAxisAlignment: showLabel
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 24, color: effectiveIconColor),
                    if (showLabel) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: effectiveTextColor,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w500,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showTrailing) trailing!,
                    ],
                  ],
                ),
              );
            },
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
