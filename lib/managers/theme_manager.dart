import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;

  ThemeManager._internal() {
    _loadSettings();
  }

  // 初期値はシステム設定に従う
  ThemeMode _themeMode = ThemeMode.system;
  final StreamController<ThemeMode> _themeController = StreamController.broadcast();

  Stream<ThemeMode> get themeStream => _themeController.stream;
  ThemeMode get currentThemeMode => _themeMode;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final String? modeStr = prefs.getString('theme_mode');
    if (modeStr != null) {
      _themeMode = ThemeMode.values.firstWhere(
            (e) => e.toString() == modeStr,
        orElse: () => ThemeMode.system,
      );
      _notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    _notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.toString());
  }

  void _notifyListeners() {
    _themeController.add(_themeMode);
  }
}