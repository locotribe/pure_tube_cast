import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../managers/playlist_manager.dart';
import '../services/dlna_service.dart';
import '../services/video_resolver.dart';

class CastLogic {
  final VideoResolver _resolver = VideoResolver();
  final DlnaService _dlnaService = DlnaService();
  final PlaylistManager _playlistManager = PlaylistManager();

  // Androidネイティブのメソッドチャンネル (アプリ最小化用)
  static const platform = MethodChannel('com.example.pure_tube_cast/app_control');

  /// URLから動画メタデータを取得する
  Future<Map<String, dynamic>?> resolveVideo(String url) async {
    final match = RegExp(r'(https?://\S+)').firstMatch(url);
    final targetUrl = match?.group(0) ?? url;
    return await _resolver.resolveMetadata(targetUrl);
  }

  /// 現在のプレイリスト一覧を取得する
  List<PlaylistModel> getPlaylists() {
    return _playlistManager.currentPlaylists;
  }

  /// 新規プレイリストを作成する
  void createPlaylist(String name) {
    _playlistManager.createPlaylist(name);
  }

  /// 動画をローカルのプレイリストに追加する
  /// (URL解決もバックグラウンドで開始される)
  Future<void> addToLocalPlaylist(Map<String, dynamic> metadata, String targetPlaylistId) async {
    await _playlistManager.processAndAdd(
        _dlnaService,
        metadata,
        device: null, // ここでは自動送信せず、リスト追加のみ行う
        targetPlaylistId: targetPlaylistId
    );
  }

  /// 再生用のストリームURLを解決する
  Future<String?> resolveStreamUrl(Map<String, dynamic> metadata) async {
    return await _resolver.resolveStreamUrl(metadata);
  }

  /// 現在接続中のDLNAデバイスを取得する
  DlnaDevice? getCurrentDevice() {
    return _dlnaService.currentDevice;
  }

  /// デバイスで「今すぐ再生」を実行する (プレイリストをクリアして再生)
  Future<void> playNowOnDevice(DlnaDevice device, String streamUrl, Map<String, dynamic> metadata) async {
    await _dlnaService.playNow(
        device,
        streamUrl,
        metadata['title'],
        metadata['thumbnailUrl']
    );
  }

  /// デバイスのプレイリストに追加する
  Future<void> addToDevicePlaylist(DlnaDevice device, String streamUrl, Map<String, dynamic> metadata) async {
    await _dlnaService.addToPlaylist(
        device,
        streamUrl,
        metadata['title'],
        metadata['thumbnailUrl']
    );
  }

  /// アプリを最小化する (バックグラウンドへ移動)
  Future<void> minimizeApp() async {
    try {
      await platform.invokeMethod('moveTaskToBack');
    } catch (e) {
      print("[CastLogic] Failed to minimize: $e");
    }
  }

  /// URLを外部ブラウザで開く
  Future<void> openInBrowser(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}