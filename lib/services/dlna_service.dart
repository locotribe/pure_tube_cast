import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class DlnaDevice {
  final String ip;
  final String name;
  final String originalName;
  final String controlUrl;
  final String serviceType;
  final int port;
  final bool isManual;

  DlnaDevice({
    required this.ip,
    required this.name,
    required this.originalName,
    required this.controlUrl,
    required this.serviceType,
    required this.port,
    this.isManual = false,
  });

  DlnaDevice copyWith({
    String? name,
    String? originalName,
    String? controlUrl,
    String? serviceType,
    int? port,
    bool? isManual,
  }) {
    return DlnaDevice(
      ip: ip,
      name: name ?? this.name,
      originalName: originalName ?? this.originalName,
      controlUrl: controlUrl ?? this.controlUrl,
      serviceType: serviceType ?? this.serviceType,
      port: port ?? this.port,
      isManual: isManual ?? this.isManual,
    );
  }
}

class PlaylistItem {
  final String label;
  final String file;
  final String? thumbnailUrl;
  final int duration;

  PlaylistItem({
    required this.label,
    required this.file,
    this.thumbnailUrl,
    this.duration = 0,
  });

  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    String? thumb = json['thumbnail'];
    if (thumb != null && thumb.isEmpty) thumb = null;

    if (thumb != null && thumb.startsWith('image://')) {
      try {
        thumb = Uri.decodeComponent(thumb.substring(8, thumb.length - 1));
      } catch (e) { }
    }

    return PlaylistItem(
      label: json['label'] ?? 'Unknown',
      file: json['file'] ?? '',
      thumbnailUrl: thumb,
      duration: json['duration'] ?? 0,
    );
  }
}

class DlnaService {
  static final DlnaService _instance = DlnaService._internal();
  factory DlnaService() => _instance;
  DlnaService._internal();

  // --- 接続状態管理 ---
  DlnaDevice? _currentDevice;
  final _connectedDeviceController = StreamController<DlnaDevice?>.broadcast();
  Stream<DlnaDevice?> get connectedDeviceStream => _connectedDeviceController.stream;
  DlnaDevice? get currentDevice => _currentDevice;

  void setDevice(DlnaDevice? device) {
    _currentDevice = device;
    _connectedDeviceController.add(_currentDevice);
    print("[DlnaService] Connected device set to: ${device?.name ?? 'None'} (${device?.ip})");
  }

  final _deviceStreamController = StreamController<List<DlnaDevice>>.broadcast();
  Stream<List<DlnaDevice>> get deviceStream => _deviceStreamController.stream;

  List<DlnaDevice> _foundDevices = [];
  RawDatagramSocket? _socket;
  Timer? _searchTimer;
  bool _isSearching = false;

  void removeDevice(String ip) {
    print("[DEBUG] Removing device: $ip");
    _foundDevices.removeWhere((d) => d.ip == ip);
    _deviceStreamController.add(List.from(_foundDevices));
  }

  void updateDeviceName(String ip, String newName) {
    final index = _foundDevices.indexWhere((d) => d.ip == ip);
    if (index != -1) {
      _foundDevices[index] = _foundDevices[index].copyWith(name: newName);
      _deviceStreamController.add(List.from(_foundDevices));
    }
  }

  // --- 検索機能 ---
  Future<void> startSearch({int duration = 20, int targetCount = 3}) async {
    stopSearch();
    _isSearching = true;
    print("[DEBUG] Search: Start (Duration: ${duration}s)");

    _foundDevices.removeWhere((d) => !d.isManual);
    _deviceStreamController.add(List.from(_foundDevices));

    _startSSDPSearch();
    _startSubnetScan();

    _searchTimer = Timer(Duration(seconds: duration), () {
      print("[DEBUG] Search: Timeout reached. Stopping.");
      stopSearch();
    });
  }

  Future<void> _startSSDPSearch() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket?.broadcastEnabled = true;
      _socket?.readEventsEnabled = true;
      _socket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            final msg = utf8.decode(datagram.data);
            _parseResponse(msg, datagram.address);
          }
        }
      });
      const searchMsg =
          'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 3\r\n'
          'ST: urn:schemas-upnp-org:service:AVTransport:1\r\n'
          '\r\n';
      final data = utf8.encode(searchMsg);
      final multicastAddress = InternetAddress('239.255.255.250');
      for (int i = 0; i < 3; i++) {
        if (!_isSearching) break;
        _socket?.send(data, multicastAddress, 1900);
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (e) { }
  }

  void _parseResponse(String msg, InternetAddress address) {
    int detectedPort = 8080;
    String? locationUrl;

    final locationRegExp = RegExp(r'LOCATION: (http://.+)', caseSensitive: false);
    final match = locationRegExp.firstMatch(msg);
    if (match != null) {
      locationUrl = match.group(1)!;
      try {
        final uri = Uri.parse(locationUrl);
        detectedPort = uri.port;
      } catch (e) { }
    }

    _addFallbackDevice(address.address, port: detectedPort, customName: "Found (Port $detectedPort)");

    if (locationUrl != null) {
      _fetchDeviceInfo(locationUrl, address.address);
    }
  }

  Future<void> _fetchDeviceInfo(String url, String ip) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        _parseAndAddDevice(response.body, ip, uri.port, false);
      }
    } catch (e) { }
  }

  bool _parseAndAddDevice(String xmlContent, String ip, int port, bool isManual) {
    try {
      final document = XmlDocument.parse(xmlContent);
      final friendlyName = document.findAllElements('friendlyName').firstOrNull?.text ?? "Unknown Device";

      String? controlPath;
      String? serviceType;

      final services = document.findAllElements('service');
      for (var service in services) {
        final type = service.findAllElements('serviceType').firstOrNull?.text ?? "";
        if (type.toLowerCase().contains('avtransport')) {
          serviceType = type;
          controlPath = service.findAllElements('controlURL').firstOrNull?.text;
          break;
        }
      }

      if (controlPath != null && serviceType != null) {
        if (!controlPath.startsWith('/')) controlPath = '/$controlPath';

        final device = DlnaDevice(
          ip: ip,
          name: friendlyName,
          originalName: friendlyName,
          controlUrl: controlPath,
          serviceType: serviceType,
          port: port,
          isManual: isManual,
        );
        _addDeviceToList(device);
        return true;
      }
    } catch (e) { }
    return false;
  }

  void _addFallbackDevice(String ip, {int port = 8080, String? customName}) {
    final index = _foundDevices.indexWhere((d) => d.ip == ip);
    if (index != -1 && !_foundDevices[index].name.startsWith("Found") && !_foundDevices[index].name.startsWith("Manual")) {
      return;
    }

    final device = DlnaDevice(
      ip: ip,
      name: customName ?? "Found Device ($ip)",
      originalName: "Unknown Device",
      controlUrl: '/upnp/service/AVTransport/control',
      serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
      port: port,
      isManual: false,
    );
    _addDeviceToList(device);
  }

  void addForcedDevice(String ip, {String? customName}) {
    final index = _foundDevices.indexWhere((d) => d.ip == ip);
    final port = index != -1 ? _foundDevices[index].port : 8080;

    final forcedDevice = DlnaDevice(
      ip: ip,
      name: customName ?? "Manual ($ip)",
      originalName: "Manual",
      controlUrl: '/upnp/service/AVTransport/control',
      serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
      port: port,
      isManual: true,
    );
    _addDeviceToList(forcedDevice);
  }

  void _addDeviceToList(DlnaDevice device) {
    final index = _foundDevices.indexWhere((d) => d.ip == device.ip);
    if (index != -1) {
      final existing = _foundDevices[index];
      _foundDevices[index] = device.copyWith(
        name: existing.isManual ? existing.name : device.name,
        isManual: existing.isManual,
      );
    } else {
      _foundDevices.add(device);
    }
    _deviceStreamController.add(List.from(_foundDevices));
  }

  Future<void> _startSubnetScan() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      String? currentIp;
      String? subnetPrefix;
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168.')) {
            currentIp = addr.address;
            subnetPrefix = currentIp.substring(0, currentIp.lastIndexOf('.') + 1);
            break;
          }
        }
      }
      if (subnetPrefix == null) return;

      final List<Future> checks = [];
      for (int i = 1; i < 255; i++) {
        if (!_isSearching) break;
        final targetIp = "$subnetPrefix$i";
        if (targetIp == currentIp) continue;
        checks.add(_checkPortOpen(targetIp));
        if (checks.length >= 30) {
          await Future.wait(checks);
          checks.clear();
        }
      }
      await Future.wait(checks);
    } catch (e) { }
  }

  Future<void> _checkPortOpen(String ip) async {
    if (_foundDevices.any((d) => d.ip == ip)) return;
    try {
      final socket = await Socket.connect(ip, 8080, timeout: const Duration(seconds: 1));
      socket.destroy();
      _addFallbackDevice(ip, port: 8080, customName: "VLC/Web ($ip)");
      _fetchDeviceInfo('http://$ip:8080/description.xml', ip);
    } catch (e) { }
  }

  Future<bool> checkConnection(DlnaDevice device) async {
    try {
      final socket = await Socket.connect(device.ip, device.port, timeout: const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyAndAddManualDevice(String ip, {String? customName}) async {
    final portsToTry = [8080, 58693, 49152, 49153, 1024, 1865];
    for (var port in portsToTry) {
      try {
        final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 800));
        socket.destroy();
        final forcedDevice = DlnaDevice(
          ip: ip,
          name: customName ?? "Manual ($ip)",
          originalName: "Manual",
          controlUrl: '/upnp/service/AVTransport/control',
          serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
          port: port,
          isManual: true,
        );
        _addDeviceToList(forcedDevice);
        _fetchDeviceInfo('http://$ip:$port/description.xml', ip);
        return true;
      } catch (e) { }
    }
    addForcedDevice(ip, customName: customName);
    return false;
  }

  // ====================================================================
  // Kodi プレイリスト操作
  // ====================================================================

  /// 1. 今すぐ再生 (割り込み)
  Future<void> playNow(DlnaDevice device, String videoUrl, String title, String? thumbnailUrl) async {
    print("[DlnaService] playNow called: $title");
    try {
      await _sendJsonRpc(device, "Playlist.Clear", {"playlistid": 1});
      await _sendJsonRpc(device, "Playlist.Add", {
        "playlistid": 1,
        "item": {"file": videoUrl}
      });
      await _sendJsonRpc(device, "Player.Open", {
        "item": {"playlistid": 1, "position": 0},
        "options": {"resume": false}
      });
      print("[DlnaService] playNow sent successfully");
      return;
    } catch (e) {
      print("[DlnaService] playNow failed with JSON-RPC: $e. Trying DLNA Fallback...");
      await castVideoDlna(device, videoUrl, title);
    }
  }

  /// 2. リストに追加
  Future<void> addToPlaylist(DlnaDevice device, String videoUrl, String title, String? thumbnailUrl) async {
    print("[DlnaService] addToPlaylist called: $title");
    try {
      await _sendJsonRpc(device, "Playlist.Add", {
        "playlistid": 1,
        "item": {"file": videoUrl}
      });
      print("[DlnaService] addToPlaylist sent successfully");
    } catch (e) {
      print("[DlnaService] addToPlaylist failed: $e");
      throw Exception("Kodiへの接続に失敗しました");
    }
  }

  /// 3. リスト内の指定位置を再生
  Future<void> playFromPlaylist(DlnaDevice device, int index) async {
    print("[DlnaService] playFromPlaylist called. Index: $index");
    try {
      await _sendJsonRpc(device, "Player.Open", {
        "item": {"playlistid": 1, "position": index}
      });
      print("[DlnaService] playFromPlaylist sent successfully");
    } catch (e) {
      print("[DlnaService] playFromPlaylist failed: $e");
      rethrow;
    }
  }

  /// 4. リスト項目の移動 (並べ替え)
  Future<void> movePlaylistItem(DlnaDevice device, int fromIndex, int toIndex) async {
    print("[DlnaService] movePlaylistItem: $fromIndex -> $toIndex");
    await _sendJsonRpc(device, "Playlist.Move", {
      "playlistid": 1,
      "item": fromIndex,
      "to": toIndex
    });
  }

  /// 5. リスト項目の削除
  Future<void> removeFromPlaylist(DlnaDevice device, int index) async {
    print("[DlnaService] removeFromPlaylist: $index");
    await _sendJsonRpc(device, "Playlist.Remove", {
      "playlistid": 1,
      "position": index
    });
  }

  // --- 共通 JSON-RPC 送信 ---
  Future<dynamic> _sendJsonRpc(DlnaDevice device, String method, Map<String, dynamic> params) async {
    final kodiUrl = Uri.parse('http://${device.ip}:8080/jsonrpc');
    final body = jsonEncode({
      "jsonrpc": "2.0",
      "method": method,
      "params": params,
      "id": 1
    });

    print("[DlnaService] Sending JSON-RPC to ${device.ip}: $method");
    print("[DlnaService] Params: $params");

    try {
      final response = await http.post(
          kodiUrl,
          headers: {'Content-Type': 'application/json'},
          body: body
      ).timeout(const Duration(seconds: 5));

      print("[DlnaService] Response Status: ${response.statusCode}");

      if (response.statusCode == 200) {
        // レスポンスが長すぎる場合に見やすくする工夫は必要ですが、まずはそのまま表示
        print("[DlnaService] Response Body: ${response.body}");

        final decoded = jsonDecode(response.body);
        if (decoded.containsKey('error')) {
          print("[DlnaService] JSON-RPC Error Detected: ${decoded['error']}");
          throw Exception("Kodi Error: ${decoded['error']}");
        }
        return decoded['result'];
      } else {
        print("[DlnaService] HTTP Error Body: ${response.body}");
      }
    } catch (e) {
      print("[DlnaService] Exception during request: $e");
      rethrow;
    }
  }

  // --- 旧 DLNAキャスト ---
  Future<void> castVideoDlna(DlnaDevice device, String videoUrl, String title) async {
    final fullControlUrl = 'http://${device.ip}:${device.port}${device.controlUrl}';
    print("[DlnaService] Fallback to DLNA Cast: $fullControlUrl");
    try {
      await _sendSoap(fullControlUrl, device.serviceType, 'SetAVTransportURI', {
        'InstanceID': '0',
        'CurrentURI': videoUrl,
        'CurrentURIMetaData': '',
      });
      await _sendSoap(fullControlUrl, device.serviceType, 'Play', {
        'InstanceID': '0',
        'Speed': '1',
      });
    } catch (e) {
      print("[DlnaService] DLNA Cast failed: $e");
      throw Exception("DLNA送信失敗");
    }
  }

  Future<void> _sendSoap(String url, String serviceType, String action, Map<String, String> args) async {
    String argsXml = args.entries.map((e) => "<${e.key}>${e.value}</${e.key}>").join();
    String soap = '''<?xml version="1.0" encoding="utf-8"?>
    <s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
      <s:Body>
        <u:$action xmlns:u="$serviceType">$argsXml</u:$action>
      </s:Body>
    </s:Envelope>''';

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'text/xml; charset="utf-8"',
        'SOAPAction': '"$serviceType#$action"',
      },
      body: soap,
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw Exception("SOAP Error ${response.statusCode}");
    }
  }

  void _stopSocketOnly() {
    _socket?.close();
    _socket = null;
  }

  void stopSearch() {
    if (_isSearching) {
      _isSearching = false;
      _searchTimer?.cancel();
      _stopSocketOnly();
    }
  }
}