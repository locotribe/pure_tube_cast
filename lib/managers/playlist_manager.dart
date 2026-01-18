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

  bool _isResolvingLoopRunning = false;

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
    _startBackgroundResolutionLoop();
  }

  void _startBackgroundResolutionLoop() async {
    if (_isResolvingLoopRunning) return;
    _isResolvingLoopRunning = true;
    print("[Manager] Background resolution loop started.");

    while (true) {
      String? targetPlaylistId;
      String? targetItemId;

      bool found = false;
      for (var playlist in _playlists) {
        for (var item in playlist.items) {
          // 「解析中」かつ「エラーなし」のものを探して処理する
          if (item.isResolving && !item.hasError) {
            targetPlaylistId = playlist.id;
            targetItemId = item.id;
            found = true;
            break;
          }
        }
        if (found) break;
      }

      if (!found || targetPlaylistId == null || targetItemId == null) {
        _isResolvingLoopRunning = false;
        print("[Manager] Background resolution loop finished.");
        break;
      }

      await ensureStreamUrl(targetPlaylistId, targetItemId);
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  // --- 連続再生シーケンス ---
  Future<void> playSequence(DlnaDevice device, String playlistId, int startIndex) async {
    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex == -1) return;

    var playlist = _playlists[pIndex];
    if (playlist.items.isEmpty) return;

    if (startIndex < 0 || startIndex >= playlist.items.length) {
      startIndex = 0;
    }

    // 1. 状態のリセット (再生中・送信済みマークを全てクリア)
    for (int i = 0; i < playlist.items.length; i++) {
      bool changed = false;
      if (playlist.items[i].isQueued || playlist.items[i].isPlaying) {
        playlist.items[i] = playlist.items[i].copyWith(isQueued: false, isPlaying: false);
        changed = true;
      }
    }

    // 履歴更新
    playlist.lastPlayedIndex = startIndex;
    _saveToStorage();

    try {
      final dlnaService = DlnaService();
      await dlnaService.clearPlaylist(device);

      // 2. 最初の1曲目を処理
      final firstItem = playlist.items[startIndex];
      String? streamUrl = await ensureStreamUrl(playlistId, firstItem.id);

      if (streamUrl != null) {
        await dlnaService.addToPlaylist(device, streamUrl, firstItem.title, firstItem.thumbnailUrl);
        await dlnaService.playFromPlaylist(device, 0);

        // 【追加】「再生中」マークをつける
        _markAsPlaying(playlistId, firstItem.id);
      } else {
        print("First item URL resolve failed");
        return;
      }

      // 3. 残りをバックグラウンド追加 (5件に制限)
      _queueNextItems(device, playlistId, startIndex + 1, 5);

    } catch (e) {
      print("[Manager] Play sequence failed: $e");
    }
  }

  void _queueNextItems(DlnaDevice device, String playlistId, int nextIndex, int count) async {
    // 順番に追加していく
    int processedCount = 0;
    int currentIndex = nextIndex;

    while (processedCount < count) {
      final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
      if (pIndex == -1) break;
      final currentItems = _playlists[pIndex].items;

      if (currentIndex >= currentItems.length) break;

      // 間隔を少し広げる (3秒 -> 4秒) タイムアウト防止
      await Future.delayed(const Duration(seconds: 4));

      final item = currentItems[currentIndex];
      String? url = await ensureStreamUrl(playlistId, item.id);

      if (url != null) {
        try {
          await DlnaService().addToPlaylist(device, url, item.title, item.thumbnailUrl);
          print("[Manager] Queued next item: ${item.title}");

          // 送信済みマーク
          _markAsQueued(playlistId, item.id);

        } catch (e) {
          print("[Manager] Queue failed for ${item.title}: $e");
          // エラーでもループは止めず、次の動画へ
        }
      }
      currentIndex++;
      processedCount++;
    }
  }

  // 「送信済み」フラグを立てる
  void _markAsQueued(String playlistId, String itemId) {
    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex != -1) {
      final iIndex = _playlists[pIndex].items.indexWhere((i) => i.id == itemId);
      if (iIndex != -1) {
        _playlists[pIndex].items[iIndex] = _playlists[pIndex].items[iIndex].copyWith(
            isQueued: true,
            hasError: false // 送信できたらエラーは消す
        );
        _notifyListeners();
      }
    }
  }

  // 【追加】「再生中」フラグを立てる (他は消す)
  void _markAsPlaying(String playlistId, String itemId) {
    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex == -1) return;

    for (int i = 0; i < _playlists[pIndex].items.length; i++) {
      final item = _playlists[pIndex].items[i];
      if (item.id == itemId) {
        // 対象アイテム: 再生中ON, 送信済ON (再生してるということはKodiにある)
        _playlists[pIndex].items[i] = item.copyWith(isPlaying: true, isQueued: true);
      } else if (item.isPlaying) {
        // 他のアイテム: 再生中OFF
        _playlists[pIndex].items[i] = item.copyWith(isPlaying: false);
      }
    }
    _notifyListeners();
  }

  // --- URL解決 ---
  Future<String?> ensureStreamUrl(String playlistId, String itemId) async {
    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex == -1) return null;
    final iIndex = _playlists[pIndex].items.indexWhere((i) => i.id == itemId);
    if (iIndex == -1) return null;

    var item = _playlists[pIndex].items[iIndex];

    // 解析済みならそれを返す
    if (item.streamUrl != null && item.streamUrl!.isNotEmpty) {
      if (item.isResolving) {
        _playlists[pIndex].items[iIndex] = item.copyWith(isResolving: false);
        _saveToStorage();
        _notifyListeners();
      }
      return item.streamUrl;
    }

    // 解析開始
    try {
      print("[Manager] Resolving: ${item.title}");

      // UI用に「解析中」フラグを立てる（もし立ってなければ）
      if (!item.isResolving) {
        _playlists[pIndex].items[iIndex] = item.copyWith(isResolving: true, hasError: false);
        _notifyListeners();
      }

      final streamUrl = await _ytService.fetchStreamUrl(item.originalUrl);

      if (streamUrl != null) {
        _playlists[pIndex].items[iIndex] = item.copyWith(
            streamUrl: streamUrl,
            isResolving: false,
            hasError: false
        );
        _saveToStorage();
        _notifyListeners();
        return streamUrl;
      } else {
        throw Exception("Stream URL not found");
      }
    } catch (e) {
      print("[Manager] Resolve failed: $e");
      _playlists[pIndex].items[iIndex] = item.copyWith(
          isResolving: false,
          hasError: true
      );
      _saveToStorage();
      _notifyListeners();
      return null;
    }
  }

  // その他のメソッドは変更なし
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
      _startBackgroundResolutionLoop();
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
    _startBackgroundResolutionLoop();
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