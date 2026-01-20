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

  // 検出済みデバイスのID管理 (重複排除用: location URLをキーにする)
  final Set<String> _foundLocations = {};

  // 手動で監視するIPリスト
  final Set<String> _manualIps = {};

  List<DlnaDevice> get currentDevices => List.unmodifiable(_devices);

  /// 検索開始
  void startSearch({int durationSec = 15}) {
    if (_isSearching) return;
    _isSearching = true;

    // 既存リストは維持しつつ、新規探索を開始
    // (クリアするかはアプリの要件によるが、ここでは維持して更新をかける)

    _setupSocket();
    _searchLoop();
  }

  /// 検索停止
  void stopSearch() {
    _isSearching = false;
    _searchTimer?.cancel();
    _socket?.close();
    _socket = null;
  }

  /// 手動IPの登録（検証して追加）
  Future<void> verifyAndAddManualDevice(String ip, {String? customName}) async {
    if (_devices.any((d) => d.ip == ip)) return;

    // Kodi (8080) チェック
    try {
      final kodiUrl = Uri.parse('http://$ip:8080/jsonrpc');
      final response = await http.post(
          kodiUrl,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"jsonrpc": "2.0", "method": "JSONRPC.Ping", "id": 1})
      ).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final device = DlnaDevice(
          ip: ip,
          name: customName ?? "Fire TV (Kodi)",
          originalName: "Fire TV (Kodi)",
          controlUrl: "/jsonrpc",
          serviceType: "kodi",
          port: 8080,
          isManual: true,
        );
        _addDevice(device);
        _manualIps.add(ip);
      }
    } catch (_) {
      // DLNAポートのチェックなどを追加可能
    }
  }

  /// デバイス名の更新 (UI側からのリネーム反映など)
  void updateDeviceName(String ip, String newName) {
    final index = _devices.indexWhere((d) => d.ip == ip);
    if (index != -1) {
      _devices[index] = _devices[index].copyWith(name: newName);
      _deviceStreamController.add(List.from(_devices));
    }
  }

  /// 強制的に手動IPとしてリストに追加 (起動時の復元用など)
  void addForcedDevice(String ip, {String? customName}) {
    if (_devices.any((d) => d.ip == ip)) return;

    final device = DlnaDevice(
      ip: ip,
      name: customName ?? "Saved Device ($ip)",
      originalName: "Saved Device",
      controlUrl: "/jsonrpc", // 仮置き
      serviceType: "unknown",
      port: 8080,
      isManual: true,
    );
    _addDevice(device);
    _manualIps.add(ip);
  }

  /// デバイスの削除
  void removeDevice(String ip) {
    _devices.removeWhere((d) => d.ip == ip);
    _manualIps.remove(ip);
    _deviceStreamController.add(List.from(_devices));
  }

  // --- Internal ---

  void _addDevice(DlnaDevice device) {
    // IPで重複チェック
    final index = _devices.indexWhere((d) => d.ip == device.ip);
    if (index != -1) {
      // 更新 (ポートや名前が変わっている可能性があるため)
      // ただしユーザーが設定した名前は保持したい場合は考慮が必要だが
      // ここではロジッククラス側(_customNames)で管理されている前提で上書きする
      _devices[index] = device;
    } else {
      _devices.add(device);
    }
    _deviceStreamController.add(List.from(_devices));
  }

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
    } catch (e) {
      print("[Discovery] Socket error: $e");
    }
  }

  void _searchLoop() async {
    if (!_isSearching) return;

    await _sendMsearch();

    // 手動IPリストも定期チェック（電源が入った瞬間に検知するため）
    for (var ip in _manualIps) {
      verifyAndAddManualDevice(ip); // 名前は既存維持されるはず
    }

    // 5秒ごとに再送信
    _searchTimer = Timer(const Duration(seconds: 5), _searchLoop);
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

        final friendlyName = deviceNode.findAllElements('friendlyName').firstOrNull?.innerText ?? "Unknown";
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