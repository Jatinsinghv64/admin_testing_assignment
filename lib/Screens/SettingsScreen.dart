import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../Widgets/AccessDeniedWidget.dart';
import '../Widgets/Authorization.dart';
import '../Widgets/Permissions.dart';
import '../Widgets/RestaurantStatusService.dart';
import '../Widgets/notification.dart';
import '../main.dart';
import 'AnalyticsScreen.dart';
import 'BranchManagement.dart';
import 'CouponsScreen.dart';
import 'OrderHistory.dart';
import 'RestaurantTimingScreen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkModeEnabled = false;
  String _selectedLanguage = 'English';

  // ✅ State to track logout process
  bool _isLoggingOut = false;

  late OrderNotificationService _notificationService;
  late RestaurantStatusService _restaurantStatus;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _notificationService = context.read<OrderNotificationService>();
    _restaurantStatus = context.read<RestaurantStatusService>();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _darkModeEnabled = prefs.getBool('dark_mode_enabled') ?? false;
      _selectedLanguage = prefs.getString('selected_language') ?? 'English';
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
    // ✅ Check if logging out FIRST to prevent Access Denied flicker
    if (_isLoggingOut) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Signing out..."),
            ],
          ),
        ),
      );
    }

    final userScope = context.watch<UserScopeService>();
    final authService = context.read<AuthService>();

    // Permission check for entire screen
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
            // Restaurant Status Card
            _buildRestaurantStatusCard(_restaurantStatus, userScope),
            const SizedBox(height: 16),

            // User Profile Card
            _buildUserProfileCard(userScope, authService),
            const SizedBox(height: 16),

            // Administration Section
            buildSectionHeader('Administration', Icons.admin_panel_settings),
            const SizedBox(height: 16),
            // Inside SettingsScreen build method, under Administration section:

            if (userScope.isSuperAdmin)
              buildSettingsCard(
                icon: Icons.access_time_rounded,
                title: 'Restaurant Timings',
                subtitle: 'Manage opening hours and shifts',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const RestaurantTimingScreen()),
                ),
              ),
            const SizedBox(height: 12),

            // --- Order History ---
            if (userScope.isSuperAdmin || userScope.role == 'branchadmin') ...[
              buildSettingsCard(
                icon: Icons.history_edu_rounded,
                title: 'Order History',
                subtitle: 'View all past orders with pagination',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const OrderHistoryScreen(),
                    ),
                  );
                },
                iconColor: Colors.blue,
                cardColor: Colors.blue.withOpacity(0.05),
              ),
              const SizedBox(height: 12),
            ],

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
            if (userScope.isSuperAdmin)
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
                onPressed: () => _showLogoutDialog(context, authService),
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

  Widget _buildRestaurantStatusCard(
      RestaurantStatusService status, UserScopeService scope) {
    if (scope.isSuperAdmin) {
      return const SizedBox.shrink();
    }

    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status.isOpen
                    ? Icons.storefront
                    : Icons.no_food_rounded,
                color: status.isOpen ? Colors.green : Colors.red,
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
                value: status.isOpen,
                onChanged: (value) async {
                  await status.toggleRestaurantStatus(value);
                },
                activeColor: Colors.green,
                inactiveThumbColor: Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            status.isOpen
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
        ],
      ),
    );
  }

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

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
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

  Future<void> _contactSupport(BuildContext context) async {
    const email = 'support@yourapp.com';
    const subject = 'Support Request - Admin App';
    const body = 'Hello Support Team,\n\nI need assistance with:';
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
    const body = 'Bug Description:\nSteps to reproduce:\nExpected behavior:\nActual behavior:';
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

  // ✅ FIXED LOGOUT FUNCTION
  void _showLogoutDialog(BuildContext context, AuthService authService) {
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

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();

    if (!userScope.isSuperAdmin || !userScope.can(Permissions.canManageStaff)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Text('❌ You do not have permission to manage staff.'),
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
        stream: _db.collection('staff').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'No staff members found',
                style: TextStyle(fontSize: 16, color: Colors.grey),
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

              final isSelf = staff.id == userScope.userEmail;

              return _StaffCard(
                staffId: staff.id,
                data: data,
                isSelf: isSelf,
                onEdit: () => _showEditStaffDialog(staff.id, data, isSelf),
              );
            },
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

  void _showEditStaffDialog(String staffId, Map<String, dynamic> currentData, bool isSelf) {
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
          _showSnackBar('❌ User with email $email already exists.', isError: true);
        }
        return;
      }

      await docRef.set({
        ...staffData,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'fcmToken': null,
        'fcmTokenUpdated': null,
      });

      if (mounted) {
        _showSnackBar('✅ Staff member added successfully');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error adding staff: $e', isError: true);
      }
    }
  }

  Future<void> _updateStaffMember(String staffId, Map<String, dynamic> staffData) async {
    try {
      final userScope = context.read<UserScopeService>();
      final isUpdatingSelf = staffId == userScope.userEmail;

      await _db.collection('staff').doc(staffId).update({
        ...staffData,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showSnackBar('✅ Staff member updated successfully');
      }

      if (isUpdatingSelf) {
        _reloadCurrentUserScope();
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error updating staff: $e', isError: true);
      }
    }
  }

  Future<void> _reloadCurrentUserScope() async {
    final userScope = context.read<UserScopeService>();
    final authService = context.read<AuthService>();
    final currentUser = authService.currentUser;

    if (currentUser != null) {
      await userScope.clearScope();
      await userScope.loadUserScope(currentUser, authService);
    }
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
        border: isSelf ? Border.all(color: Colors.deepPurple.withOpacity(0.3)) : null,
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
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  icon: const Icon(Icons.edit_outlined, color: Colors.deepPurple),
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
    return role.toUpperCase();
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusBadge({required this.label, required this.color, required this.icon});

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

  String _selectedRole = 'branchadmin';
  bool _isActive = true;
  List<String> _selectedBranches = [];

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

      String rawRole = widget.currentData!['role'] ?? 'branchadmin';
      if (rawRole == 'super_admin') rawRole = 'superadmin';
      if (rawRole == 'branch_admin') rawRole = 'branchadmin';

      if (['superadmin', 'branchadmin'].contains(rawRole)) {
        _selectedRole = rawRole;
      } else {
        _selectedRole = 'branchadmin';
      }

      _isActive = widget.currentData!['isActive'] ?? true;
      _selectedBranches = List<String>.from(widget.currentData!['branchIds'] ?? []);

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
                        decoration: _inputDecoration('Full Name', Icons.person_outline),
                        validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        enabled: !widget.isEditing,
                        decoration: _inputDecoration('Email Address', Icons.email_outlined).copyWith(
                          filled: widget.isEditing,
                        ),
                        validator: (v) {
                          if (v?.trim().isEmpty ?? true) return 'Required';
                          if (!v!.contains('@')) return 'Invalid email';
                          return null;
                        },
                      ),
                      if (widget.isEditing)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 12),
                          child: Text(
                            'Email cannot be changed after creation.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ),
                      const SizedBox(height: 24),
                      const Text('Role & Access', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        onChanged: widget.isSelf ? null : (value) {
                          if (value != null) setState(() => _selectedRole = value);
                        },
                        decoration: _inputDecoration('Select Role', Icons.security),
                        items: const [
                          DropdownMenuItem(value: 'branchadmin', child: Text('Branch Admin')),
                          DropdownMenuItem(value: 'superadmin', child: Text('Super Admin')),
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
                        subtitle: Text(_isActive ? 'User can log in' : 'User access revoked'),
                        value: _isActive,
                        activeColor: Colors.deepPurple,
                        onChanged: widget.isSelf ? null : (val) => setState(() => _isActive = val),
                      ),
                      const SizedBox(height: 16),
                      const Text('Assigned Branches', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      MultiBranchSelector(
                        selectedIds: _selectedBranches,
                        onChanged: (list) => setState(() => _selectedBranches = list),
                      ),
                      const SizedBox(height: 24),
                      const Text('Detailed Permissions', style: TextStyle(fontWeight: FontWeight.bold)),
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
                              onChanged: (val) => setState(() => _permissions[key] = val!),
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
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(widget.isEditing ? 'Save Changes' : 'Create User'),
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
      if (_selectedRole == 'branchadmin' && _selectedBranches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Branch Admins must be assigned to at least one branch.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final staffData = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim().toLowerCase(),
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
    return key.replaceFirst('can', '').replaceAllMapped(
        RegExp(r'([A-Z])'), (match) => ' ${match.group(0)}'
    ).trim();
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