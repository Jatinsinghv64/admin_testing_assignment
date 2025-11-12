import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Widgets/AccessDeniedWidget.dart';
import '../Widgets/Authorization.dart';
import '../Widgets/Permissions.dart';
import '../main.dart';
import 'AnalyticsScreen.dart';
import 'BranchManagement.dart';
import 'CouponsScreen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ❌ **REMOVED (already imported from main.dart):**
// import '../Widgets/RestaurantStatusService.dart';
// import '../Widgets/notification.dart';

// ✅ **ADDED (these seem to be missing from your paste but are in the context):**
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../Widgets/RestaurantStatusService.dart';
import '../Widgets/notification.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ❌ REMOVED: bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  String _selectedLanguage = 'English';
  // ❌ REMOVED: bool _inventoryAlerts = true;
  // ❌ REMOVED: bool _systemUpdates = false;

  late OrderNotificationService _notificationService;
  late RestaurantStatusService _restaurantStatus;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    // ✅ **ADDED:**
    _notificationService = context.read<OrderNotificationService>();
    _restaurantStatus = context.read<RestaurantStatusService>();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // ❌ REMOVED: _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _darkModeEnabled = prefs.getBool('dark_mode_enabled') ?? false;
      _selectedLanguage = prefs.getString('selected_language') ?? 'English';
      // ❌ REMOVED: _inventoryAlerts = prefs.getBool('inventory_alerts') ?? true;
      // ❌ REMOVED: _systemUpdates = prefs.getBool('system_updates') ?? false;
    });
  }

  Future<void> _savePreference(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final authService = context.read<AuthService>(); // ✅ **ADDED**

    // Permission check for entire screen
    // ✅ **MODIFIED:** (Based on your pasted code, 'canManageSettings' is the permission)
    if (!userScope.can(Permissions.canManageSettings)) {
      return const Scaffold(
        body: AccessDeniedWidget(permission: 'manage settings'),
      );
    }

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ **MERGED:** Restaurant Status Card
            _buildRestaurantStatusCard(_restaurantStatus, userScope),
            const SizedBox(height: 16),

            // ✅ **MERGED:** User Profile Card
            _buildUserProfileCard(userScope, authService),
            const SizedBox(height: 16),

            // Administration Section
            buildSectionHeader('Administration', Icons.admin_panel_settings),
            const SizedBox(height: 16),
            if (userScope.isSuperAdmin && userScope.can(Permissions.canManageStaff))
              buildSettingsCard(
                icon: Icons.people_alt,
                title: 'Staff Management',
                subtitle: 'Manage staff members and permissions',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const StaffManagementScreen(),
                    ),
                  );
                },
              ),
            if (userScope.isSuperAdmin && userScope.can(Permissions.canManageStaff))
              const SizedBox(height: 12),
            if (userScope.can(Permissions.canManageCoupons))
              buildSettingsCard(
                icon: Icons.card_giftcard_rounded,
                title: 'Coupon Management',
                subtitle: 'Create and manage discount coupons',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const CouponManagementScreen(),
                    ),
                  );
                },
                iconColor: Colors.teal,
                cardColor: Colors.teal.withOpacity(0.05),
              ),
            if (userScope.can(Permissions.canManageCoupons))
              const SizedBox(height: 12),

            // ✅ **FIX:** Only show Branch Management to Super Admins
            if (userScope.isSuperAdmin)
              buildSettingsCard(
                  icon: Icons.business_outlined,
                  title: 'Branch Settings',
                  subtitle: 'Manage branch information and settings',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const BranchManagementScreen(),
                    ),
                  )
              ),
            if (userScope.isSuperAdmin) // Also hide the SizedBox
              const SizedBox(height: 12),

            if (userScope.isSuperAdmin)
              buildSettingsCard(
                icon: Icons.analytics_outlined,
                title: 'Business Analytics',
                subtitle: 'View detailed business reports',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AnalyticsScreen(),
                  ),
                ),
              ),
            if (userScope.isSuperAdmin)
              const SizedBox(height: 32),

            // App Preferences Section
            if (!userScope.isSuperAdmin)
              const SizedBox(height: 32),
            buildSectionHeader('App Preferences', Icons.settings_applications),
            const SizedBox(height: 16),
            buildSettingsCard(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: 'Manage push notifications and alerts',
              onTap: () => _showNotificationSettings(context),
            ),
            const SizedBox(height: 12),
            buildSettingsCard(
              icon: Icons.dark_mode_outlined,
              title: 'Dark Mode',
              subtitle: 'Switch between light and dark theme',
              onTap: () {
                setState(() => _darkModeEnabled = !_darkModeEnabled);
                _savePreference('dark_mode_enabled', _darkModeEnabled);
                _showSnackBar(context, 'Dark mode ${_darkModeEnabled ? 'enabled' : 'disabled'}');
              },
            ),
            const SizedBox(height: 12),
            buildSettingsCard(
              icon: Icons.language_outlined,
              title: 'Language',
              subtitle: 'Change app language',
              onTap: () => _showLanguageDialog(context),
            ),
            const SizedBox(height: 12),
            buildSettingsCard(
              icon: Icons.palette_outlined,
              title: 'Theme Color',
              subtitle: 'Change primary theme color',
              onTap: () => _showThemeColorDialog(context),
            ),

            const SizedBox(height: 32),

            // Support Section
            buildSectionHeader('Support & Information', Icons.help_outline),
            const SizedBox(height: 16),
            buildSettingsCard(
              icon: Icons.help_center_outlined,
              title: 'Help & Support',
              subtitle: 'Get help and contact support',
              onTap: () => _contactSupport(context),
            ),
            const SizedBox(height: 12),
            buildSettingsCard(
              icon: Icons.bug_report_outlined,
              title: 'Report a Bug',
              subtitle: 'Found an issue? Let us know',
              onTap: () => _reportBug(context),
            ),
            const SizedBox(height: 12),
            buildSettingsCard(
              icon: Icons.feedback_outlined,
              title: 'Send Feedback',
              subtitle: 'Share your suggestions',
              onTap: () => _sendFeedback(context),
            ),
            const SizedBox(height: 12),
            buildSettingsCard(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              subtitle: 'View our privacy policy',
              onTap: () => _viewPrivacyPolicy(context),
            ),
            const SizedBox(height: 12),
            buildSettingsCard(
              icon: Icons.description_outlined,
              title: 'Terms of Service',
              subtitle: 'View terms and conditions',
              onTap: () => _viewTermsOfService(context),
            ),
            const SizedBox(height: 12),
            buildSettingsCard(
              icon: Icons.phone_android_outlined,
              title: 'App Version',
              subtitle: 'v1.2.0 (Build 45)',
              onTap: () => _showAppInfo(context),
            ),
            const SizedBox(height: 12),
            buildSettingsCard(
              icon: Icons.update_outlined,
              title: 'Check for Updates',
              subtitle: 'Check for new app versions',
              onTap: () => _checkForUpdates(context),
            ),

            const SizedBox(height: 40),

            // Logout Button
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 24),
                label: const Text(
                  'Sign Out',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                onPressed: () => _showLogoutDialog(context, authService), // ✅ **PASSED authService**
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ✅ **MERGED:** From context file
  Widget _buildRestaurantStatusCard(
      RestaurantStatusService status, UserScopeService scope) {
    if (scope.isSuperAdmin) {
      // Super admins don't have a single branch, so they can't toggle status.
      return const SizedBox.shrink();
    }

    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status.isOpen // ✅ **FIXED:** Changed from isRestaurantOpen
                    ? Icons.storefront
                    : Icons.no_food_rounded,
                color: status.isOpen ? Colors.green : Colors.red, // ✅ **FIXED:** Changed from isRestaurantOpen
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
              const Spacer(),
              Switch(
                value: status.isOpen, // ✅ **FIXED:** Changed from isRestaurantOpen
                onChanged: (value) async {
                  await status.toggleRestaurantStatus(value); // ✅ **FIXED:** Renamed method
                },
                activeColor: Colors.green,
                inactiveThumbColor: Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            status.isOpen // ✅ **FIXED:** Changed from isRestaurantOpen
                ? 'Your restaurant is OPEN and accepting new orders.'
                : 'Your restaurant is CLOSED. You will not receive new orders.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ **MERGED:** From context file
  Widget _buildUserProfileCard(
      UserScopeService userScope, AuthService authService) {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: Colors.deepPurple),
              const SizedBox(width: 12),
              const Text(
                'User Profile',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.email, 'Email:', userScope.userEmail),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.security, 'Role:', userScope.role.toUpperCase()),
          const SizedBox(height: 8),
          _buildInfoRow(
              Icons.store, 'Branch:', userScope.branchId ?? 'N/A'),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text(
                'Sign Out',
                style: TextStyle(color: Colors.red),
              ),
              onPressed: () async {
                await authService.signOut();
                // AuthWrapper will handle navigation and scope clearing
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ **MERGED:** From context file (replaces _showNotificationSettings)
  Widget _buildNotificationCard(OrderNotificationService service) {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.notifications, color: Colors.deepPurple),
              const SizedBox(width: 12),
              Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Play Sound'),
            subtitle: const Text('Play a sound for new orders'),
            value: service.playSound,
            onChanged: (value) => service.setPlaySound(value),
            secondary: const Icon(Icons.music_note),
          ),
          SwitchListTile(
            title: const Text('Vibrate'),
            subtitle: const Text('Vibrate for new orders'),
            value: service.vibrate,
            onChanged: (value) => service.setVibrate(value),
            secondary: const Icon(Icons.vibration),
          ),
          ListTile(
            title: const Text('Test Notification'),
            subtitle: const Text('Play sound and vibrate'),
            leading: const Icon(Icons.play_arrow_rounded),
            onTap: () async {
              if (service.playSound) {
                final player = AudioPlayer();
                await player.play(AssetSource('notification.mp3'));
              }
              if (service.vibrate) {
                if (await Vibration.hasVibrator() ?? false) {
                  Vibration.vibrate();
                }
              }
            },
          ),
        ],
      ),
    );
  }

  // ✅ **MERGED:** From context file
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ✅ **MERGED:** From context file
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

  // Functional Methods (keeping all your existing logic)
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showBranchSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Branch Settings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BranchSettingItem(
                title: 'Branch Information',
                onTap: () => _editBranchInfo(context),
              ),
              _BranchSettingItem(
                title: 'Operating Hours',
                onTap: () => _editOperatingHours(context),
              ),
              _BranchSettingItem(
                title: 'Delivery Settings',
                onTap: () => _editDeliverySettings(context),
              ),
              _BranchSettingItem(
                title: 'Payment Methods',
                onTap: () => _editPaymentMethods(context),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showBusinessAnalytics(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Business Analytics')),
          body: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.analytics, size: 64, color: Colors.deepPurple),
                SizedBox(height: 16),
                Text(
                  'Advanced Analytics',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text('Sales reports, customer insights, and performance metrics'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNotificationSettings(BuildContext context) {
    // ✅ **MODIFIED:** This now reads from and writes to the service.
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
                  value: _notificationService.playSound, // ✅ CHANGED
                  onChanged: (value) {
                    _notificationService.setPlaySound(value); // ✅ CHANGED
                    setState(() {}); // Update the dialog UI
                  },
                ),
                _NotificationSettingItem(
                  title: 'Vibrate on Order',
                  subtitle: 'Vibrate for new orders',
                  value: _notificationService.vibrate, // ✅ CHANGED
                  onChanged: (value) {
                    _notificationService.setVibrate(value); // ✅ CHANGED
                    setState(() {}); // Update the dialog UI
                  },
                ),
                // You can add these to the service later if needed
                // _NotificationSettingItem(
                //   title: 'Inventory Alerts',
                //   subtitle: 'Low stock notifications',
                //   value: _inventoryAlerts,
                //   onChanged: (value) {
                //     setState(() => _inventoryAlerts = value);
                //     _savePreference('inventory_alerts', value);
                //   },
                // ),
                // _NotificationSettingItem(
                //   title: 'System Updates',
                //   subtitle: 'App and system update notifications',
                //   value: _systemUpdates,
                //   onChanged: (value) {
                //     setState(() => _systemUpdates = value);
                //     _savePreference('system_updates', value);
                //   },
                // ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'), // ✅ CHANGED
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    final languages = ['English', 'Arabic', 'Hindi', 'Spanish', 'French'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Language'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: languages.map((language) => _LanguageOption(
            language: language,
            code: _getLanguageCode(language),
            isSelected: language == _selectedLanguage,
            onTap: () {
              setState(() => _selectedLanguage = language);
              _savePreference('selected_language', language);
              Navigator.pop(context);
              _showSnackBar(context, 'Language changed to $language');
            },
          )).toList(),
        ),
      ),
    );
  }

  void _showThemeColorDialog(BuildContext context) {
    final colors = [
      Colors.deepPurple,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.pink,
      Colors.teal,
    ];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Theme Color'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colors.map((color) => GestureDetector(
            onTap: () {
              Navigator.pop(context);
              _showSnackBar(context, 'Theme color updated');
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade300),
              ),
            ),
          )).toList(),
        ),
      ),
    );
  }

  Future<void> _createDataBackup(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Creating backup...'),
          ],
        ),
      ),
    );
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.pop(context);
      _showSnackBar(context, 'Data backup created successfully');
    }
  }

  Future<void> _restoreData(BuildContext context) async {
    final result = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Data'),
        content: const Text('This will replace all current data with the backup. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      _showSnackBar(context, 'Data restored successfully');
    }
  }

  Future<void> _exportReports(BuildContext context) async {
    final format = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Format'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('CSV Format'),
              onTap: () => Navigator.pop(context, 'CSV'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('PDF Format'),
              onTap: () => Navigator.pop(context, 'PDF'),
            ),
          ],
        ),
      ),
    );
    if (format != null && mounted) {
      _showSnackBar(context, 'Exporting reports as $format...');
    }
  }

  Future<void> _clearAppCache(BuildContext context) async {
    final result = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text('This will clear all cached data. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Clear Cache'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      _showSnackBar(context, 'Cache cleared successfully');
    }
  }

  Future<void> _contactSupport(BuildContext context) async {
    const email = 'support@yourapp.com';
    const subject = 'Support Request - Admin App';
    const body = 'Hello Support Team,\\n\\nI need assistance with:';
    final uri = Uri.parse('mailto:$email?subject=$subject&body=$body');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnackBar(context, 'Could not launch email app');
    }
  }

  Future<void> _reportBug(BuildContext context) async {
    const email = 'bugs@yourapp.com';
    const subject = 'Bug Report - Admin App';
    const body = 'Bug Description:\\nSteps to reproduce:\\nExpected behavior:\\nActual behavior:';
    final uri = Uri.parse('mailto:$email?subject=$subject&body=$body');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnackBar(context, 'Could not launch email app');
    }
  }

  Future<void> _sendFeedback(BuildContext context) async {
    const email = 'feedback@yourapp.com';
    const subject = 'App Feedback - Admin App';
    const body = 'I would like to share the following feedback:';
    final uri = Uri.parse('mailto:$email?subject=$subject&body=$body');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnackBar(context, 'Could not launch email app');
    }
  }

  Future<void> _viewPrivacyPolicy(BuildContext context) async {
    const url = 'https://yourapp.com/privacy';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnackBar(context, 'Could not open privacy policy');
    }
  }

  Future<void> _viewTermsOfService(BuildContext context) async {
    const url = 'https://yourapp.com/terms';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnackBar(context, 'Could not open terms of service');
    }
  }

  void _showAppInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('App Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AppInfoItem(title: 'Version', value: '1.2.0'),
            _AppInfoItem(title: 'Build Number', value: '45'),
            _AppInfoItem(title: 'Last Updated', value: '2024-01-15'),
            _AppInfoItem(title: 'Developer', value: 'Your Company'),
            _AppInfoItem(title: 'Package Name', value: 'com.yourapp.admin'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _checkForUpdates(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Checking for Updates'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Checking for the latest version...'),
            const SizedBox(height: 16),
            Text(
              'You are using the latest version',
              style: TextStyle(
                color: Colors.green[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

    void _showLogoutDialog(BuildContext context, AuthService authService) { // ✅ **ADDED authService**
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of your account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // ✅ **MODIFIED:** (UserScopeService is already in context)
              context.read<UserScopeService>().clearScope();
              await authService.signOut();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  String _getLanguageCode(String language) {
    switch (language) {
      case 'English': return 'US';
      case 'Arabic': return 'SA';
      case 'Hindi': return 'IN';
      case 'Spanish': return 'ES';
      case 'French': return 'FR';
      default: return 'US';
    }
  }

  // Branch setting methods
  void _editBranchInfo(BuildContext context) {
    _showSnackBar(context, 'Edit Branch Information');
  }

  void _editOperatingHours(BuildContext context) {
    _showSnackBar(context, 'Edit Operating Hours');
  }

  void _editDeliverySettings(BuildContext context) {
    _showSnackBar(context, 'Edit Delivery Settings');
  }

  void _editPaymentMethods(BuildContext context) {
    _showSnackBar(context, 'Edit Payment Methods');
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

class _LanguageOption extends StatelessWidget {
  final String language;
  final String code;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.language,
    required this.code,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Text(
        _getFlagEmoji(code),
        style: const TextStyle(fontSize: 20),
      ),
      title: Text(language),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Colors.deepPurple)
          : null,
      onTap: onTap,
    );
  }

  String _getFlagEmoji(String countryCode) {
    final int firstLetter = countryCode.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int secondLetter = countryCode.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(firstLetter) + String.fromCharCode(secondLetter);
  }
}

class _AppInfoItem extends StatelessWidget {
  final String title;
  final String value;

  const _AppInfoItem({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$title: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(value),
        ],
      ),
    );
  }
}

class _BranchSettingItem extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _BranchSettingItem({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }
}

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();

    // DOUBLE SECURITY CHECK: Only allow superadmin with canManageStaff permission
    if (!userScope.isSuperAdmin || !userScope.can(Permissions.canManageStaff)) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Manage Staff'),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: Text('Access Denied - Super Admin privileges required'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
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
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add, color: Colors.deepPurple),
              ),
              onPressed: _showAddStaffDialog,
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('staff').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No staff members found',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add your first staff member',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          final staffMembers = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: staffMembers.length,
            itemBuilder: (context, index) {
              final staff = staffMembers[index];
              final data = staff.data() as Map<String, dynamic>;

              return _StaffCard(
                staffId: staff.id,
                data: data,
                onEdit: () => _showEditStaffDialog(staff.id, data),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddStaffDialog() {
    showDialog(
      context: context,
      builder: (context) => _StaffEditDialog(
        isEditing: false,
        onSave: (staffData) => _addStaffMember(staffData),
      ),
    );
  }

  void _showEditStaffDialog(String staffId, Map<String, dynamic> currentData) {
    showDialog(
      context: context,
      builder: (context) => _StaffEditDialog(
        isEditing: true,
        currentData: currentData,
        onSave: (staffData) => _updateStaffMember(staffId, staffData),
      ),
    );
  }

  Future<void> _addStaffMember(Map<String, dynamic> staffData) async {
    try {
      await _db.collection('staff').doc(staffData['email']).set({
        ...staffData,
        'isActive': true,
        'fcmTokenUpdated': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staff member added successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding staff: $e')),
        );
      }
    }
  }

  Future<void> _updateStaffMember(String staffId, Map<String, dynamic> staffData) async {
    try {
      final userScope = context.read<UserScopeService>();
      final currentUserEmail = userScope.userEmail;

      final bool isUpdatingSelf = staffId == currentUserEmail;

      await _db.collection('staff').doc(staffId).update(staffData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staff member updated successfully')),
        );
      }

      if (isUpdatingSelf) {
        _reloadCurrentUserScope();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating staff: $e')),
        );
      }
    }
  }

  Future<void> _reloadCurrentUserScope() async {
    final userScope = context.read<UserScopeService>();
    final authService = context.read<AuthService>(); // ✅ **THE FIX IS HERE**
    final currentUser = authService.currentUser; // ✅ **THE FIX IS HERE**

    if (currentUser != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Reloading permissions...'),
            ],
          ),
        ),
      );

      await userScope.clearScope();
      await userScope.loadUserScope(currentUser, authService); // ✅ **THE FIX IS HERE**

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permissions updated. App refreshed.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }
}

class _StaffCard extends StatelessWidget {
  final String staffId;
  final Map<String, dynamic> data;
  final VoidCallback onEdit;

  const _StaffCard({
    required this.staffId,
    required this.data,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final String name = data['name'] ?? 'No Name';
    final String email = data['email'] ?? staffId;
    final String role = data['role'] ?? 'No Role';
    final bool isActive = data['isActive'] ?? false;
    final List<dynamic> branchIds = data['branchIds'] ?? [];
    final Map<String, dynamic> permissions = data['permissions'] ?? {};

    // Count enabled permissions
    int enabledPermissions = permissions.values.where((v) => v == true).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Avatar
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.deepPurple, Colors.deepPurple.shade300],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Name and Email
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Unnamed Staff' : name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.email_outlined, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              email,
                              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Edit Button
                Container(
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.edit, color: Colors.deepPurple, size: 20),
                    onPressed: onEdit,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Role and Status Row
            Row(
              children: [
                Expanded(
                  child: _InfoChip(
                    icon: Icons.badge_outlined,
                    label: 'Role',
                    value: _formatRole(role),
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoChip(
                    icon: isActive ? Icons.check_circle_outline : Icons.cancel_outlined,
                    label: 'Status',
                    value: isActive ? 'Active' : 'Inactive',
                    color: isActive ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Branches and Permissions Row
            Row(
              children: [
                Expanded(
                  child: _InfoChip(
                    icon: Icons.business_outlined,
                    label: 'Branches',
                    value: '${branchIds.length}',
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoChip(
                    icon: Icons.lock_outline,
                    label: 'Permissions',
                    value: '$enabledPermissions',
                    color: Colors.purple,
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
    switch (role) {
      case 'superadmin':
        return 'Super Admin';
      case 'branchadmin':
        return 'Branch Admin';
      default:
        return role;
    }
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffEditDialog extends StatefulWidget {
  final bool isEditing;
  final Map<String, dynamic>? currentData;
  final Function(Map<String, dynamic>) onSave;

  const _StaffEditDialog({
    required this.isEditing,
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
  String _selectedRole = 'branchadmin';
  bool _isActive = true;
  List<String> _selectedBranches = [];

  final Map<String, bool> _permissions = {
    'canViewDashboard': false,
    'canManageInventory': false,
    'canManageOrders': false,
    'canManageRiders': false,
    'canManageSettings': false,
    'canManageStaff': false,
    'canViewAnalytics': false,
    'canManageCoupons': false,
  };

  @override
  void initState() {
    super.initState();
    if (widget.isEditing && widget.currentData != null) {
      _nameController.text = widget.currentData!['name'] ?? '';
      _emailController.text = widget.currentData!['email'] ?? '';
      _selectedRole = widget.currentData!['role'] ?? 'branchadmin';
      _isActive = widget.currentData!['isActive'] ?? true;
      _selectedBranches = List<String>.from(widget.currentData!['branchIds'] ?? []);

      final currentPermissions = widget.currentData!['permissions'] ?? {};
      _permissions.forEach((key, value) {
        _permissions[key] = currentPermissions[key] ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          widget.isEditing ? Icons.edit : Icons.person_add,
                          color: Colors.deepPurple,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.isEditing ? 'Edit Staff Member' : 'Add Staff Member',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Name Field
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (value) =>
                    (value?.isEmpty ?? true) ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 16),

                  // Email Field
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) =>
                    (value?.isEmpty ?? true) ? 'Email is required' : null,
                    readOnly: widget.isEditing,
                  ),
                  const SizedBox(height: 16),

                  // Role Dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: InputDecoration(
                      labelText: 'Role',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    items: const [
                      DropdownMenuItem(value: 'superadmin', child: Text('Super Admin')),
                      DropdownMenuItem(value: 'branchadmin', child: Text('Branch Admin')),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedRole = value!);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Active Status Switch
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: SwitchListTile(
                      title: const Text('Active Status'),
                      subtitle: Text(_isActive ? 'Staff member is active' : 'Staff member is inactive'),
                      value: _isActive,
                      onChanged: (value) {
                        setState(() => _isActive = value);
                      },
                      activeColor: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Branch Selector
                  MultiBranchSelector(
                    selectedIds: _selectedBranches,
                    onChanged: (branches) {
                      setState(() => _selectedBranches = branches);
                    },
                  ),
                  const SizedBox(height: 24),

                  // Permissions Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lock_outline, color: Colors.deepPurple, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Permissions',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.deepPurple,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._permissions.entries.map((entry) => CheckboxListTile(
                          title: Text(_getPermissionLabel(entry.key)),
                          value: entry.value,
                          onChanged: (value) {
                            setState(() => _permissions[entry.key] = value ?? false);
                          },
                          activeColor: Colors.deepPurple,
                          contentPadding: EdgeInsets.zero,
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _saveStaff,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          widget.isEditing ? 'Update' : 'Add',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getPermissionLabel(String key) {
    switch (key) {
      case 'canViewDashboard':
        return 'View Dashboard';
      case 'canManageInventory':
        return 'Manage Inventory';
      case 'canManageOrders':
        return 'Manage Orders';
      case 'canManageRiders':
        return 'Manage Riders';
      case 'canManageSettings':
        return 'Manage Settings';
      case 'canManageStaff':
        return 'Manage Staff';
      case 'canViewAnalytics':
        return 'View Analytics';
      case 'canManageCoupons':
        return 'Manage Coupons';
      default:
        return key;
    }
  }

  void _saveStaff() {
    if (_formKey.currentState!.validate()) {
      final staffData = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'role': _selectedRole,
        'isActive': _isActive,
        'branchIds': _selectedBranches,
        'permissions': _permissions,
      };
      widget.onSave(staffData);
      Navigator.of(context).pop();
    }
  }
}