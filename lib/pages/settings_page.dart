import 'package:flutter/material.dart';
import '../logics/settings_logic.dart'; // ロジッククラス

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final logic = SettingsLogic();

    return Scaffold(
      appBar: AppBar(title: const Text("設定")),
      body: StreamBuilder<ThemeMode>(
        stream: logic.themeStream,
        initialData: logic.currentThemeMode,
        builder: (context, snapshot) {
          final currentMode = snapshot.data ?? ThemeMode.system;

          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text("外観設定", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              RadioListTile<ThemeMode>(
                title: const Text("ライトモード"),
                secondary: const Icon(Icons.wb_sunny),
                value: ThemeMode.light,
                groupValue: currentMode,
                onChanged: (value) => logic.setThemeMode(value!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text("ダークモード"),
                secondary: const Icon(Icons.nightlight_round),
                value: ThemeMode.dark,
                groupValue: currentMode,
                onChanged: (value) => logic.setThemeMode(value!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text("システムのデフォルト"),
                secondary: const Icon(Icons.settings_brightness),
                value: ThemeMode.system,
                groupValue: currentMode,
                onChanged: (value) => logic.setThemeMode(value!),
              ),
            ],
          );
        },
      ),
    );
  }
}