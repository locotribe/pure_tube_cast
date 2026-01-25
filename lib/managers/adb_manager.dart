// lib/managers/adb_manager.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_adb/adb_crypto.dart';
import 'package:flutter_adb/flutter_adb.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart' as pc;

class AdbManager {
  static final AdbManager _instance = AdbManager._internal();

  factory AdbManager() {
    return _instance;
  }

  AdbManager._internal();

  AdbCrypto? crypto;

  Future<void> init() async {
    if (crypto != null) return;

    try {
      print("[AdbManager] Initializing ADB Crypto...");
      final Directory docDir = await getApplicationDocumentsDirectory();

      // 【重要】ファイル名を変更して、強制的に新しい鍵を作らせる
      final File keyFile = File('${docDir.path}/adb_keys_v2.json');

      pc.AsymmetricKeyPair<pc.RSAPublicKey, pc.RSAPrivateKey>? keyPair;

      // 1. 既存の鍵ファイルがあれば読み込む
      if (await keyFile.exists()) {
        try {
          print("[AdbManager] Loading keys from ${keyFile.path}");
          final String jsonStr = await keyFile.readAsString();
          final Map<String, dynamic> jsonMap = jsonDecode(jsonStr);

          keyPair = pc.AsymmetricKeyPair(
            pc.RSAPublicKey(
              BigInt.parse(jsonMap['pub_modulus']),
              BigInt.parse(jsonMap['pub_exponent']),
            ),
            pc.RSAPrivateKey(
              BigInt.parse(jsonMap['priv_modulus']),
              BigInt.parse(jsonMap['priv_exponent']),
              BigInt.parse(jsonMap['priv_p']),
              BigInt.parse(jsonMap['priv_q']),
            ),
          );
        } catch (e) {
          print("[AdbManager] Failed to load keys: $e");
          keyPair = null;
        }
      }

      // 2. 鍵がない場合は新規生成して保存
      if (keyPair == null) {
        print("[AdbManager] Generating new keys (v2)...");
        keyPair = _generateRSAKeyPair();

        final Map<String, String> jsonMap = {
          'pub_modulus': keyPair.publicKey.modulus!.toString(),
          'pub_exponent': keyPair.publicKey.exponent!.toString(),
          'priv_modulus': keyPair.privateKey.modulus!.toString(),
          'priv_exponent': keyPair.privateKey.privateExponent!.toString(),
          'priv_p': keyPair.privateKey.p!.toString(),
          'priv_q': keyPair.privateKey.q!.toString(),
        };
        await keyFile.writeAsString(jsonEncode(jsonMap));
        print("[AdbManager] New keys saved to ${keyFile.path}");
      }

      crypto = AdbCrypto(keyPair: keyPair);
      print("[AdbManager] ADB Crypto initialized successfully.");

    } catch (e) {
      print("[AdbManager] Error initializing ADB crypto: $e");
      crypto = AdbCrypto();
    }
  }

  // 鍵生成メソッド
  pc.AsymmetricKeyPair<pc.RSAPublicKey, pc.RSAPrivateKey> _generateRSAKeyPair() {
    final secureRandom = _getSecureRandom();
    final rsapars = pc.RSAKeyGeneratorParameters(BigInt.parse("65537"), 2048, 64);
    final params = pc.ParametersWithRandom(rsapars, secureRandom);
    final keyGenerator = pc.RSAKeyGenerator();
    keyGenerator.init(params);

    final pair = keyGenerator.generateKeyPair();

    return pc.AsymmetricKeyPair<pc.RSAPublicKey, pc.RSAPrivateKey>(
      pair.publicKey as pc.RSAPublicKey,
      pair.privateKey as pc.RSAPrivateKey,
    );
  }

  pc.SecureRandom _getSecureRandom() {
    final secureRandom = pc.FortunaRandom();
    final seedSource = Random.secure();
    final seeds = <int>[];
    for (int i = 0; i < 32; i++) {
      seeds.add(seedSource.nextInt(255));
    }
    secureRandom.seed(pc.KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }
}