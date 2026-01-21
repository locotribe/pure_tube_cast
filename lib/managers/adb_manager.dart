import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_adb/adb_crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:crypto/crypto.dart';

class AdbManager {
  // シングルトンパターン
  static final AdbManager _instance = AdbManager._internal();
  factory AdbManager() => _instance;
  AdbManager._internal();

  AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>? _adbKeyPair;
  AdbCrypto? _adbCrypto;

  // 初期化 (アプリ起動時に一度だけ呼ぶ)
  Future<void> init() async {
    if (_adbCrypto != null) return; // すでに初期化済みなら何もしない

    try {
      final dir = await getApplicationDocumentsDirectory();
      final keyFile = File('${dir.path}/adb_key_store.json');

      if (await keyFile.exists()) {
        print("[AdbManager] Loading existing ADB key...");
        try {
          final jsonStr = await keyFile.readAsString();
          final data = jsonDecode(jsonStr);

          final modulus = BigInt.parse(data['modulus']);
          final privateExponent = BigInt.parse(data['privateExponent']);
          final publicExponent = BigInt.parse(data['publicExponent']);
          final p = BigInt.parse(data['p']);
          final q = BigInt.parse(data['q']);

          final privateKey = RSAPrivateKey(modulus, privateExponent, p, q);
          final publicKey = RSAPublicKey(modulus, publicExponent);

          _adbKeyPair = AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(publicKey, privateKey);
          final fingerprint = md5.convert(modulus.toString().codeUnits).toString();
          print("[AdbManager] Key loaded. Fingerprint: $fingerprint");

          _adbCrypto = AdbCrypto(keyPair: _adbKeyPair);
          return;
        } catch (e) {
          print("[AdbManager] Failed to load key: $e");
        }
      }

      print("[AdbManager] Generating new ADB key pair...");
      final keyGen = pc.KeyGenerator('RSA');
      final secureRandom = pc.SecureRandom('Fortuna')..seed(
          pc.KeyParameter(Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(255))))
      );

      keyGen.init(pc.ParametersWithRandom(
        pc.RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        secureRandom,
      ));

      final pair = keyGen.generateKeyPair();
      final privateKey = pair.privateKey as RSAPrivateKey;
      final publicKey = pair.publicKey as RSAPublicKey;
      _adbKeyPair = AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(publicKey, privateKey);

      final data = {
        'modulus': privateKey.modulus.toString(),
        'privateExponent': privateKey.privateExponent.toString(),
        'publicExponent': publicKey.publicExponent.toString(),
        'p': privateKey.p.toString(),
        'q': privateKey.q.toString(),
      };
      await keyFile.writeAsString(jsonEncode(data));
      print("[AdbManager] New key saved to ${keyFile.path}");

      _adbCrypto = AdbCrypto(keyPair: _adbKeyPair);

    } catch (e) {
      print("[AdbManager] Error initializing ADB key: $e");
    }
  }

  AdbCrypto? get crypto => _adbCrypto;
}