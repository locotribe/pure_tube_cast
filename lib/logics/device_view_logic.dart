import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_adb/adb_connection.dart';
import '../managers/adb_manager.dart';
import '../services/dlna_service.dart';

class DeviceViewLogic {
  final DlnaService _dlnaService = DlnaService();
  final AdbManager _adbManager = AdbManager(); // シングルトン取得

  // --- State Streams & Notifiers ---
  final StreamController<List<DlnaDevice>> _devicesController = StreamController.broadcast();
  Stream<List<DlnaDevice>> get devicesStream => _devicesController.stream;

  Stream<DlnaDevice?> get connectedDeviceStream => _dlnaService.connectedDeviceStream;
  DlnaDevice? get currentConnectedDevice => _dlnaService.currentDevice;

  final ValueNotifier<bool> isSearching = ValueNotifier(false);

  // --- Internal State ---
  Map<String, String> _customNames = {};
  Map<String, String> _customMacs = {};
  Timer? _searchTimeoutTimer;

  // --- Initialization & Disposal ---

  Future<void> init() async {
    // マネージャーで鍵を初期化 (すでに初期化済みならスキップされる)
    await _adbManager.init();

    await _loadSettings();

    _dlnaService.deviceStream.listen((devices) {
      final processed = _processDevices(devices);
      _devicesController.add(processed);
    });

    await _loadSavedIps();
  }

  void dispose() {
    _searchTimeoutTimer?.cancel();
    _dlnaService.stopSearch();
    _devicesController.close();
    isSearching.dispose();
  }

  // --- Search Control ---
  void startSearch({int durationSec = 30}) {
    isSearching.value = true;
    _dlnaService.startSearch(duration: durationSec);
    _searchTimeoutTimer?.cancel();
    _searchTimeoutTimer = Timer(Duration(seconds: durationSec), () {
      isSearching.value = false;
    });
  }

  void stopSearch() {
    isSearching.value = false;
    _searchTimeoutTimer?.cancel();
    _dlnaService.stopSearch();
  }

  // --- Data Processing ---
  List<DlnaDevice> _processDevices(List<DlnaDevice> devices) {
    return devices.map((device) {
      String? savedName = _customNames[device.ip];
      String? savedMac = _customMacs[device.ip];
      if (savedName != null || savedMac != null) {
        return device.copyWith(
          name: savedName ?? device.name,
          macAddress: savedMac ?? device.macAddress,
        );
      }
      return device;
    }).toList();
  }

  // --- Settings / Persistence ---
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    String? namesJson = prefs.getString('custom_names');
    if (namesJson != null) {
      try {
        _customNames = Map<String, String>.from(jsonDecode(namesJson));
      } catch (_) {}
    }
    String? macsJson = prefs.getString('custom_macs');
    if (macsJson != null) {
      try {
        _customMacs = Map<String, String>.from(jsonDecode(macsJson));
      } catch (_) {}
    }
  }

  Future<void> _loadSavedIps() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> ips = prefs.getStringList('saved_ips') ?? [];
    for (var ip in ips) {
      String? name = _customNames[ip];
      _dlnaService.addForcedDevice(ip, customName: name);
    }
  }

  Future<void> updateDeviceSettings(DlnaDevice device, String newName, String newMac) async {
    final prefs = await SharedPreferences.getInstance();
    if (newName.isNotEmpty) _customNames[device.ip] = newName;
    _customMacs[device.ip] = newMac;
    if (newName.isNotEmpty) {
      _dlnaService.updateDeviceName(device.ip, newName);
    }
    await prefs.setString('custom_names', jsonEncode(_customNames));
    await prefs.setString('custom_macs', jsonEncode(_customMacs));
  }

  Future<void> addManualIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    String? savedName = _customNames[ip];
    await _dlnaService.verifyAndAddManualDevice(ip, customName: savedName);
    List<String> ips = prefs.getStringList('saved_ips') ?? [];
    if (!ips.contains(ip)) {
      ips.add(ip);
      await prefs.setStringList('saved_ips', ips);
    }
  }

  Future<void> removeDevice(DlnaDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    _dlnaService.removeDevice(device.ip);
    List<String> ips = prefs.getStringList('saved_ips') ?? [];
    ips.remove(device.ip);
    await prefs.setStringList('saved_ips', ips);
  }

  // --- Device Actions ---
  Future<bool> checkConnection(DlnaDevice device) async {
    return await _dlnaService.checkConnection(device);
  }

  void setSelectDevice(DlnaDevice device) {
    _dlnaService.setDevice(device);
  }

  void disconnect() {
    _dlnaService.setDevice(null);
  }

  Future<void> sendWol(String mac) async {
    await _dlnaService.sendWakeOnLan(mac);
  }

  // --- ADB ---
  Future<void> launchAppViaAdb(DlnaDevice device) async {
    print("[DeviceViewLogic] Starting ADB launch...");

    // マネージャーから鍵を取得
    if (_adbManager.crypto == null) {
      await _adbManager.init();
    }

    if (_adbManager.crypto == null) {
      throw Exception("ADB Crypto init failed");
    }

    // 常に同じ鍵インスタンスを使用
    var connection = AdbConnection(device.ip, 5555, _adbManager.crypto!);

    bool isConnected = false;
    int retryCount = 0;
    const maxRetries = 3;

    try {
      while (!isConnected && retryCount < maxRetries) {
        print("[DeviceViewLogic] Connecting to ${device.ip}:5555 (Attempt ${retryCount + 1})...");
        try {
          isConnected = await connection.connect();
          if (!isConnected) {
            print("[DeviceViewLogic] Connect returned false. Waiting...");
            await Future.delayed(const Duration(seconds: 2));
          }
        } catch (e) {
          print("[DeviceViewLogic] Connect error: $e. Retrying...");
          await Future.delayed(const Duration(seconds: 2));
        }
        retryCount++;
      }

      if (isConnected) {
        print("[DeviceViewLogic] Connected! Attempting to launch Kodi...");

        // 作戦A: am start .Splash + スペース
        print("[DeviceViewLogic] Try 1: am start .Splash");
        var stream1 = await connection.open("shell:am start -n org.xbmc.kodi/.Splash ");
        var output1 = await stream1.onPayload.cast<List<int>>().transform(utf8.decoder).join();
        print("[Output 1] $output1");

        if (output1.toLowerCase().contains("error") || output1.toLowerCase().contains("does not exist")) {
          // 作戦B: am start .Main + スペース
          print("[DeviceViewLogic] Try 2: am start .Main");
          await Future.delayed(const Duration(milliseconds: 500));
          var stream2 = await connection.open("shell:am start -n org.xbmc.kodi/.Main ");
          var output2 = await stream2.onPayload.cast<List<int>>().transform(utf8.decoder).join();
          print("[Output 2] $output2");

          if (output2.toLowerCase().contains("error") || output2.toLowerCase().contains("does not exist")) {
            // 作戦C: monkey + スペース
            print("[DeviceViewLogic] Try 3: monkey");
            await Future.delayed(const Duration(milliseconds: 500));
            var stream3 = await connection.open("shell:monkey -p org.xbmc.kodi -v 1 ");
            var output3 = await stream3.onPayload.cast<List<int>>().transform(utf8.decoder).join();
            print("[Output 3] $output3");
          }
        }

        await Future.delayed(const Duration(seconds: 2));
        await connection.disconnect();
        print("[DeviceViewLogic] Disconnected.");

      } else {
        print("[DeviceViewLogic] Failed to connect.");
        throw Exception("ADB Connection failed.");
      }

    } catch (e) {
      print("[DeviceViewLogic] ADB Error: $e");
      try { await connection.disconnect(); } catch (_) {}
      rethrow;
    }
  }
}