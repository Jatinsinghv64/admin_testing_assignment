import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Screens/LoginScreen.dart';
import '../main.dart';
import 'FCM_Service.dart'; // ✅ Import FCM Service for token cleanup

// Auth Service
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Stream<User?> get userStream => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<String?> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        return 'Invalid email or password.';
      } else {
        return 'An error occurred. Please try again.';
      }
    } catch (e) {
      return 'An unexpected error occurred.';
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

    // 2. Perform Firebase Sign Out
    // This triggers the userStream, which AuthWrapper listens to.
    await _auth.signOut();
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

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