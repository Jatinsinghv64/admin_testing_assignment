// lib/Screens/LoginScreen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Widgets/Authorization.dart';
import '../constants.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isPasswordVisible = false;
  String? _errorMessage;

  // --- RATE LIMITING STATE ---
  int _failedAttempts = 0;
  DateTime? _lockoutEndTime;
  static const String _lockoutEndKey = 'login_lockout_end';
  static const String _failedAttemptsKey = 'login_failed_attempts';

  @override
  void initState() {
    super.initState();
    _loadRateLimitState();
  }

  Future<void> _loadRateLimitState() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutEndMs = prefs.getInt(_lockoutEndKey);
    final attempts = prefs.getInt(_failedAttemptsKey) ?? 0;
    
    setState(() {
      _failedAttempts = attempts;
      if (lockoutEndMs != null) {
        _lockoutEndTime = DateTime.fromMillisecondsSinceEpoch(lockoutEndMs);
        // Clear lockout if expired
        if (_lockoutEndTime!.isBefore(DateTime.now())) {
          _lockoutEndTime = null;
          _failedAttempts = 0;
          _clearRateLimitState();
        }
      }
    });
  }

  Future<void> _saveRateLimitState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_failedAttemptsKey, _failedAttempts);
    if (_lockoutEndTime != null) {
      await prefs.setInt(_lockoutEndKey, _lockoutEndTime!.millisecondsSinceEpoch);
    }
  }

  Future<void> _clearRateLimitState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lockoutEndKey);
    await prefs.remove(_failedAttemptsKey);
  }

  bool get _isLockedOut {
    if (_lockoutEndTime == null) return false;
    return _lockoutEndTime!.isAfter(DateTime.now());
  }

  String get _lockoutRemainingTime {
    if (_lockoutEndTime == null) return '';
    final remaining = _lockoutEndTime!.difference(DateTime.now());
    if (remaining.isNegative) return '';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  Future<void> _login() async {
    // Check lockout first
    if (_isLockedOut) {
      setState(() => _errorMessage = 'Too many failed attempts. Please try again in $_lockoutRemainingTime');
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final authService = context.read<AuthService>();
      final error = await authService.signInWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (error != null && mounted) {
        // Increment failed attempts
        _failedAttempts++;
        
        // Check if we should lockout
        if (_failedAttempts >= AppConstants.maxLoginAttempts) {
          _lockoutEndTime = DateTime.now().add(AppConstants.loginLockoutDuration);
          await _saveRateLimitState();
          setState(() => _errorMessage = 'Too many failed attempts. Account locked for ${AppConstants.loginLockoutDuration.inMinutes} minutes.');
        } else {
          await _saveRateLimitState();
          final remaining = AppConstants.maxLoginAttempts - _failedAttempts;
          setState(() => _errorMessage = '$error ($remaining attempts remaining)');
        }
      } else if (error == null) {
        // Successful login - clear rate limit state
        await _clearRateLimitState();
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = "An unexpected error occurred.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_emailController.text.isEmpty) {
      setState(() => _errorMessage = "Please enter your email to reset password.");
      return;
    }
    // Call your Auth Service reset password logic here
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Password reset link sent to your email.")),
    );
  }

  Future<void> _contactSupport() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'support@mitran.qa',
      query: 'subject=Login Issue - Admin App',
    );
    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- BRANDING ---
                  Container(
                    height: 120,
                    width: 120,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)],
                    ),
                    child: const Center(
                      child: Icon(Icons.restaurant_menu_rounded, size: 60, color: Colors.deepPurple),
                      // Use Image.asset('assets/logo.png') here for production
                    ),
                  ),
                  const SizedBox(height: 32),

                  Text(
                    'Welcome Back',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to manage your branch',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 40),

                  // --- INPUTS ---
                  TextFormField(
                    controller: _emailController,
                    decoration: _buildInputDecoration('Work Email', Icons.email_outlined),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (value) => (value == null || !value.contains('@')) ? 'Invalid email address' : null,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    decoration: _buildInputDecoration('Password', Icons.lock_outline).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                        onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                      ),
                    ),
                    onFieldSubmitted: (_) => _login(),
                    validator: (value) => (value == null || value.isEmpty) ? 'Password is required' : null,
                  ),

                  // --- FORGOT PASSWORD ---
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _resetPassword,
                      child: const Text('Forgot Password?', style: TextStyle(color: Colors.deepPurple)),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --- ERROR MESSAGE ---
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[100]!),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                        ],
                      ),
                    ),

                  // --- LOGIN BUTTON ---
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: _isLoading
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // --- FOOTER ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Trouble logging in? ", style: TextStyle(color: Colors.grey[600])),
                      GestureDetector(
                        onTap: _contactSupport,
                        child: const Text("Contact Support", style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.w600)),
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

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.grey[500]),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.deepPurple, width: 2)),
    );
  }
}