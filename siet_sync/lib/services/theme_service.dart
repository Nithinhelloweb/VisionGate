import 'package:flutter/material.dart';

/// Theme Manager Service
/// Manages app-wide theme settings including dark mode
class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  ThemeMode _themeMode = ThemeMode.light;
  
  /// Get current theme mode
  ThemeMode get themeMode => _themeMode;
  
  /// Check if dark mode is enabled
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  
  /// Check if system theme is selected
  bool get isSystemMode => _themeMode == ThemeMode.system;
  
  /// Toggle between light and system mode
  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.light ? ThemeMode.system : ThemeMode.light;
    notifyListeners();
  }
  
  /// Set specific theme mode
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }
}

// Global instance for easy access
final themeService = ThemeService();
