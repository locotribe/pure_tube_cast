import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dlna_service.dart';

class DeviceViewLogic {
  final DlnaService _dlnaService = DlnaService();

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

  // 【追加】切断処理
  void disconnect() {
    _dlnaService.setDevice(null);
  }

  Future<void> sendWol(String mac) async {
    await _dlnaService.sendWakeOnLan(mac);
  }
}