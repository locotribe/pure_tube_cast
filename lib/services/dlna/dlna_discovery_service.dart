import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../../models/dlna_device.dart';

class DlnaDiscoveryService {
  final List<DlnaDevice> _devices = [];
  final StreamController<List<DlnaDevice>> _deviceStreamController = StreamController.broadcast();
  Stream<List<DlnaDevice>> get deviceStream => _deviceStreamController.stream;

  RawDatagramSocket? _socket;
  Timer? _searchTimer;
  bool _isSearching = false;

  // スキャンセッション管理ID
  int _currentScanSessionId = 0;

  final Set<String> _foundLocations = {};
  final Set<String> _manualIps = {};

  List<DlnaDevice> get currentDevices => List.unmodifiable(_devices);

  /// 検索開始
  void startSearch({int durationSec = 30}) {
    stopSearch();
    _currentScanSessionId++;
    final int mySessionId = _currentScanSessionId;

    _isSearching = true;
    print("[Discovery] === 検索を開始しました (ID: $mySessionId, タイムアウト: ${durationSec}秒) ===");

    _setupSocket();
    _searchLoop(mySessionId);

    Future.delayed(const Duration(milliseconds: 500), () {
      if (_currentScanSessionId == mySessionId) {
        _scanSubnet(mySessionId);
      }
    });

    Timer(Duration(seconds: durationSec), () {
      if (_isSearching && _currentScanSessionId == mySessionId) {
        print("[Discovery] タイムアウトにより検索状態を終了します");
        _isSearching = false;
      }
    });
  }

  /// 検索停止
  void stopSearch() {
    if (_isSearching) {
      print("[Discovery] === 検索を停止しました ===");
    }
    _isSearching = false;
    _searchTimer?.cancel();
    _socket?.close();
    _socket = null;
  }

  /// 手動IPの登録
  Future<void> verifyAndAddManualDevice(String ip, {String? customName}) async {
    if (_devices.any((d) => d.ip == ip)) return;
    print("[Discovery] 手動追加IPを確認中: $ip");
    _checkLanDevice(ip, _currentScanSessionId, customName: customName, isManual: true);
  }

  /// デバイス名の更新
  void updateDeviceName(String ip, String newName) {
    final index = _devices.indexWhere((d) => d.ip == ip);
    if (index != -1) {
      print("[Discovery] デバイス名更新: ${_devices[index].name} -> $newName");
      _devices[index] = _devices[index].copyWith(name: newName);
      _deviceStreamController.add(List.from(_devices));
    }
  }

  /// 強制追加
  void addForcedDevice(String ip, {String? customName}) {
    if (_devices.any((d) => d.ip == ip)) return;
    _checkLanDevice(ip, _currentScanSessionId, customName: customName, isManual: true);
  }

  /// 削除
  void removeDevice(String ip) {
    print("[Discovery] デバイス削除: $ip");
    _devices.removeWhere((d) => d.ip == ip);
    _manualIps.remove(ip);
    _deviceStreamController.add(List.from(_devices));
  }

  // --- Internal ---

  void _addDevice(DlnaDevice device) {
    final index = _devices.indexWhere((d) => d.ip == device.ip);

    if (index != -1) {
      final existing = _devices[index];

      String newName = existing.name;

      // 【修正】Kodi(...) などの汎用名判定を強化し、Fire TV等の名前で確実に上書きする
      bool isExistingGeneric = _isGenericName(existing.name);
      bool isNewFireTv = device.name.contains("Fire TV") || device.name.contains("Cast");

      if (isNewFireTv || (isExistingGeneric && !_isGenericName(device.name))) {
        newName = device.name;
      }

      int newPort = device.port;
      String newServiceType = device.serviceType;
      String newControlUrl = device.controlUrl;

      // 既存がKodi(8080)なのに、LANスキャン(0)で上書きしない
      if (existing.port == 8080 && device.port == 0) {
        newPort = existing.port;
        newServiceType = existing.serviceType;
        newControlUrl = existing.controlUrl;
      }

      _devices[index] = device.copyWith(
        name: newName,
        port: newPort,
        serviceType: newServiceType,
        controlUrl: newControlUrl,
      );
    } else {
      print("[Discovery] ★デバイス追加: ${device.name} (${device.ip})");
      _devices.add(device);
    }
    _deviceStreamController.add(List.from(_devices));
  }

  // 【修正】汎用名かどうかの判定ロジック強化
  bool _isGenericName(String name) {
    final lower = name.toLowerCase();
    final isIp = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}').hasMatch(name);

    // "Kodi" で始まるものすべて (例: "Kodi (192...)", "Kodi") は汎用とみなす
    final isKodiDefault = lower.startsWith('kodi') || lower.contains('unknown') || lower.contains('localhost');
    return isIp || isKodiDefault;
  }

  // --- LANスキャン機能 ---

  Future<void> _scanSubnet(int sessionId) async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      String? localIp;
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith("192.168.")) {
            localIp = addr.address;
            break;
          }
        }
        if (localIp != null) break;
      }

      if (localIp == null) return;

      final lastDot = localIp.lastIndexOf('.');
      final subnet = localIp.substring(0, lastDot + 1);

      List<String> targetIps = [];
      for (int i = 1; i < 255; i++) {
        final ip = "$subnet$i";
        if (ip != localIp) targetIps.add(ip);
      }

      // バッチ処理
      final int batchSize = 10;
      for (int i = 0; i < targetIps.length; i += batchSize) {
        if (_currentScanSessionId != sessionId || !_isSearching) return;

        int end = (i + batchSize < targetIps.length) ? i + batchSize : targetIps.length;
        List<String> batch = targetIps.sublist(i, end);

        await Future.wait(batch.map((ip) => _checkLanDevice(ip, sessionId)));
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (_) {}
  }

  // 指定IPの調査
  Future<void> _checkLanDevice(String ip, int sessionId, {String? customName, bool isManual = false}) async {
    if (!isManual && _currentScanSessionId != sessionId) return;

    // 【追加】ルーター (末尾 .1) を除外
    if (ip.endsWith('.1')) return;

    String? hostname;
    String? kodiSystemName;
    bool isKodi = false;
    bool isReachable = false;

    bool isFireTv = false;
    bool isCast = false;

    // 1. ホスト名逆引き
    try {
      final addr = await InternetAddress(ip).reverse().timeout(const Duration(milliseconds: 300));
      if (addr.host.isNotEmpty && addr.host != ip) {
        hostname = addr.host;
      }
    } catch (_) {}

    // 2. ポートスキャン
    final portsToCheck = [8080, 5555, 8009, 80];

    for (final port in portsToCheck) {
      if (!isManual && _currentScanSessionId != sessionId) return;

      Socket? socket;
      try {
        socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 200));
        isReachable = true;

        if (port == 8080) {
          isKodi = true;
          kodiSystemName = await _fetchKodiSystemName(ip);
        } else if (port == 5555) {
          isFireTv = true;
        } else if (port == 8009) {
          isCast = true;
        }

      } catch (e) {
        if (e is SocketException && e.osError != null) {
          if (e.osError!.errorCode == 111 || e.message.contains("refused")) {
            isReachable = true;
          }
        }
      } finally {
        try { socket?.destroy(); } catch (_) {}
      }

      if (isReachable && (isKodi || isFireTv || isCast)) break;
    }

    if (hostname != null || isKodi || isReachable || isManual) {

      String displayName = "";

      if (customName != null) {
        displayName = customName;
      } else if (kodiSystemName != null && !_isGenericName(kodiSystemName!)) {
        displayName = kodiSystemName!;
      } else {
        if (isFireTv) {
          displayName = "Fire TV ($ip)";
        } else if (isCast) {
          displayName = "Fire TV / Cast ($ip)";
        } else if (isKodi) {
          displayName = "Fire TV (Kodi) ($ip)";
        } else if (hostname != null) {
          if (hostname!.toLowerCase().contains('amazon') || hostname!.toLowerCase().contains('android')) {
            displayName = "Fire TV / Device ($ip)";
          } else {
            displayName = hostname!;
          }
        } else {
          displayName = "Unknown Device ($ip)";
        }
      }

      final device = DlnaDevice(
        ip: ip,
        name: displayName,
        originalName: displayName,
        controlUrl: isKodi ? "/jsonrpc" : "",
        serviceType: isKodi ? "kodi" : "lan",
        port: isKodi ? 8080 : 0,
        isManual: isManual,
      );

      _addDevice(device);
    }
  }

  Future<String?> _fetchKodiSystemName(String ip) async {
    try {
      final uri = Uri.parse('http://$ip:8080/jsonrpc');
      final body = {
        "jsonrpc": "2.0",
        "method": "System.GetProperties",
        "params": {"properties": ["friendlyname"]},
        "id": "name_check"
      };

      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      ).timeout(const Duration(milliseconds: 1000));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['result'] != null && data['result']['friendlyname'] != null) {
          String name = data['result']['friendlyname'];
          // 【修正】Kodiで始まる名前も無効として扱い、呼び出し側でFire TVなどに変換させる
          if (name.toLowerCase().startsWith('kodi') || name.toLowerCase() == 'localhost') {
            return null;
          }
          if (name.isNotEmpty) return name;
        }
      }
    } catch (_) {}
    return null;
  }

  // --- SSDP ---

  Future<void> _setupSocket() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket?.broadcastEnabled = true;
      _socket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            final message = utf8.decode(datagram.data);
            _handleResponse(message);
          }
        }
      });
    } catch (_) {}
  }

  void _searchLoop(int sessionId) async {
    if (!_isSearching || _currentScanSessionId != sessionId) return;
    await _sendMsearch();
    _searchTimer = Timer(const Duration(seconds: 5), () => _searchLoop(sessionId));
  }

  Future<void> _sendMsearch() async {
    if (_socket == null) return;
    const msg = 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 3\r\n'
        'ST: urn:schemas-upnp-org:service:AVTransport:1\r\n'
        '\r\n';
    try {
      _socket?.send(utf8.encode(msg), InternetAddress('239.255.255.250'), 1900);
    } catch (_) {}
  }

  void _handleResponse(String message) {
    final lines = message.split('\r\n');
    String? location;
    for (final line in lines) {
      if (line.toUpperCase().startsWith('LOCATION:')) {
        location = line.substring(9).trim();
        break;
      }
    }
    if (location != null) {
      _fetchDescription(location);
    }
  }

  Future<void> _fetchDescription(String url) async {
    if (_foundLocations.contains(url)) return;

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final deviceNode = document.findAllElements('device').firstOrNull;
        if (deviceNode == null) return;

        String friendlyName = deviceNode.findAllElements('friendlyName').firstOrNull?.innerText ?? "Unknown Device";

        // 【修正】SSDPで "Kodi..." と来たら "Fire TV (Kodi)" に強制変換
        if (friendlyName.toLowerCase().startsWith('kodi') || friendlyName.toLowerCase() == 'localhost') {
          friendlyName = "Fire TV (Kodi)";
        }

        print("[Discovery] SSDP検出: $friendlyName ($url)");

        final serviceList = deviceNode.findAllElements('service');
        String? controlUrl;
        String? serviceType;

        for (final service in serviceList) {
          final type = service.findAllElements('serviceType').firstOrNull?.innerText;
          if (type != null && type.contains('AVTransport')) {
            serviceType = type;
            controlUrl = service.findAllElements('controlURL').firstOrNull?.innerText;
            break;
          }
        }

        if (controlUrl != null && serviceType != null) {
          final uri = Uri.parse(url);
          final device = DlnaDevice(
            ip: uri.host,
            name: friendlyName,
            originalName: friendlyName,
            controlUrl: controlUrl,
            serviceType: serviceType,
            port: uri.port,
          );

          _foundLocations.add(url);
          _addDevice(device);
        }
      }
    } catch (_) {}
  }
}