// lib/logics/device_view_logic.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_adb/adb_connection.dart';
import '../managers/adb_manager.dart';
import '../services/dlna_service.dart';

class DeviceViewLogic {
  final DlnaService _dlnaService = DlnaService();
  final AdbManager _adbManager = AdbManager();

  // --- State Streams & Notifiers ---
  final StreamController<List<DlnaDevice>> _devicesController = StreamController.broadcast();
  Stream<List<DlnaDevice>> get devicesStream => _devicesController.stream;

  Stream<DlnaDevice?> get connectedDeviceStream => _dlnaService.connectedDeviceStream;
  DlnaDevice? get currentConnectedDevice => _dlnaService.currentDevice;

  final ValueNotifier<bool> isSearching = ValueNotifier(false);

  // --- Internal State ---
  Map<String, String> _customNames = {};
  Map<String, String> _customMacs = {};
  List<String> _savedIps = [];

  Map<String, bool> _kodiStates = {};
  final Set<String> _launchingIps = {};

  Timer? _searchTimeoutTimer;
  StreamSubscription? _deviceSubscription;

  // --- Initialization & Disposal ---

  Future<void> init() async {
    await _adbManager.init();
    await _loadSettings();
    await _loadSavedIps();

    _deviceSubscription = _dlnaService.deviceStream.listen((devices) {
      final processed = _processDevices(devices);
      if (!_devicesController.isClosed) {
        _devicesController.add(processed);
      }
    });

    if (_dlnaService.currentDevices.isNotEmpty) {
      _devicesController.add(_processDevices(_dlnaService.currentDevices));
    }
  }

  void dispose() {
    _searchTimeoutTimer?.cancel();
    _deviceSubscription?.cancel();
    _devicesController.close();
    isSearching.dispose();
  }

  // --- Search Control ---
  void startSearch({int durationSec = 30}) {
    isSearching.value = true;
    _dlnaService.startSearch(duration: durationSec);

    _checkAllKodiStatus();

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
    final mapped = devices.map((device) {
      String? savedName = _customNames[device.ip];
      String? savedMac = _customMacs[device.ip];
      bool isKodiFg = _kodiStates[device.ip] ?? false;
      bool isLaunching = _launchingIps.contains(device.ip);

      if (savedName != null || savedMac != null || isKodiFg || isLaunching) {
        return device.copyWith(
          name: savedName ?? device.name,
          macAddress: savedMac ?? device.macAddress,
          isKodiForeground: isKodiFg,
          isLaunching: isLaunching,
        );
      }
      return device;
    }).toList();

    mapped.sort((a, b) {
      bool aIsSaved = _savedIps.contains(a.ip);
      bool bIsSaved = _savedIps.contains(b.ip);
      if (aIsSaved && !bIsSaved) return -1;
      if (!aIsSaved && bIsSaved) return 1;
      return 0;
    });

    return mapped;
  }

  // --- Status Checks ---
  void _checkAllKodiStatus() {
    final devices = _dlnaService.currentDevices;
    for (var device in devices) {
      _checkKodiStatus(device);
    }
  }

  Future<void> _checkKodiStatus(DlnaDevice device) async {
    try {
      if (_adbManager.crypto == null) await _adbManager.init();
      if (_adbManager.crypto == null) return;

      var connection = AdbConnection(device.ip, 5555, _adbManager.crypto!);
      bool isConnected = await connection.connect();

      if (isConnected) {
        // 修正: ウィンドウフォーカスではなく、Resumeされているアクティビティを確認するコマンドに変更
        // grep mResumedActivity は現在アクティブなアプリを確実に拾いやすい
        var stream = await connection.open("shell:dumpsys activity activities | grep mResumedActivity");
        var output = await stream.onPayload.cast<List<int>>().transform(utf8.decoder).join();

        await connection.disconnect();

        // 追加: デバッグログ（何が返ってきているか確認用）
        print("[DeviceViewLogic] Status Output (${device.ip}): ${output.trim()}");

        bool isRunning = output.contains("org.xbmc.kodi");

        _kodiStates[device.ip] = isRunning;

        if (!_devicesController.isClosed) {
          _devicesController.add(_processDevices(_dlnaService.currentDevices));
        }
      }
    } catch (e) {
      print("[DeviceViewLogic] Check Status Error (${device.ip}): $e");
    }
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
    _savedIps = prefs.getStringList('saved_ips') ?? [];
    for (var ip in _savedIps) {
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

    if (!_savedIps.contains(ip)) {
      _savedIps.add(ip);
      await prefs.setStringList('saved_ips', _savedIps);
    }
  }

  Future<void> removeDevice(DlnaDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    _dlnaService.removeDevice(device.ip);

    _savedIps.remove(device.ip);
    await prefs.setStringList('saved_ips', _savedIps);
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
    print("[DeviceViewLogic] Starting ADB launch sequence...");

    _launchingIps.add(device.ip);
    if (!_devicesController.isClosed) {
      _devicesController.add(_processDevices(_dlnaService.currentDevices));
    }

    if (_adbManager.crypto == null) {
      await _adbManager.init();
    }

    if (_adbManager.crypto == null) {
      _launchingIps.remove(device.ip);
      _devicesController.add(_processDevices(_dlnaService.currentDevices));
      throw Exception("ADB Crypto init failed");
    }

    var connection = AdbConnection(device.ip, 5555, _adbManager.crypto!);

    try {
      bool isConnected = false;
      int retryCount = 0;
      const maxRetries = 3;

      while (!isConnected && retryCount < maxRetries) {
        print("[DeviceViewLogic] Connecting to ${device.ip}:5555 (Attempt ${retryCount + 1})...");
        try {
          isConnected = await connection.connect();
          if (!isConnected) {
            await Future.delayed(const Duration(seconds: 2));
          }
        } catch (e) {
          await Future.delayed(const Duration(seconds: 2));
        }
        retryCount++;
      }

      if (isConnected) {
        print("[DeviceViewLogic] Connected! Sending launch commands...");

        var stream1 = await connection.open("shell:am start -n org.xbmc.kodi/.Splash ");
        await stream1.onPayload.drain();

        await Future.delayed(const Duration(milliseconds: 500));

        var stream2 = await connection.open("shell:am start -n org.xbmc.kodi/.Main ");
        await stream2.onPayload.drain();

        await connection.disconnect();
        print("[DeviceViewLogic] Commands sent. Waiting for startup...");

        // 待ち時間を少し延長（念のため）
        await Future.delayed(const Duration(seconds: 5));

        print("[DeviceViewLogic] Checking status...");
        await _checkKodiStatus(device);

      } else {
        print("[DeviceViewLogic] Failed to connect.");
        throw Exception("ADB Connection failed.");
      }

    } catch (e) {
      print("[DeviceViewLogic] ADB Error: $e");
      rethrow;
    } finally {
      _launchingIps.remove(device.ip);
      if (!_devicesController.isClosed) {
        _devicesController.add(_processDevices(_dlnaService.currentDevices));
      }
    }
  }
}