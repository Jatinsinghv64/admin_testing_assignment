// import 'dart:async';
//
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/foundation.dart';
//
// /// Model to hold the custom claims data.
// class StaffClaims {
//   final String role;
//   final List<String> branchIds;
//
//   StaffClaims({required this.role, required this.branchIds});
//
//   /// Factory constructor to parse claims from the token.
//   factory StaffClaims.fromMap(Map<String, dynamic> claims) {
//     // Read role, default to 'guest' if not present
//     final role = claims['role'] as String? ?? 'guest';
//
//     // Read branchIds, default to empty list.
//     // Claims array comes as List<dynamic>, so we must cast.
//     final branchIdsRaw = claims['branchIds'] as List<dynamic>? ?? [];
//     final branchIds = branchIdsRaw.map((id) => id.toString()).toList();
//
//     return StaffClaims(role: role, branchIds: branchIds);
//   }
// }
//
// /// Provider to manage the user's auth state and their custom claims.
// class UserProvider with ChangeNotifier {
//   final FirebaseAuth _auth = FirebaseAuth.instance;
//
//   StaffClaims? _claims;
//   StaffClaims? get claims => _claims;
//
//   bool _isLoading = false;
//   bool get isLoading => _isLoading;
//
//   User? _firebaseUser;
//   User? get firebaseUser => _firebaseUser;
//
//   StreamSubscription? _authSubscription;
//
//   UserProvider() {
//     // Listen to Firebase Auth state changes
//     _authSubscription = _auth.authStateChanges().listen(_onAuthStateChanged);
//   }
//
//   @override
//   void dispose() {
//     _authSubscription?.cancel();
//     super.dispose();
//   }
//
//   /// Called whenever the Firebase auth state changes (login/logout).
//   Future<void> _onAuthStateChanged(User? user) async {
//     _isLoading = true;
//     notifyListeners();
//
//     _firebaseUser = user;
//
//     if (user == null) {
//       // User logged out
//       _claims = null;
//     } else {
//       // User logged in, force refresh token to get latest claims
//       await _loadClaims(user, forceRefresh: true);
//     }
//
//     _isLoading = false;
//     notifyListeners();
//   }
//
//   /// Fetches the ID token and parses the custom claims from it.
//   Future<void> _loadClaims(User user, {bool forceRefresh = false}) async {
//     try {
//       final idTokenResult = await user.getIdTokenResult(forceRefresh);
//       final claimsMap = idTokenResult.claims ?? {};
//       _claims = StaffClaims.fromMap(claimsMap);
//     } catch (e) {
//       print("Error loading custom claims: $e");
//       // On error, set to guest to prevent unauthorized access
//       _claims = StaffClaims(role: 'guest', branchIds: []);
//     }
//     notifyListeners();
//   }
//
//   /// Public method to sign out.
//   Future<void> signOut() async {
//     await _auth.signOut();
//     // The authStateChanges listener will handle the rest.
//   }
// }
