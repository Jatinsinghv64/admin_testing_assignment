import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardThemeService with ChangeNotifier {
  static const String _themePrefKey = 'dashboard_is_dark_mode';
  late SharedPreferences _prefs;
  bool _isDarkMode = false; // Default to light mode (white background, blue text)

  bool get isDarkMode => _isDarkMode;

  /// Initializes SharedPreferences and loads the saved theme preference.
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _isDarkMode = _prefs.getBool(_themePrefKey) ?? _isDarkMode;
    notifyListeners();
  }

  /// Toggles the dark mode state and saves the preference.
  Future<void> toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    await _prefs.setBool(_themePrefKey, _isDarkMode);
    notifyListeners();
  }

  /// Explicitly sets the dark mode state and saves the preference.
  Future<void> setDarkMode(bool isDark) async {
    if (_isDarkMode != isDark) {
      _isDarkMode = isDark;
      await _prefs.setBool(_themePrefKey, _isDarkMode);
      notifyListeners();
    }
  }
}
