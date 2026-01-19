// lib/services/adb_service.dart

import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_adb/adb_crypto.dart';

class AdbService {
  static final AdbService _instance = AdbService._internal();
  factory AdbService() => _instance;
  AdbService._internal();

  // 【重要】鍵をメモリ上に保持して、アプリ起動中は使い回す
  // これにより、連続でボタンを押しても「許可画面」が出なくなります
  static AdbCrypto? _cachedCrypto;

  Future<bool> launchKodi(String ip, {int port = 5555}) async {
    try {
      print("[ADB] Connecting to $ip...");

      // 鍵がなければ作成、あればそれを使う
      _cachedCrypto ??= AdbCrypto();

      // 【重要】コマンドの変更
      // "am start" ではなく "monkey" コマンドを使用します。
      // これはアプリを「強制的に起動（タップ）」するコマンドで、成功率が非常に高いです。
      final String result = await Adb.sendSingleCommand(
        'monkey -p org.xbmc.kodi -c android.intent.category.LAUNCHER 1',
        ip: ip,
        port: port,
        crypto: _cachedCrypto!,
      );

      print("[ADB] Command Result: $result");

      // "No activities found" というエラーが含まれていなければ成功とみなす
      if (result.contains("No activities found") || result.contains("Error")) {
        return false;
      }

      return true;

    } catch (e) {
      print("[ADB] Error: $e");
      return false;
    }
  }
}