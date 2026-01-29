// lib/services/dlna_service.dart
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
  final String? macAddress;

  DlnaDevice({
    required this.ip,
    required this.name,
    required this.originalName,
    required this.controlUrl,
    required this.serviceType,
    required this.port,
    this.isManual = false,
    this.macAddress,
  });

  DlnaDevice copyWith({
    String? name,
    String? originalName,
    String? controlUrl,
    String? serviceType,
    int? port,
    bool? isManual,
    String? macAddress,
  }) {
    return DlnaDevice(
      ip: ip,
      name: name ?? this.name,
      originalName: originalName ?? this.originalName,
      controlUrl: controlUrl ?? this.controlUrl,
      serviceType: serviceType ?? this.serviceType,
      port: port ?? this.port,
      isManual: isManual ?? this.isManual,
      macAddress: macAddress ?? this.macAddress,
    );
  }
}

class KodiPlaylistItem {
  final String label;
  final String file;
  KodiPlaylistItem({required this.label, required this.file});

  factory KodiPlaylistItem.fromJson(Map<String, dynamic> json) {
    String name = json['title'] ?? '';
    if (name.isEmpty) {
      name = json['label'] ?? '';
    }
    return KodiPlaylistItem(
      label: name,
      file: json['file'] ?? '',
    );
  }
}

class DlnaService {
  static final DlnaService _instance = DlnaService._internal();
  factory DlnaService() => _instance;
  DlnaService._internal();

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

  Future<void> startSearch({int duration = 20, int targetCount = 3}) async {
    stopSearch();
    _isSearching = true;

    _foundDevices.removeWhere((d) => !d.isManual);
    _deviceStreamController.add(List.from(_foundDevices));

    _startSSDPSearch();
    _startSubnetScan();

    _searchTimer = Timer(Duration(seconds: duration), () {
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
    if (index != -1 && _foundDevices[index].isManual) {
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
      macAddress: index != -1 ? _foundDevices[index].macAddress : null,
    );
    _addDeviceToList(forcedDevice);
  }

  void _addDeviceToList(DlnaDevice device) {
    print("[DlnaService] Adding/Updating: ${device.name} (${device.ip}) Manual:${device.isManual}");
    final index = _foundDevices.indexWhere((d) => d.ip == device.ip);
    if (index != -1) {
      final existing = _foundDevices[index];
      _foundDevices[index] = device.copyWith(
        name: existing.isManual ? existing.name : device.name,
        isManual: existing.isManual || device.isManual,
        macAddress: existing.macAddress ?? device.macAddress,
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
        if (subnetPrefix != null) break;
      }

      subnetPrefix ??= "192.168.1.";

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
      final socket = await Socket.connect(ip, 8080, timeout: const Duration(milliseconds: 1000));
      socket.destroy();
      _addFallbackDevice(ip, port: 8080, customName: "Kodi? ($ip)");
      _fetchDeviceInfo('http://$ip:8080/description.xml', ip);
      return;
    } catch (e) {
    }

    try {
      final socket = await Socket.connect(ip, 5555, timeout: const Duration(milliseconds: 1000));
      socket.destroy();
      _addFallbackDevice(ip, port: 5555, customName: "FireTV/ADB");
    } catch (e) {
    }
  }

  Future<bool> checkConnection(DlnaDevice device) async {
    if (await _tryConnect(device.ip, device.port)) return true;
    if (device.port != 8080) {
      if (await _tryConnect(device.ip, 8080)) return true;
    }
    return false;
  }

  Future<bool> _tryConnect(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
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
        final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 1500));
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

  Future<void> sendWakeOnLan(String? mac) async {
    if (mac == null || mac.isEmpty) return;
    final String cleanMac = mac.replaceAll(':', '').replaceAll('-', '').trim();
    if (cleanMac.length != 12) return;
    try {
      final List<int> packet = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF];
      final List<int> macBytes = [];
      for (int i = 0; i < 12; i += 2) macBytes.add(int.parse(cleanMac.substring(i, i + 2), radix: 16));
      for (int i = 0; i < 16; i++) packet.addAll(macBytes);
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(packet, InternetAddress('255.255.255.255'), 9);
      socket.close();
      print("[WOL] Sent to $mac");
    } catch (e) { print("[WOL] Error: $e"); }
  }

  // Kodi操作系
  Future<void> playNow(DlnaDevice device, String videoUrl, String title, String? thumbnailUrl, {String? youtubeVideoId}) async {
    final String kodiUrl = youtubeVideoId != null
        ? "plugin://plugin.video.youtube/play/?video_id=$youtubeVideoId"
        : videoUrl;

    try {
      await _sendJsonRpc(device, "Playlist.Clear", {"playlistid": 1});
      await _sendJsonRpc(device, "Playlist.Add", {"playlistid": 1, "item": {"file": kodiUrl}});
      await _sendJsonRpc(device, "Player.Open", {"item": {"playlistid": 1, "position": 0}, "options": {"resume": false}});
    } catch (e) {
      // JSON-RPC失敗時はDLNAフォールバック
      await castVideoDlna(device, videoUrl, title);
    }
  }

  Future<void> addToPlaylist(DlnaDevice device, String videoUrl, String title, String? thumbnailUrl, {String? youtubeVideoId}) async {
    final String kodiUrl = youtubeVideoId != null
        ? "plugin://plugin.video.youtube/play/?video_id=$youtubeVideoId"
        : videoUrl;
    await _sendJsonRpc(device, "Playlist.Add", {"playlistid": 1, "item": {"file": kodiUrl}});
  }

  Future<void> insertToPlaylist(DlnaDevice device, int position, String videoUrl, String title, String? thumbnailUrl, {String? youtubeVideoId}) async {
    final String kodiUrl = youtubeVideoId != null
        ? "plugin://plugin.video.youtube/play/?video_id=$youtubeVideoId"
        : videoUrl;
    await _sendJsonRpc(device, "Playlist.Insert", {"playlistid": 1, "position": position, "item": {"file": kodiUrl}});
  }

  Future<void> playFromPlaylist(DlnaDevice device, int index) async => await _sendJsonRpc(device, "Player.Open", {"item": {"playlistid": 1, "position": index}});
  Future<void> movePlaylistItem(DlnaDevice device, int fromIndex, int toIndex) async => await _sendJsonRpc(device, "Playlist.Move", {"playlistid": 1, "item": fromIndex, "to": toIndex});
  Future<void> removeFromPlaylist(DlnaDevice device, int index) async => await _sendJsonRpc(device, "Playlist.Remove", {"playlistid": 1, "position": index});
  Future<void> clearPlaylist(DlnaDevice device) async => await _sendJsonRpc(device, "Playlist.Clear", {"playlistid": 1});

  Future<Map<String, dynamic>?> getPlayerStatus(DlnaDevice device) async {
    try {
      final props = await _sendJsonRpc(device, "Player.GetProperties", {"playerid": 1, "properties": ["position", "time", "totaltime"]});
      final item = await _sendJsonRpc(device, "Player.GetItem", {"playerid": 1, "properties": ["title", "file"]});
      if (props != null && item != null && item['item'] != null) {
        String name = item['item']['title'] ?? item['item']['label'] ?? '';
        int totalSeconds = 0;
        if (props['totaltime'] != null) {
          final t = props['totaltime'];
          totalSeconds = ((t['hours'] ?? 0) * 3600) + ((t['minutes'] ?? 0) * 60) + (t['seconds'] ?? 0);
        }
        return {'position': props['position'] ?? 0, 'title': name, 'totalSeconds': totalSeconds};
      }
    } catch (e) { }
    return null;
  }

  Future<List<KodiPlaylistItem>> getPlaylistItems(DlnaDevice device) async {
    try {
      final result = await _sendJsonRpc(device, "Playlist.GetItems", {"playlistid": 1, "properties": ["title", "file"], "limits": {"start": 0, "end": 100}});
      if (result != null && result['items'] != null) {
        return (result['items'] as List).map((e) => KodiPlaylistItem.fromJson(e)).toList();
      }
    } catch (e) { }
    return [];
  }

  // 【修正】タイムアウトを10秒に延長し、エラーハンドリングを強化
  Future<dynamic> _sendJsonRpc(DlnaDevice device, String method, Map<String, dynamic> params) async {
    // 優先順位: 1. 8080 (Kodi標準) 2. device.port (手動設定等)
    // 通常は8080固定だが、タイムアウト対策としてポート指定を少し柔軟にする検討も可能
    // ここでは安全のため標準の8080を使用しつつタイムアウトを延長
    final kodiUrl = Uri.parse('http://${device.ip}:8080/jsonrpc');

    final body = jsonEncode({"jsonrpc": "2.0", "method": method, "params": params, "id": 1});

    // タイムアウトを10秒に設定
    final response = await http.post(kodiUrl, headers: {'Content-Type': 'application/json'}, body: body).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded.containsKey('error')) throw Exception("Kodi Error: ${decoded['error']}");
      return decoded['result'];
    }
    throw Exception("HTTP Error ${response.statusCode}");
  }

  Future<void> castVideoDlna(DlnaDevice device, String videoUrl, String title) async {
    final fullControlUrl = 'http://${device.ip}:${device.port}${device.controlUrl}';
    await _sendSoap(fullControlUrl, device.serviceType, 'SetAVTransportURI', {'InstanceID': '0', 'CurrentURI': videoUrl, 'CurrentURIMetaData': ''});
    await _sendSoap(fullControlUrl, device.serviceType, 'Play', {'InstanceID': '0', 'Speed': '1'});
  }

  Future<void> _sendSoap(String url, String serviceType, String action, Map<String, String> args) async {
    String argsXml = args.entries.map((e) => "<${e.key}>${e.value}</${e.key}>").join();
    String soap = '''<?xml version="1.0" encoding="utf-8"?><s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:$action xmlns:u="$serviceType">$argsXml</u:$action></s:Body></s:Envelope>''';
    // タイムアウトを10秒に設定
    await http.post(Uri.parse(url), headers: {'Content-Type': 'text/xml; charset="utf-8"', 'SOAPAction': '"$serviceType#$action"'}, body: soap).timeout(const Duration(seconds: 10));
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

  // ==========================================
  // リモコン機能
  // ==========================================

  Future<Map<String, dynamic>?> getPlayerPropertiesForRemote(DlnaDevice device) async {
    try {
      final playerProps = await _sendJsonRpc(device, "Player.GetProperties", {
        "playerid": 1,
        "properties": ["time", "totaltime", "speed", "percentage"]
      });
      final appProps = await _sendJsonRpc(device, "Application.GetProperties", {
        "properties": ["volume", "muted"]
      });
      final itemProps = await _sendJsonRpc(device, "Player.GetItem", {
        "playerid": 1,
        "properties": ["title", "thumbnail"]
      });

      if (playerProps == null || appProps == null) return null;

      int currentSec = 0;
      if (playerProps['time'] != null) {
        final t = playerProps['time'];
        currentSec = ((t['hours'] ?? 0) * 3600) + ((t['minutes'] ?? 0) * 60) + (t['seconds'] ?? 0);
      }

      int totalSec = 0;
      if (playerProps['totaltime'] != null) {
        final t = playerProps['totaltime'];
        totalSec = ((t['hours'] ?? 0) * 3600) + ((t['minutes'] ?? 0) * 60) + (t['seconds'] ?? 0);
      }

      String title = "";
      String thumbnail = "";
      if (itemProps != null && itemProps['item'] != null) {
        title = itemProps['item']['title'] ?? itemProps['item']['label'] ?? "";
      }

      return {
        'time': currentSec,
        'totaltime': totalSec,
        'speed': playerProps['speed'] ?? 0,
        'volume': appProps['volume'] ?? 0,
        'muted': appProps['muted'] ?? false,
        'title': title,
        'thumbnail': thumbnail,
      };
    } catch (e) {
      return null;
    }
  }

  Future<void> togglePlayPause(DlnaDevice device) async {
    try {
      await _sendJsonRpc(device, "Player.PlayPause", {"playerid": 1, "play": "toggle"});
    } catch (e) {
      print("[DlnaService] togglePlayPause failed: $e");
    }
  }

  Future<void> skipPrevious(DlnaDevice device) async {
    await _sendJsonRpc(device, "Player.GoTo", {"playerid": 1, "to": "previous"});
  }

  Future<void> skipNext(DlnaDevice device) async {
    await _sendJsonRpc(device, "Player.GoTo", {"playerid": 1, "to": "next"});
  }

  Future<void> setVolume(DlnaDevice device, int volume) async {
    await _sendJsonRpc(device, "Application.SetVolume", {"volume": volume});
  }

  Future<void> changeSpeed(DlnaDevice device, String direction) async {
    try {
      await _sendJsonRpc(device, "Player.SetSpeed", {
        "playerid": 1,
        "speed": direction
      });
    } catch (e) {
      print("[DlnaService] changeSpeed failed: $e");
    }
  }

  Future<void> changeTempo(DlnaDevice device, String direction) async {
    try {
      String action = direction == "increment" ? "tempoup" : "tempodown";
      await _sendJsonRpc(device, "Input.ExecuteAction", {"action": action});
    } catch (e) {
      print("[DlnaService] changeTempo failed: $e");
    }
  }

  Future<void> resetSpeed(DlnaDevice device) async {
    try {
      await _sendJsonRpc(device, "Player.SetSpeed", {
        "playerid": 1,
        "speed": 1
      });
    } catch (e) {
      print("[DlnaService] resetSpeed failed: $e");
    }
  }

  Future<void> seekRelative(DlnaDevice device, int secondsOffset) async {
    try {
      final props = await _sendJsonRpc(device, "Player.GetProperties", {
        "playerid": 1,
        "properties": ["time", "totaltime"]
      });
      if (props == null) return;

      final t = props['time'];
      int currentSec = ((t['hours'] ?? 0) * 3600) + ((t['minutes'] ?? 0) * 60) + (t['seconds'] ?? 0);

      int totalSec = 0;
      if (props['totaltime'] != null) {
        final tt = props['totaltime'];
        totalSec = ((tt['hours'] ?? 0) * 3600) + ((tt['minutes'] ?? 0) * 60) + (tt['seconds'] ?? 0);
      }

      if (totalSec == 0) return;

      int targetSec = currentSec + secondsOffset;
      if (targetSec < 0) targetSec = 0;
      if (targetSec > totalSec) targetSec = totalSec;

      double progress = (targetSec / totalSec) * 100.0;

      await _sendJsonRpc(device, "Player.Seek", {
        "playerid": 1,
        "value": {
          "percentage": progress
        }
      });

    } catch (e) {
      print("[DlnaService] Seek error: $e");
    }
  }

  Future<void> setSpeed(DlnaDevice device, double speed) async {
    try {
      await _sendJsonRpc(device, "Player.SetSpeed", {
        "playerid": 1,
        "speed": speed
      });
    } catch (e) {
      print("[DlnaService] setSpeed failed: $e");
    }
  }

  Future<void> executeAction(DlnaDevice device, String action) async {
    try {
      await _sendJsonRpc(device, "Input.ExecuteAction", {"action": action});
    } catch (e) {
      print("[DlnaService] executeAction failed: $e");
    }
  }

  Future<void> seekTo(DlnaDevice device, double percentage) async {
    try {
      await _sendJsonRpc(device, "Player.Seek", {
        "playerid": 1,
        "value": {
          "percentage": percentage
        }
      });
    } catch (e) {
      print("[DlnaService] seekTo failed: $e");
    }
  }
}