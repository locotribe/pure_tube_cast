import 'dart:async';
import '../models/dlna_device.dart';
import 'dlna/dlna_discovery_service.dart';
import 'dlna/kodi_rpc_client.dart';
import 'dlna/dlna_soap_client.dart';
import 'dlna/wol_service.dart';

// モデルクラスをエクスポート
export '../models/dlna_device.dart';
export 'dlna/kodi_rpc_client.dart' show KodiPlaylistItem; // 必要に応じてエクスポート

class DlnaService {
  static final DlnaService _instance = DlnaService._internal();
  factory DlnaService() => _instance;

  DlnaService._internal();

  // --- サブサービス ---
  final DlnaDiscoveryService _discoveryService = DlnaDiscoveryService();
  final KodiRpcClient _kodiClient = KodiRpcClient();
  final DlnaSoapClient _soapClient = DlnaSoapClient();
  final WolService _wolService = WolService();

  // --- 状態管理 ---
  DlnaDevice? _currentDevice;
  final StreamController<DlnaDevice?> _connectedDeviceController = StreamController.broadcast();

  // --- 公開プロパティ ---

  Stream<DlnaDevice?> get connectedDeviceStream => _connectedDeviceController.stream;
  DlnaDevice? get currentDevice => _currentDevice;

  Stream<List<DlnaDevice>> get deviceStream => _discoveryService.deviceStream;
  List<DlnaDevice> get currentDevices => _discoveryService.currentDevices;

  // --- デバイス探索・管理 ---

  // DeviceViewLogicに合わせて引数名を `duration` に変更
  void startSearch({int duration = 15}) => _discoveryService.startSearch(durationSec: duration);

  void stopSearch() => _discoveryService.stopSearch();

  void setDevice(DlnaDevice? device) {
    _currentDevice = device;
    _connectedDeviceController.add(_currentDevice);
  }

  Future<bool> checkConnection(DlnaDevice device) async {
    if (_isKodi(device)) {
      try {
        await _kodiClient.getPlaylist(device);
        return true;
      } catch (e) {
        return false;
      }
    }
    return true;
  }

  Future<void> verifyAndAddManualDevice(String ip, {String? customName}) =>
      _discoveryService.verifyAndAddManualDevice(ip, customName: customName);

  void addForcedDevice(String ip, {String? customName}) =>
      _discoveryService.addForcedDevice(ip, customName: customName);

  void updateDeviceName(String ip, String newName) =>
      _discoveryService.updateDeviceName(ip, newName);

  void removeDevice(String ip) =>
      _discoveryService.removeDevice(ip);

  Future<void> sendWakeOnLan(String mac) => _wolService.sendWakeOnLan(mac);

  // --- 再生制御 (Control) ---

  // 位置引数呼び出しに対応するため、thumbnailUrlを [] で囲む (互換性維持)
  Future<void> playNow(DlnaDevice device, String url, String title, [String? thumbnailUrl]) async {
    if (_isKodi(device)) {
      await _kodiClient.playNow(device, url, title, thumbnailUrl: thumbnailUrl);
    } else {
      await _soapClient.castVideo(device, url, title);
    }
  }

  // 位置引数呼び出しに対応
  Future<void> addToPlaylist(DlnaDevice device, String url, String title, [String? thumbnailUrl]) async {
    if (_isKodi(device)) {
      await _kodiClient.addToPlaylist(device, url, title, thumbnailUrl: thumbnailUrl);
    } else {
      print("[DlnaService] addToPlaylist is not fully supported for generic DLNA via this method.");
    }
  }

  Future<void> stop(DlnaDevice device) async {
    if (_isKodi(device)) {
      await _kodiClient.stop(device);
    }
  }

  // PlaylistManagerが使用しているメソッド名 (getPlaylistItems) に合わせる
  Future<List<KodiPlaylistItem>> getPlaylistItems(DlnaDevice device) async {
    if (_isKodi(device)) {
      return await _kodiClient.getPlaylist(device);
    }
    return [];
  }

  // --- Kodi固有操作 & Alias for PlaylistManager ---

  // PlaylistManagerが使用しているメソッド名 (getPlayerStatus) を追加
  Future<Map<String, dynamic>> getPlayerStatus(DlnaDevice device) async {
    if (_isKodi(device)) {
      return await _kodiClient.getPlayerProperties(device);
    }
    return {};
  }

  // PlaylistManagerが使用しているメソッド名 (insertToPlaylist) を追加
  Future<void> insertToPlaylist(DlnaDevice device, int position, String url, String title, [String? thumbnailUrl]) async {
    if (_isKodi(device)) {
      await _kodiClient.insertItem(device, position, url, title, thumbnailUrl: thumbnailUrl);
    }
  }

  // PlaylistManagerが使用しているメソッド名 (playFromPlaylist) を追加
  Future<void> playFromPlaylist(DlnaDevice device, int index) async {
    if (_isKodi(device)) {
      await _kodiClient.jumpToItem(device, index);
    }
  }

  Future<void> clearPlaylist(DlnaDevice device) async {
    if (_isKodi(device)) await _kodiClient.clearPlaylist(device);
  }

  // jumpToItem も残しておく (Logicクラスなどで使っている場合のため)
  Future<void> jumpToItem(DlnaDevice device, int index) async {
    await _kodiClient.jumpToItem(device, index);
  }

  Future<void> removeItem(DlnaDevice device, int index) async {
    if (_isKodi(device)) await _kodiClient.removeItem(device, index);
  }

  Future<void> moveItem(DlnaDevice device, int oldIndex, int newIndex) async {
    if (_isKodi(device)) await _kodiClient.moveItem(device, oldIndex, newIndex);
  }

  Future<void> seek(DlnaDevice device, double percentage) async {
    if (_isKodi(device)) await _kodiClient.seek(device, percentage);
  }

  Future<void> setVolume(DlnaDevice device, int volume) async {
    if (_isKodi(device)) await _kodiClient.setVolume(device, volume);
  }

  // --- Helper ---

  bool _isKodi(DlnaDevice device) {
    return device.serviceType == 'kodi' ||
        device.serviceType.contains('XBMC') ||
        device.port == 8080 ||
        device.isManual;
  }
}