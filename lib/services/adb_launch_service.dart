// lib/services/adb_launch_service.dart
import 'dart:async';
import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_adb/adb_connection.dart';
import '../managers/adb_manager.dart';

class AdbLaunchService {
  Future<bool> launchKodi(String ipAddress) async {
    final manager = AdbManager();

    // 鍵の遅延初期化
    if (manager.crypto == null) {
      await manager.init();
    }

    final crypto = manager.crypto;
    if (crypto == null) {
      print("[AdbLaunchService] Failed to initialize Crypto.");
      return false;
    }

    print("[AdbLaunchService] Connecting to $ipAddress...");

    int maxRetries = 3;
    for (int i = 0; i < maxRetries; i++) {
      AdbConnection? connection;
      try {
        // 1. 接続オブジェクト作成
        connection = AdbConnection(ipAddress, 5555, crypto);

        // 2. 接続試行
        // ホットリロード後はここで失敗しやすいので、必ずアプリを再起動してください
        bool connected = await connection.connect();
        if (!connected) {
          print("[AdbLaunchService] Attempt ${i + 1}: connect() returned false.");
          // 接続拒否された場合、少し待ってから再試行（認証ダイアログ待ちの可能性）
          throw Exception("Connection failed (connect returned false)");
        }

        // 3. コマンド実行 (v1.12.2と同じ形式、末尾にスペース追加)
        // connection.openの引数にコマンドを渡すことで、接続と同時に実行します
        String command = 'am start -n org.xbmc.kodi/.Splash '; // 末尾にスペース
        print("[AdbLaunchService] Executing: shell:$command");

        // コマンドを含めてストリームを開く
        await connection.open('shell:$command');

        // 4. 実行完了待ち
        await Future.delayed(const Duration(seconds: 2));

        // 5. 切断
        await connection.disconnect();

        print("[AdbLaunchService] Launch command executed.");
        return true;

      } catch (e) {
        print("[AdbLaunchService] Error on attempt ${i + 1}: $e");

        // エラー時の切断
        try {
          await connection?.disconnect();
        } catch (_) {}

        if (i < maxRetries - 1) {
          print("[AdbLaunchService] Retrying in 5 seconds...");
          await Future.delayed(const Duration(seconds: 5));
        } else {
          print("[AdbLaunchService] All attempts failed.");
        }
      }
    }

    return false;
  }
}