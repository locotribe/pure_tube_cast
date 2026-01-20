import 'package:flutter/material.dart';
import '../managers/theme_manager.dart';

class SettingsLogic {
  final ThemeManager _themeManager = ThemeManager();

  // --- Streams ---
  Stream<ThemeMode> get themeStream => _themeManager.themeStream;

  // --- Current Data ---
  ThemeMode get currentThemeMode => _themeManager.currentThemeMode;

  // --- Actions ---

  /// テーマモードを変更する
  void setThemeMode(ThemeMode mode) {
    _themeManager.setThemeMode(mode);
  }
}