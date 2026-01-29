import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'managers/theme_manager.dart'; // 追加

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  print("[DEBUG] === App Started ===");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager(); // 追加

    // StreamBuilderでラップして動的に切り替え
    return StreamBuilder<ThemeMode>(
      stream: themeManager.themeStream,
      initialData: themeManager.currentThemeMode,
      builder: (context, snapshot) {
        return MaterialApp(
          title: '動画キャスト for Kodi',
          // ライトテーマ定義
          theme: ThemeData(
            primarySwatch: Colors.red,
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: Colors.white,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
            ),
            cardColor: Colors.white,
          ),
          // ダークテーマ定義
          darkTheme: ThemeData(
            primarySwatch: Colors.red,
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF121212), // 黒すぎないダークグレー
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF121212),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            cardColor: const Color(0xFF1E1E1E),
            dialogBackgroundColor: const Color(0xFF1E1E1E),
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.red,
              brightness: Brightness.dark,
            ),
          ),
          themeMode: snapshot.data ?? ThemeMode.system, // 現在の設定を適用
          home: const HomePage(),
        );
      },
    );
  }
}