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

  // バックグラウンド処理中かどうかのフラグ
  bool _isresolvingLoopRunning = false;

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
      // 旧データ移行
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

    // 【追加】起動時に未解析のものがあれば処理を開始
    _startBackgroundResolutionLoop();
  }

  // 【追加】連続再生のシーケンス制御
  Future<void> playSequence(DlnaDevice device, String playlistId, int startIndex) async {
    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex == -1) return;

    final playlist = _playlists[pIndex];
    if (playlist.items.isEmpty) return;

    // 範囲チェック
    if (startIndex < 0 || startIndex >= playlist.items.length) {
      startIndex = 0;
    }

    // 1. 履歴を更新
    playlist.lastPlayedIndex = startIndex;
    _saveToStorage(); // 保存

    try {
      // 2. Kodiのリストをクリア
      final dlnaService = DlnaService();
      await dlnaService.clearPlaylist(device);

      // 3. 最初の1曲目を解決して再生
      final firstItem = playlist.items[startIndex];
      String? streamUrl = await ensureStreamUrl(playlistId, firstItem.id);

      if (streamUrl != null) {
        // 追加して再生
        await dlnaService.addToPlaylist(device, streamUrl, firstItem.title, firstItem.thumbnailUrl);
        await dlnaService.playFromPlaylist(device, 0); // 0番目(今入れたやつ)を再生
      } else {
        // URL取れなければスキップ等の処理が必要だが、一旦エラー表示
        print("First item URL resolve failed");
        return;
      }

      // 4. 【スマート・キューイング】残りの曲をバックグラウンドで順次追加
      // 最大10曲先まで予約する（無限ループ防止とURL期限切れ対策）
      _queueNextItems(device, playlistId, startIndex + 1, 10);

    } catch (e) {
      print("[Manager] Play sequence failed: $e");
    }
  }

  // バックグラウンドで次々と追加していく処理
  void _queueNextItems(DlnaDevice device, String playlistId, int nextIndex, int count) async {
    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex == -1) return;

    final items = _playlists[pIndex].items;
    int addedCount = 0;

    for (int i = nextIndex; i < items.length; i++) {
      if (addedCount >= count) break;

      // 3秒待機 (API制限回避 & 負荷軽減)
      await Future.delayed(const Duration(seconds: 3));

      final item = items[i];
      // URL解決
      String? url = await ensureStreamUrl(playlistId, item.id);

      if (url != null) {
        try {
          // Kodiの末尾に追加
          await DlnaService().addToPlaylist(device, url, item.title, item.thumbnailUrl);
          print("[Manager] Queued next item: ${item.title}");
          addedCount++;
        } catch (e) {
          print("[Manager] Queue failed for ${item.title}: $e");
        }
      }
    }
  }


  // --- バックグラウンド解析ループ ---
  void _startBackgroundResolutionLoop() async {
    if (_isresolvingLoopRunning) return;
    _isresolvingLoopRunning = true;
    print("[Manager] Background resolution loop started.");

    while (true) {
      // 未解析(isResolving: true)かつエラーでないアイテムを探す
      // ※全てのプレイリストを走査
      String? targetPlaylistId;
      String? targetItemId;

      bool found = false;
      for (var playlist in _playlists) {
        for (var item in playlist.items) {
          if (item.isResolving && !item.hasError) {
            targetPlaylistId = playlist.id;
            targetItemId = item.id;
            found = true;
            break;
          }
        }
        if (found) break;
      }

      // 未解析がなくなったらループ終了
      if (!found || targetPlaylistId == null || targetItemId == null) {
        _isresolvingLoopRunning = false;
        print("[Manager] Background resolution loop finished.");
        break;
      }

      // 解析実行 (ensureStreamUrlが解決処理を行う)
      await ensureStreamUrl(targetPlaylistId, targetItemId);

      // 連続アクセスを防ぐため、少し待機 (重要)
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  // --- YouTubeプレイリスト取込 ---
  Future<String?> importFromYoutubePlaylist(String url) async {
    try {
      final info = await _ytService.fetchPlaylistInfo(url);
      if (info == null) return null;

      final String title = info['title'] ?? "YouTube Playlist";
      final List itemsData = info['items'] ?? [];

      final newPlaylistId = DateTime.now().millisecondsSinceEpoch.toString();
      final newPlaylist = PlaylistModel(
        id: newPlaylistId,
        name: title,
        items: [],
      );

      for (var item in itemsData) {
        newPlaylist.items.add(LocalPlaylistItem(
          title: item['title'],
          originalUrl: item['url'],
          thumbnailUrl: item['thumbnailUrl'],
          durationStr: item['duration'],
          isResolving: true, // ここで解析待ちとして登録
        ));
      }

      _playlists.add(newPlaylist);
      await _saveToStorage();

      // 【追加】取込後に解析ループを開始
      _startBackgroundResolutionLoop();

      return newPlaylistId;
    } catch (e) {
      print("[Manager] Import failed: $e");
      return null;
    }
  }

  // --- URL解決 (オンデマンド & バックグラウンド兼用) ---
  Future<String?> ensureStreamUrl(String playlistId, String itemId) async {
    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex == -1) return null;

    final iIndex = _playlists[pIndex].items.indexWhere((i) => i.id == itemId);
    if (iIndex == -1) return null;

    var item = _playlists[pIndex].items[iIndex];

    // 既に解決済みなら返す
    if (item.streamUrl != null && item.streamUrl!.isNotEmpty) {
      // isResolvingが残っていたら消しておく
      if (item.isResolving) {
        _playlists[pIndex].items[iIndex] = item.copyWith(isResolving: false);
        _saveToStorage();
        _notifyListeners(); // UI更新
      }
      return item.streamUrl;
    }

    // 解析処理
    try {
      print("[Manager] Resolving: ${item.title}");
      final streamUrl = await _ytService.fetchStreamUrl(item.originalUrl);

      if (streamUrl != null) {
        _playlists[pIndex].items[iIndex] = item.copyWith(
            streamUrl: streamUrl,
            isResolving: false,
            hasError: false
        );
        _saveToStorage();
        _notifyListeners(); // UI更新（インジケータを消すため）
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
      _notifyListeners(); // UI更新（エラー表示のため）
      return null;
    }
  }

  // --- 既存メソッド ---
  void createPlaylist(String name) {
    final newList = PlaylistModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      items: [],
    );
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

  // 単体追加時もバックグラウンド処理を開始するように修正
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
      isResolving: true, // 解析待ちとして追加
    );

    targetList.items.add(newItem);
    _saveToStorage();
    _notifyListeners();

    // 【追加】解析ループ開始
    _startBackgroundResolutionLoop();

    // ※元のprocessAndAddにあった即時解析ロジックは _startBackgroundResolutionLoop に任せるため削除・統合しました
  }



  void reorder(int oldIndex, int newIndex, {String? playlistId}) {
    final list = (playlistId == null)
        ? _playlists.first
        : _playlists.firstWhere((p) => p.id == playlistId, orElse: () => _playlists.first);

    if (oldIndex < newIndex) newIndex -= 1;
    final item = list.items.removeAt(oldIndex);
    list.items.insert(newIndex, item);
    _saveToStorage();
    _notifyListeners();
  }

  void removeItem(int index, {String? playlistId}) {
    final list = (playlistId == null)
        ? _playlists.first
        : _playlists.firstWhere((p) => p.id == playlistId, orElse: () => _playlists.first);

    if (index >= 0 && index < list.items.length) {
      list.items.removeAt(index);
      _saveToStorage();
      _notifyListeners();
    }
  }

  void removeItems(Set<String> ids, {String? playlistId}) {
    final list = (playlistId == null)
        ? _playlists.first
        : _playlists.firstWhere((p) => p.id == playlistId, orElse: () => _playlists.first);

    list.items.removeWhere((item) => ids.contains(item.id));
    _saveToStorage();
    _notifyListeners();
  }

  void moveItemToPlaylist(String itemId, {required String? fromPlaylistId, required String toPlaylistId}) {
    final fromList = (fromPlaylistId == null)
        ? _playlists.first
        : _playlists.firstWhere((p) => p.id == fromPlaylistId, orElse: () => _playlists.first);

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
    final list = (playlistId == null)
        ? _playlists.first
        : _playlists.firstWhere((p) => p.id == playlistId, orElse: () => _playlists.first);
    list.items.clear();
    _saveToStorage();
    _notifyListeners();
  }
}