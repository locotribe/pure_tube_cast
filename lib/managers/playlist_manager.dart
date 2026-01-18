import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dlna_service.dart';
import '../services/youtube_service.dart';
import '../models/playlist_model.dart';
import '../models/local_playlist_item.dart';

export '../models/playlist_model.dart';
export '../models/local_playlist_item.dart';

class PlaylistManager {
  static final PlaylistManager _instance = PlaylistManager._internal();
  factory PlaylistManager() => _instance;

  PlaylistManager._internal() {
    _loadFromStorage();
  }

  final List<PlaylistModel> _playlists = [];
  final StreamController<List<PlaylistModel>> _playlistsController = StreamController.broadcast();
  Stream<List<PlaylistModel>> get playlistsStream => _playlistsController.stream;

  final StreamController<List<LocalPlaylistItem>> _itemsController = StreamController.broadcast();
  Stream<List<LocalPlaylistItem>> get itemsStream => _itemsController.stream;

  final YoutubeService _ytService = YoutubeService();

  // 監視用タイマー
  Timer? _monitorTimer;
  // 最後に再生を開始したインデックス (Kodiの0番目に対応するアプリ側のインデックス)
  int _sessionStartIndex = 0;

  List<PlaylistModel> get currentPlaylists => _playlists;
  List<LocalPlaylistItem> get currentItems => _playlists.isNotEmpty ? _playlists.first.items : [];

  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonStr = jsonEncode(_playlists.map((e) => e.toJson()).toList());
    await prefs.setString('saved_playlists_v2', jsonStr);
    _notifyListeners();
  }

  void _notifyListeners() {
    _playlistsController.add(List.from(_playlists));
    if (_playlists.isNotEmpty) {
      _itemsController.add(List.from(_playlists.first.items));
    } else {
      _itemsController.add([]);
    }
  }

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final String? newJsonStr = prefs.getString('saved_playlists_v2');

    if (newJsonStr != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(newJsonStr);
        _playlists.clear();
        _playlists.addAll(jsonList.map((e) => PlaylistModel.fromJson(e)).toList());
      } catch (e) {
        print("[Manager] Load new data failed: $e");
      }
    } else {
      final String? oldJsonStr = prefs.getString('saved_playlist');
      if (oldJsonStr != null) {
        try {
          final List<dynamic> jsonList = jsonDecode(oldJsonStr);
          final oldItems = jsonList.map((e) => LocalPlaylistItem.fromJson(e)).toList();
          final mainList = PlaylistModel(id: 'default_main', name: 'メインリスト', items: oldItems.cast<LocalPlaylistItem>());
          _playlists.add(mainList);
          await _saveToStorage();
        } catch (e) {}
      }
    }
    _notifyListeners();
  }

  // --- 監視システム ---
  void _startMonitor(DlnaDevice device, String playlistId) {
    _monitorTimer?.cancel();

    // 3秒おきにKodiの状態を確認
    _monitorTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final status = await DlnaService().getPlayerStatus(device);
      if (status != null) {
        final int kodiPosition = status['position'];
        // Kodiの0番目 = アプリの _sessionStartIndex 番目
        // したがって、現在の再生動画 = _sessionStartIndex + kodiPosition
        final int currentAppIndex = _sessionStartIndex + kodiPosition;

        _syncPlayingStatus(playlistId, currentAppIndex);
      }
    });
  }

  void _syncPlayingStatus(String playlistId, int playingIndex) {
    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex == -1) return;

    final playlist = _playlists[pIndex];
    if (playingIndex < 0 || playingIndex >= playlist.items.length) return;

    bool updated = false;

    // 現在の状態と違えば更新
    if (!playlist.items[playingIndex].isPlaying) {
      // 全ての再生中フラグをリセットし、対象のみONにする
      for (int i = 0; i < playlist.items.length; i++) {
        if (i == playingIndex) {
          _playlists[pIndex].items[i] = playlist.items[i].copyWith(isPlaying: true, isQueued: true);
        } else {
          if (playlist.items[i].isPlaying) {
            _playlists[pIndex].items[i] = playlist.items[i].copyWith(isPlaying: false);
          }
        }
      }
      updated = true;
    }

    if (updated) {
      _notifyListeners();
      // 再生位置が変わったので補充チェック
      _checkAndQueueNext(DlnaService().currentDevice!, playlistId, playingIndex);
    }
  }

  // 自動補充ロジック
  bool _isQueueLoopRunning = false;

  void _checkAndQueueNext(DlnaDevice device, String playlistId, int currentIndex) async {
    if (_isQueueLoopRunning) return;
    _isQueueLoopRunning = true;

    try {
      final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
      if (pIndex == -1) return;

      final items = _playlists[pIndex].items;

      // 現在の再生位置の次から5つ先までをチェック
      int lookAhead = 5;

      for (int i = 1; i <= lookAhead; i++) {
        int nextIndex = currentIndex + i;
        if (nextIndex >= items.length) break;

        final item = items[nextIndex];

        // まだ送信しておらず、エラーでもない場合のみ処理
        if (!item.isQueued && !item.hasError) {
          print("[Manager] Auto-replenish: ${item.title}");

          // 解析と送信（リトライ付き）
          String? url = await ensureStreamUrl(playlistId, item.id);
          if (url != null) {
            try {
              await DlnaService().addToPlaylist(device, url, item.title, item.thumbnailUrl);
              _markAsQueued(playlistId, item.id);
              // 連続送信を防ぐため少し待機
              await Future.delayed(const Duration(seconds: 2));
            } catch (e) {
              print("[Manager] Auto-replenish send failed: $e");
            }
          }
        }
      }
    } finally {
      _isQueueLoopRunning = false;
    }
  }

  void _markAsQueued(String playlistId, String itemId) {
    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex != -1) {
      final iIndex = _playlists[pIndex].items.indexWhere((i) => i.id == itemId);
      if (iIndex != -1) {
        _playlists[pIndex].items[iIndex] = _playlists[pIndex].items[iIndex].copyWith(isQueued: true);
        _notifyListeners();
      }
    }
  }

  // --- 解析（リトライ機能付き） ---
  Future<String?> ensureStreamUrl(String playlistId, String itemId) async {
    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex == -1) return null;

    // アイテム検索
    final iIndex = _playlists[pIndex].items.indexWhere((i) => i.id == itemId);
    if (iIndex == -1) return null;
    var item = _playlists[pIndex].items[iIndex];

    // 既にURLがあれば返す
    if (item.streamUrl != null && item.streamUrl!.isNotEmpty) {
      // isResolvingフラグが残っていたら消す
      if (item.isResolving) {
        _playlists[pIndex].items[iIndex] = item.copyWith(isResolving: false);
        _notifyListeners();
      }
      return item.streamUrl;
    }

    // UI更新（解析中）
    _playlists[pIndex].items[iIndex] = item.copyWith(isResolving: true, hasError: false);
    _notifyListeners();

    // リトライループ
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        final streamUrl = await _ytService.fetchStreamUrl(item.originalUrl);
        if (streamUrl != null) {
          // 成功
          _playlists[pIndex].items[iIndex] = item.copyWith(
              streamUrl: streamUrl,
              isResolving: false,
              hasError: false
          );
          _saveToStorage();
          _notifyListeners();
          return streamUrl;
        }
      } catch (e) {
        print("[Manager] Resolve retry $retryCount failed: $e");
      }

      retryCount++;
      await Future.delayed(const Duration(seconds: 2)); // 待機してリトライ
    }

    // 失敗
    _playlists[pIndex].items[iIndex] = item.copyWith(isResolving: false, hasError: true);
    _notifyListeners();
    return null;
  }

  // --- 連続再生シーケンス（開始点） ---
  Future<void> playSequence(DlnaDevice device, String playlistId, int startIndex) async {
    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex == -1) return;

    final playlist = _playlists[pIndex];
    if (playlist.items.isEmpty) return;

    if (startIndex < 0) startIndex = 0;

    // 【重要】セッション開始位置を記憶
    _sessionStartIndex = startIndex;

    // 1. リセット
    for (int i = 0; i < playlist.items.length; i++) {
      if (playlist.items[i].isPlaying || playlist.items[i].isQueued) {
        _playlists[pIndex].items[i] = playlist.items[i].copyWith(isPlaying: false, isQueued: false);
      }
    }
    _saveToStorage();

    // 2. 監視スタート
    _startMonitor(device, playlistId);

    try {
      final dlnaService = DlnaService();
      await dlnaService.clearPlaylist(device);

      // 3. 開始曲を再生
      final firstItem = playlist.items[startIndex];
      String? url = await ensureStreamUrl(playlistId, firstItem.id);

      if (url != null) {
        await dlnaService.addToPlaylist(device, url, firstItem.title, firstItem.thumbnailUrl);
        await dlnaService.playFromPlaylist(device, 0);

        // 即座にステータス反映 (監視のラグを埋める)
        _playlists[pIndex].items[startIndex] = firstItem.copyWith(isPlaying: true, isQueued: true);
        _notifyListeners();

        // 4. 初回の補充
        _checkAndQueueNext(device, playlistId, startIndex);
      }
    } catch (e) {
      print("[Manager] Play sequence failed: $e");
    }
  }

  // その他のメソッド（import, processAndAddなど）はそのまま
  Future<String?> importFromYoutubePlaylist(String url) async {
    try {
      final info = await _ytService.fetchPlaylistInfo(url);
      if (info == null) return null;
      final String title = info['title'] ?? "YouTube Playlist";
      final List itemsData = info['items'] ?? [];
      final newPlaylistId = DateTime.now().millisecondsSinceEpoch.toString();
      final newPlaylist = PlaylistModel(id: newPlaylistId, name: title, items: []);
      for (var item in itemsData) {
        newPlaylist.items.add(LocalPlaylistItem(
          title: item['title'],
          originalUrl: item['url'],
          thumbnailUrl: item['thumbnailUrl'],
          durationStr: item['duration'],
          isResolving: true,
        ));
      }
      _playlists.add(newPlaylist);
      await _saveToStorage();
      return newPlaylistId;
    } catch (e) {
      print("[Manager] Import failed: $e");
      return null;
    }
  }

  void createPlaylist(String name) {
    final newList = PlaylistModel(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name, items: []);
    _playlists.add(newList);
    _saveToStorage();
  }
  void deletePlaylist(String playlistId) {
    _playlists.removeWhere((p) => p.id == playlistId);
    if (_playlists.isEmpty) createPlaylist("メインリスト");
    _saveToStorage();
  }
  void renamePlaylist(String playlistId, String newName) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      _playlists[index].name = newName;
      _saveToStorage();
    }
  }
  Future<void> processAndAdd(DlnaService dlnaService, Map<String, dynamic> metadata, {DlnaDevice? device, String? targetPlaylistId}) async {
    PlaylistModel targetList;
    if (targetPlaylistId != null) {
      targetList = _playlists.firstWhere((p) => p.id == targetPlaylistId, orElse: () => _playlists.first);
    } else {
      if (_playlists.isEmpty) createPlaylist("メインリスト");
      targetList = _playlists.first;
    }
    final newItem = LocalPlaylistItem(
      title: metadata['title'],
      originalUrl: metadata['url'],
      thumbnailUrl: metadata['thumbnailUrl'],
      durationStr: metadata['duration'],
      isResolving: true,
    );
    targetList.items.add(newItem);
    _saveToStorage();
    _notifyListeners();
    ensureStreamUrl(targetList.id, newItem.id);
  }
  void reorder(int oldIndex, int newIndex, {String? playlistId}) {
    final list = (playlistId == null) ? _playlists.first : _playlists.firstWhere((p) => p.id == playlistId, orElse: () => _playlists.first);
    if (oldIndex < newIndex) newIndex -= 1;
    final item = list.items.removeAt(oldIndex);
    list.items.insert(newIndex, item);
    _saveToStorage();
    _notifyListeners();
  }
  void removeItem(int index, {String? playlistId}) {
    final list = (playlistId == null) ? _playlists.first : _playlists.firstWhere((p) => p.id == playlistId, orElse: () => _playlists.first);
    if (index >= 0 && index < list.items.length) {
      list.items.removeAt(index);
      _saveToStorage();
      _notifyListeners();
    }
  }
  void removeItems(Set<String> ids, {String? playlistId}) {
    final list = (playlistId == null) ? _playlists.first : _playlists.firstWhere((p) => p.id == playlistId, orElse: () => _playlists.first);
    list.items.removeWhere((item) => ids.contains(item.id));
    _saveToStorage();
    _notifyListeners();
  }
  void moveItemToPlaylist(String itemId, {required String? fromPlaylistId, required String toPlaylistId}) {
    final fromList = (fromPlaylistId == null) ? _playlists.first : _playlists.firstWhere((p) => p.id == fromPlaylistId, orElse: () => _playlists.first);
    final toListIndex = _playlists.indexWhere((p) => p.id == toPlaylistId);
    if (toListIndex == -1 || fromList.id == _playlists[toListIndex].id) return;
    final itemIndex = fromList.items.indexWhere((i) => i.id == itemId);
    if (itemIndex != -1) {
      final item = fromList.items.removeAt(itemIndex);
      _playlists[toListIndex].items.add(item);
      _saveToStorage();
      _notifyListeners();
    }
  }
  void clear({String? playlistId}) {
    final list = (playlistId == null) ? _playlists.first : _playlists.firstWhere((p) => p.id == playlistId, orElse: () => _playlists.first);
    list.items.clear();
    _saveToStorage();
    _notifyListeners();
  }
}