import 'dart:async';
import '../services/dlna_service.dart';
import '../services/youtube_service.dart';
import '../models/playlist_model.dart';
import '../models/local_playlist_item.dart';
import '../services/playlist/playlist_storage_service.dart';
import '../services/playlist/playback_sequencer.dart';

export '../models/playlist_model.dart';
export '../models/local_playlist_item.dart';

class PlaylistManager {
  static final PlaylistManager _instance = PlaylistManager._internal();
  factory PlaylistManager() => _instance;

  // --- Services ---
  final PlaylistStorageService _storage = PlaylistStorageService();
  late final PlaybackSequencer _sequencer;
  final DlnaService _dlnaService = DlnaService();
  final YoutubeService _ytService = YoutubeService();

  // --- State ---
  List<PlaylistModel> _playlists = [];
  final StreamController<List<PlaylistModel>> _playlistsController = StreamController.broadcast();
  Stream<List<PlaylistModel>> get playlistsStream => _playlistsController.stream;

  List<PlaylistModel> get currentPlaylists => List.unmodifiable(_playlists);

  PlaylistManager._internal() {
    // シーケンサーの初期化（状態変化時に通知を受け取る）
    _sequencer = PlaybackSequencer(onStateChanged: _notifyListeners);

    _init();
  }

  Future<void> _init() async {
    // データのロード
    _playlists = await _storage.loadPlaylists();
    _notifyListeners();

    print("[Manager] Storage loaded. Listening for device connections...");

    // デバイス接続監視 -> セッション復元試行
    _dlnaService.connectedDeviceStream.listen((device) {
      if (device != null) {
        _attemptRestoreSession(device);
      }
    });
  }

  /// 変更通知と保存
  void _notifyListeners() {
    if (!_playlistsController.isClosed) {
      _playlistsController.add(List.from(_playlists));
    }
    _storage.savePlaylists(_playlists);
  }

  // --- Playlist CRUD ---

  void createPlaylist(String name) {
    final newPlaylist = PlaylistModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      items: [],
    );
    _playlists.add(newPlaylist);
    _notifyListeners();
  }

  void deletePlaylist(String id) {
    _playlists.removeWhere((p) => p.id == id);
    _notifyListeners();
  }

  void renamePlaylist(String id, String newName) {
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index != -1) {
      _playlists[index].name = newName;
      _notifyListeners();
    }
  }

  void reorderPlaylists(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _playlists.removeAt(oldIndex);
    _playlists.insert(newIndex, item);
    _notifyListeners();
  }

  // --- Item CRUD ---

  void removeItem(int index, {String? playlistId}) {
    final list = _getTargetPlaylist(playlistId);
    if (index >= 0 && index < list.items.length) {
      list.items.removeAt(index);
      _notifyListeners();
    }
  }

  void removeItems(Set<String> ids, {String? playlistId}) {
    final list = _getTargetPlaylist(playlistId);
    list.items.removeWhere((item) => ids.contains(item.id));
    _notifyListeners();
  }

  void moveItemToPlaylist(String itemId, {required String? fromPlaylistId, required String toPlaylistId}) {
    final fromList = _getTargetPlaylist(fromPlaylistId);
    final toList = _playlists.firstWhere((p) => p.id == toPlaylistId, orElse: () => fromList);

    if (fromList.id == toList.id) return;

    final itemIndex = fromList.items.indexWhere((i) => i.id == itemId);
    if (itemIndex != -1) {
      final item = fromList.items.removeAt(itemIndex);
      toList.items.add(item);
      _notifyListeners();
    }
  }

  void reorder(int oldIndex, int newIndex, {String? playlistId}) {
    final list = _getTargetPlaylist(playlistId);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = list.items.removeAt(oldIndex);
    list.items.insert(newIndex, item);
    _notifyListeners();
  }

  void clear({String? playlistId}) {
    final list = _getTargetPlaylist(playlistId);
    list.items.clear();
    _notifyListeners();
  }

  // --- External Import / Processing ---

  Future<String?> importFromYoutubePlaylist(String url) async {
    final playlistIdMatch = RegExp(r'[?&]list=([^#\&\?]+)').firstMatch(url);
    if (playlistIdMatch == null) return null;

    final playlistId = playlistIdMatch.group(1)!;
    final meta = await _ytService.getPlaylistDetails(playlistId);

    if (meta == null) return null;

    final newPlaylist = PlaylistModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: meta['title'] ?? 'Imported Playlist',
      items: [],
    );

    final videos = await _ytService.getPlaylistVideos(playlistId);
    for (var v in videos) {
      newPlaylist.items.add(LocalPlaylistItem(
        id: DateTime.now().microsecondsSinceEpoch.toString() + v['id'],
        title: v['title'],
        originalUrl: "https://www.youtube.com/watch?v=${v['id']}",
        thumbnailUrl: v['thumbnail'],
        durationStr: v['duration'] ?? '',
      ));
    }

    _playlists.add(newPlaylist);
    _notifyListeners();
    return newPlaylist.id;
  }

  /// 動画を追加し、必要であればデバイスへ送信する
  /// (CastLogicとの互換性のため dlnaService 引数を残すが、内部ではインスタンスを使用可能)
  Future<void> processAndAdd(
      DlnaService? dlnaService, // 互換用 (null可)
      Map<String, dynamic> metadata,
      {DlnaDevice? device,
        String? targetPlaylistId}) async {

    final list = _getTargetPlaylist(targetPlaylistId);

    final newItem = LocalPlaylistItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: metadata['title'],
      originalUrl: metadata['url'],
      thumbnailUrl: metadata['thumbnailUrl'],
      durationStr: metadata['duration'] ?? '',
    );

    list.items.add(newItem);
    _notifyListeners();

    // デバイス指定がある場合は即座にキュー追加などの処理を行う
    // (CastPageで「今すぐ再生」などが選ばれたわけではなく、追加処理の一部として実行される場合)
    // ただし現状のCastLogicは「リストに追加」のみ行い、再生は別途 playNow を呼ぶ設計にリファクタリング済み。
    // ここでは「リスト追加」のみで終了してよいが、もしデバイスへ即送信する要件があればここに記述する。
    // 今回はリスト追加のみとする。
  }

  // --- Playback Control (Delegated to Sequencer) ---

  Future<void> playSequence(DlnaDevice device, String playlistId, int startIndex) async {
    final playlist = _getTargetPlaylist(playlistId);
    await _sequencer.playSequence(device, playlist, startIndex);
  }

  void stopSession(DlnaDevice device) {
    _sequencer.stopSession();
    _dlnaService.stop(device); // 実際にデバイスも止める
  }

  /// 再生またはジャンプ
  Future<void> playOrJump(DlnaDevice device, String playlistId, int index) async {
    // 既に再生中のセッションと同じリスト・デバイスならジャンプ
    // そうでなければ新規シーケンス開始
    await playSequence(device, playlistId, index);
  }

  // --- Internal Helpers ---

  PlaylistModel _getTargetPlaylist(String? id) {
    if (_playlists.isEmpty) {
      // 空なら作成して返す
      final newPl = PlaylistModel(id: 'default', name: 'メインリスト', items: []);
      _playlists.add(newPl);
      return newPl;
    }
    if (id == null) return _playlists.first;
    return _playlists.firstWhere((p) => p.id == id, orElse: () => _playlists.first);
  }

  /// 接続復帰時の処理 (Kodiの状態を見て同期する)
  Future<void> _attemptRestoreSession(DlnaDevice device) async {
    // 簡易実装: 現在のアプリ内状態とKodiの状態を比較し、
    // 明らかに同期ずれがあればリセット等はせず、ログを出す程度にとどめる
    // 本格的な同期は複雑なため、Sequencerのmonitorに任せる
    try {
      final status = await _dlnaService.getPlayerStatus(device);
      if (status.isNotEmpty) {
        print("[Manager] Device is playing: ${status['file']}");
        // ここでアプリ側の playing state を復元するロジックを入れられる
      }
    } catch (_) {}
  }
}