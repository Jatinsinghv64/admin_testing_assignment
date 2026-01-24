import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Screens/LoginScreen.dart';
import '../main.dart';
import '../constants.dart';
import 'FCM_Service.dart'; // ✅ Import FCM Service for token cleanup

// Auth Service
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Stream<User?> get userStream => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // Session management keys
  static const String _lastActivityKey = 'last_activity_timestamp';

  Future<String?> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      if (kIsWeb) {
        await _auth.setPersistence(
            Persistence.LOCAL); // ✅ Ensure persistence only on web
      }
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      
      // ✅ Record login activity for session timeout
      await _updateLastActivity();
      
      return null;
    } on FirebaseException catch (e) {
      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        return 'Invalid email or password.';
      } else {
        return 'An error occurred. Please try again. (${e.code})';
      }
    } catch (e) {
      return 'An unexpected error occurred: $e';
    }
  }

  // ✅ Session Timeout: Update last activity timestamp
  Future<void> _updateLastActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastActivityKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('⚠️ Error updating last activity: $e');
    }
  }

  // ✅ Session Timeout: Check if session is still valid
  Future<bool> isSessionValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastActivityMs = prefs.getInt(_lastActivityKey);
      
      if (lastActivityMs == null) {
        // No recorded activity - consider session valid (first login)
        await _updateLastActivity();
        return true;
      }
      
      final lastActivity = DateTime.fromMillisecondsSinceEpoch(lastActivityMs);
      final now = DateTime.now();
      final sessionAge = now.difference(lastActivity);
      
      // Check against session timeout from constants (default 24 hours)
      if (sessionAge > AppConstants.sessionTimeout) {
        debugPrint('🔒 Session expired: ${sessionAge.inHours} hours old');
        return false;
      }
      
      return true;
    } catch (e) {
      debugPrint('⚠️ Error checking session validity: $e');
      return true; // On error, allow session to prevent lockout
    }
  }

  // ✅ Session Timeout: Update activity on user interaction
  Future<void> recordActivity() async {
    await _updateLastActivity();
  }

  // ✅ Session Timeout: Clear session on logout
  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastActivityKey);
    } catch (e) {
      debugPrint('⚠️ Error clearing session: $e');
    }
  }

  // ✅ UPDATED: Sign Out with Token Cleanup & Safety
  Future<void> signOut() async {
    try {
      // 1. Delete the specific device token from Firestore
      // This prevents the "Shared Device" issue (receiving notifs for the previous user).
      debugPrint("🚪 Attempting to delete FCM token before sign out...");
      await FcmService().deleteToken();
    } catch (e) {
      // If offline, token deletion might fail. We catch the error
      // so the user can still sign out locally.
      debugPrint("⚠️ Error deleting token (likely offline): $e");
    }

    // 2. Clear session data
    await _clearSession();

    // 3. Perform Firebase Sign Out
    // This triggers the userStream, which AuthWrapper listens to.
    await _auth.signOut();
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  bool _isCheckingSession = true;
  bool _sessionExpired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Check session validity when app resumes from background
      _checkSession();
    }
  }

  Future<void> _checkSession() async {
    final authService = context.read<AuthService>();
    if (authService.currentUser != null) {
      final isValid = await authService.isSessionValid();
      if (!isValid && mounted) {
        setState(() => _sessionExpired = true);
        // Sign out the user
        await authService.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session expired. Please log in again.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
    if (mounted) {
      setState(() => _isCheckingSession = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return StreamBuilder<User?>(
      stream: authService.userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final User? user = snapshot.data;

          // ✅ FIX: User is signed out
          if (user == null) {
            // We use addPostFrameCallback to ensure we don't modify the
            // provider state (notifyListeners) while the widget tree is still building.
            // This prevents the "Access Denied" glitch and "setState during build" errors.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                context.read<UserScopeService>().clearScope();
              }
            });

            return const LoginScreen();
          }

          // ✅ Check session on first load
          if (_isCheckingSession) {
            _checkSession();
          }

          // ✅ Record activity when user is active
          authService.recordActivity();

          // User is signed in
          return ScopeLoader(user: user);
        }

        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
