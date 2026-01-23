// test/login_screen_test.dart
// Widget tests for LoginScreen - critical authentication UI flow

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mdd/Screens/LoginScreen.dart';
import 'package:mdd/Widgets/Authorization.dart';

// Mock AuthService for testing
class MockAuthService extends AuthService {
  String? mockError;
  bool signInCalled = false;
  String? lastEmail;
  String? lastPassword;

  @override
  Future<String?> signInWithEmailAndPassword(
      String email, String password) async {
    signInCalled = true;
    lastEmail = email;
    lastPassword = password;
    await Future.delayed(const Duration(milliseconds: 100));
    return mockError;
  }
}

void main() {
  late MockAuthService mockAuthService;

  setUp(() {
    mockAuthService = MockAuthService();
  });

  Widget createTestWidget() {
    return Provider<AuthService>.value(
      value: mockAuthService,
      child: const MaterialApp(
        home: LoginScreen(),
      ),
    );
  }

  group('LoginScreen UI', () {
    testWidgets('displays all required elements', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Check branding
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Sign in to manage your branch'), findsOneWidget);

      // Check input fields
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Work Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);

      // Check buttons
      expect(find.text('Login'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.text('Contact Support'), findsOneWidget);
    });

    testWidgets('email field validation shows error for invalid email',
        (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Enter invalid email
      await tester.enterText(find.byType(TextFormField).first, 'invalid-email');
      await tester.enterText(find.byType(TextFormField).last, 'password123');

      // Tap login
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();

      // Check validation error
      expect(find.text('Invalid email address'), findsOneWidget);
    });

    testWidgets('password field validation shows error for empty password',
        (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Enter email but no password
      await tester.enterText(
          find.byType(TextFormField).first, 'test@example.com');

      // Tap login
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();

      // Check validation error
      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('password visibility toggle works', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Find password field and visibility toggle
      final passwordField = find.byType(TextFormField).last;
      await tester.enterText(passwordField, 'secretpassword');
      await tester.pump();

      // Find visibility toggle button (initially visibility_off)
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);

      // Tap to show password
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();

      // Should now show visibility icon
      expect(find.byIcon(Icons.visibility), findsOneWidget);
    });
  });

  group('LoginScreen Form Submission', () {
    testWidgets('shows loading indicator when submitting', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Enter valid credentials
      await tester.enterText(
          find.byType(TextFormField).first, 'test@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'password123');

      // Tap login
      await tester.tap(find.text('Login'));
      await tester.pump();

      // Check loading indicator appears
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('calls AuthService with correct credentials', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Enter credentials
      await tester.enterText(
          find.byType(TextFormField).first, 'admin@test.com');
      await tester.enterText(find.byType(TextFormField).last, 'secretPass123');

      // Tap login
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();

      // Verify AuthService was called with correct values
      expect(mockAuthService.signInCalled, true);
      expect(mockAuthService.lastEmail, 'admin@test.com');
      expect(mockAuthService.lastPassword, 'secretPass123');
    });

    testWidgets('displays error message on failed login', (tester) async {
      mockAuthService.mockError = 'Invalid email or password.';
      await tester.pumpWidget(createTestWidget());

      // Enter credentials
      await tester.enterText(
          find.byType(TextFormField).first, 'test@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'wrongpassword');

      // Tap login
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();

      // Check error message appears (with attempts remaining)
      expect(find.textContaining('Invalid email or password'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  group('LoginScreen Rate Limiting', () {
    testWidgets('shows remaining attempts after failed login', (tester) async {
      mockAuthService.mockError = 'Invalid email or password.';
      await tester.pumpWidget(createTestWidget());

      // Enter credentials
      await tester.enterText(
          find.byType(TextFormField).first, 'test@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'wrongpassword');

      // Tap login
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();

      // Should show remaining attempts (4 after 1st failure)
      expect(find.textContaining('attempts remaining'), findsOneWidget);
    });
  });

  group('LoginScreen Forgot Password', () {
    testWidgets('shows error when email is empty', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Tap forgot password without entering email
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      // Check error message
      expect(find.textContaining('enter your email'), findsOneWidget);
    });

    testWidgets('shows success message when email is provided', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Enter email
      await tester.enterText(
          find.byType(TextFormField).first, 'test@example.com');

      // Tap forgot password
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      // Check success snackbar
      expect(
          find.text('Password reset link sent to your email.'), findsOneWidget);
    });
  });
}
