import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dlna_service.dart';

class DeviceViewLogic {
  final DlnaService _dlnaService = DlnaService();

  // --- State Streams & Notifiers ---

  // 検出されたデバイス一覧 (設定適用済み)
  final StreamController<List<DlnaDevice>> _devicesController = StreamController.broadcast();
  Stream<List<DlnaDevice>> get devicesStream => _devicesController.stream;

  // 現在接続中のデバイス
  Stream<DlnaDevice?> get connectedDeviceStream => _dlnaService.connectedDeviceStream;
  DlnaDevice? get currentConnectedDevice => _dlnaService.currentDevice;

  // 検索中フラグ
  final ValueNotifier<bool> isSearching = ValueNotifier(false);

  // --- Internal State ---
  Map<String, String> _customNames = {};
  Map<String, String> _customMacs = {};
  Timer? _searchTimeoutTimer;

  // --- Initialization & Disposal ---

  Future<void> init() async {
    await _loadSettings();

    // DLNAサービスからの更新を監視し、設定(名前/MAC)を適用して流す
    _dlnaService.deviceStream.listen((devices) {
      final processed = _processDevices(devices);
      _devicesController.add(processed);
    });

    // 保存されたIPを復元してサービスに追加
    await _loadSavedIps();
  }

  void dispose() {
    _searchTimeoutTimer?.cancel();
    _dlnaService.stopSearch();
    _devicesController.close();
    isSearching.dispose();
  }

  // --- Search Control ---

  void startSearch({int durationSec = 15}) {
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

    // Custom Names
    String? namesJson = prefs.getString('custom_names');
    if (namesJson != null) {
      try {
        _customNames = Map<String, String>.from(jsonDecode(namesJson));
      } catch (_) {}
    }

    // Custom MACs
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

    // メモリ更新
    if (newName.isNotEmpty) _customNames[device.ip] = newName;
    _customMacs[device.ip] = newMac;

    // Service側の名前も更新 (探索結果などに反映させるため)
    if (newName.isNotEmpty) {
      _dlnaService.updateDeviceName(device.ip, newName);
    }

    // 保存
    await prefs.setString('custom_names', jsonEncode(_customNames));
    await prefs.setString('custom_macs', jsonEncode(_customMacs));
  }

  Future<void> addManualIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();

    // Serviceに追加
    String? savedName = _customNames[ip];
    await _dlnaService.verifyAndAddManualDevice(ip, customName: savedName);

    // リスト保存
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

  Future<void> sendWol(String mac) async {
    await _dlnaService.sendWakeOnLan(mac);
  }
}