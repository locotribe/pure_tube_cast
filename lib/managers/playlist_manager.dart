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
    _loadFromStorage().then((_) {
      print("[Manager] Storage loaded. Listening for device connections...");
      DlnaService().connectedDeviceStream.listen((device) {
        if (device != null) {
          print("[Manager] Device connected: ${device.name}. Attempting to restore session...");
          _attemptRestoreSession(device);
        }
      });
    });
  }

  final List<PlaylistModel> _playlists = [];
  final StreamController<List<PlaylistModel>> _playlistsController = StreamController.broadcast();
  Stream<List<PlaylistModel>> get playlistsStream => _playlistsController.stream;

  final StreamController<List<LocalPlaylistItem>> _itemsController = StreamController.broadcast();
  Stream<List<LocalPlaylistItem>> get itemsStream => _itemsController.stream;

  final YoutubeService _ytService = YoutubeService();

  Timer? _monitorTimer;

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


  // ==========================================================
  //  リカバリー（逆同期）ロジック 【時間照合版】
  // ==========================================================

  Future<void> _attemptRestoreSession(DlnaDevice device) async {
    await Future.delayed(const Duration(seconds: 1));

    final status = await DlnaService().getPlayerStatus(device);
    final kodiItems = await DlnaService().getPlaylistItems(device);

    if (status == null || kodiItems.isEmpty) return;

    final int kodiPos = status['position'];
    final int kodiDurationSec = status['totalSeconds'] ?? 0; // Kodi側の秒数

    if (kodiPos < 0 || kodiPos >= kodiItems.length) return;

    final currentKodiItem = kodiItems[kodiPos];
    final nextKodiItem = (kodiPos + 1 < kodiItems.length) ? kodiItems[kodiPos + 1] : null;

    String? matchedPlaylistId;
    int? matchedItemIndex;

    // --- ヘルパー: "H:MM:SS" 文字列を秒数に変換 ---
    int parseDuration(String durationStr) {
      try {
        final parts = durationStr.split(':').map((e) => int.parse(e)).toList();
        if (parts.length == 3) {
          return (parts[0] * 3600) + (parts[1] * 60) + parts[2];
        } else if (parts.length == 2) {
          return (parts[0] * 60) + parts[1];
        } else {
          return parts[0]; // 秒のみの場合
        }
      } catch (e) {
        return 0;
      }
    }

    // --- 判定ロジック: タイトル OR URL OR 【時間】 で照合 ---
    bool isMatch(LocalPlaylistItem local, KodiPlaylistItem remote, {bool checkDuration = false}) {
      // 1. タイトルチェック
      final lTitle = local.title.trim().toLowerCase();
      final rLabel = remote.label.trim().toLowerCase();
      if (lTitle.isNotEmpty && (lTitle == rLabel || rLabel.contains(lTitle) || lTitle.contains(rLabel))) {
        return true;
      }

      // 2. URL一致 (一応残す)
      if (local.streamUrl != null && local.streamUrl == remote.file) {
        return true;
      }

      // 3. 【最強】再生時間の一致チェック (現在再生中のアイテムのみ有効)
      if (checkDuration && kodiDurationSec > 0) {
        final localSec = parseDuration(local.durationStr);
        // 誤差±2秒を許容 (KodiとYouTubeのメタデータで多少ズレるため)
        if ((localSec - kodiDurationSec).abs() <= 2) {
          print("[Manager] Duration Match! Local: $localSec sec, Remote: $kodiDurationSec sec");
          return true;
        }
      }

      return false;
    }

    // --- フェーズ 1: 文脈マッチング (現在 + 次) ---
    if (nextKodiItem != null) {
      for (var playlist in _playlists) {
        for (int i = 0; i < playlist.items.length - 1; i++) {
          // 現在の曲は「時間」も含めてチェック
          bool currentMatch = isMatch(playlist.items[i], currentKodiItem, checkDuration: true);
          // 次の曲はまだ再生されていないので「タイトル/URL」のみでチェック
          bool nextMatch = isMatch(playlist.items[i + 1], nextKodiItem, checkDuration: false);

          if (currentMatch && nextMatch) {
            matchedPlaylistId = playlist.id;
            matchedItemIndex = i;
            print("[Manager] Context Match (Duration+Next): ${playlist.name} ($i)");
            break;
          }
        }
        if (matchedPlaylistId != null) break;
      }
    }

    // --- フェーズ 2: 単体マッチング (時間優先) ---
    if (matchedPlaylistId == null) {
      for (var playlist in _playlists) {
        for (int i = 0; i < playlist.items.length; i++) {
          // 時間が一致すれば採用
          if (isMatch(playlist.items[i], currentKodiItem, checkDuration: true)) {
            matchedPlaylistId = playlist.id;
            matchedItemIndex = i;
            print("[Manager] Single Match (Duration): ${playlist.name} ($i)");
            break;
          }
        }
        if (matchedPlaylistId != null) break;
      }
    }

    // 復元処理
    if (matchedPlaylistId != null && matchedItemIndex != null) {
      print("[Manager] Restoring session... Playlist: $matchedPlaylistId");

      for (var p in _playlists) {
        for (int i = 0; i < p.items.length; i++) {
          if (p.items[i].isPlaying || p.items[i].isQueued) {
            p.items[i] = p.items[i].copyWith(isPlaying: false, isQueued: false);
          }
        }
      }

      final pIndex = _playlists.indexWhere((p) => p.id == matchedPlaylistId);
      final items = _playlists[pIndex].items;

      for (int k = 0; k < kodiItems.length; k++) {
        final localIndex = matchedItemIndex! - kodiPos + k;
        if (localIndex >= 0 && localIndex < items.length) {
          bool isPlaying = (k == kodiPos);
          _playlists[pIndex].items[localIndex] = items[localIndex].copyWith(
            isQueued: true,
            isPlaying: isPlaying,
            hasError: false,
            isResolving: false,
          );
        }
      }

      _notifyListeners();
      _startMonitor(device, matchedPlaylistId);
      _checkAndQueueNext(device, matchedPlaylistId, matchedItemIndex!);

    } else {
      print("[Manager] Failed to find matching playlist for: ${currentKodiItem.label} (Duration: $kodiDurationSec sec)");
    }
  }


  int? _getKodiPosition(String playlistId, String itemId) {
    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex == -1) return null;

    final items = _playlists[pIndex].items;
    final itemIndex = items.indexWhere((i) => i.id == itemId);
    if (itemIndex == -1) return null;

    if (!items[itemIndex].isQueued) return null;

    int count = 0;
    for (int i = 0; i < itemIndex; i++) {
      if (items[i].isQueued) count++;
    }
    return count;
  }

  void _startMonitor(DlnaDevice device, String playlistId) {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final status = await DlnaService().getPlayerStatus(device);
      if (status != null) {
        final int kodiPosition = status['position'];

        final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
        if (pIndex != -1) {
          final items = _playlists[pIndex].items;
          int currentQueuedCount = 0;
          int? targetAppIndex;

          for (int i = 0; i < items.length; i++) {
            if (items[i].isQueued) {
              if (currentQueuedCount == kodiPosition) {
                targetAppIndex = i;
                break;
              }
              currentQueuedCount++;
            }
          }

          if (targetAppIndex != null) {
            _syncPlayingStatus(playlistId, targetAppIndex);
          }
        }
      }
    });
  }

  void _syncPlayingStatus(String playlistId, int playingIndex) {
    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex == -1) return;

    final playlist = _playlists[pIndex];
    if (playingIndex < 0 || playingIndex >= playlist.items.length) return;

    bool updated = false;

    if (!playlist.items[playingIndex].isPlaying) {
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
      _checkAndQueueNext(DlnaService().currentDevice!, playlistId, playingIndex);
    }
  }

  bool _isQueueLoopRunning = false;

  void _checkAndQueueNext(DlnaDevice device, String playlistId, int currentIndex) async {
    if (_isQueueLoopRunning) return;
    _isQueueLoopRunning = true;

    try {
      final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
      if (pIndex == -1) return;

      final items = _playlists[pIndex].items;
      int lookAhead = 5;

      for (int i = 1; i <= lookAhead; i++) {
        int nextIndex = currentIndex + i;
        if (nextIndex >= items.length) break;

        final item = items[nextIndex];

        if (!item.isQueued && !item.hasError) {
          int insertPos = 0;
          for(int j=0; j<nextIndex; j++){
            if(items[j].isQueued) insertPos++;
          }

          String? url = await ensureStreamUrl(playlistId, item.id);
          if (url != null) {
            try {
              // 挿入試行 (Insert)
              await DlnaService().insertToPlaylist(device, insertPos, url, item.title, item.thumbnailUrl);
              _markAsQueued(playlistId, item.id);
              await Future.delayed(const Duration(seconds: 2));
            } catch (e) {
              print("[Manager] Insert failed, trying Add fallback: $e");
              // フォールバック (Add)
              try {
                await DlnaService().addToPlaylist(device, url, item.title, item.thumbnailUrl);
                _markAsQueued(playlistId, item.id);
                print("[Manager] Fallback Add succeeded for: ${item.title}");
                await Future.delayed(const Duration(seconds: 2));
              } catch (e2) {
                print("[Manager] Fallback Add also failed: $e2");
              }
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

  Future<void> playOrJump(DlnaDevice device, String playlistId, int index) async {
    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex == -1) return;

    final item = _playlists[pIndex].items[index];

    if (item.isQueued) {
      final kodiPos = _getKodiPosition(playlistId, item.id);
      if (kodiPos != null) {
        print("[Manager] Jumping to position $kodiPos");
        await DlnaService().playFromPlaylist(device, kodiPos);
        _syncPlayingStatus(playlistId, index);
        return;
      }
    }

    await playSequence(device, playlistId, index);
  }

  Future<void> stopSession(DlnaDevice device) async {
    _monitorTimer?.cancel();
    await DlnaService().clearPlaylist(device);

    for (var playlist in _playlists) {
      for (int i = 0; i < playlist.items.length; i++) {
        if (playlist.items[i].isPlaying || playlist.items[i].isQueued) {
          playlist.items[i] = playlist.items[i].copyWith(isPlaying: false, isQueued: false);
        }
      }
    }
    _notifyListeners();
  }

  Future<String?> ensureStreamUrl(String playlistId, String itemId) async {
    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex == -1) return null;
    final iIndex = _playlists[pIndex].items.indexWhere((i) => i.id == itemId);
    if (iIndex == -1) return null;
    var item = _playlists[pIndex].items[iIndex];

    if (item.streamUrl != null && item.streamUrl!.isNotEmpty) {
      if (item.isResolving) {
        _playlists[pIndex].items[iIndex] = item.copyWith(isResolving: false);
        _notifyListeners();
      }
      return item.streamUrl;
    }

    _playlists[pIndex].items[iIndex] = item.copyWith(isResolving: true, hasError: false);
    _notifyListeners();

    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
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
        }
      } catch (e) {
        print("[Manager] Resolve retry $retryCount failed: $e");
      }
      retryCount++;
      await Future.delayed(const Duration(seconds: 2));
    }

    _playlists[pIndex].items[iIndex] = item.copyWith(isResolving: false, hasError: true);
    _notifyListeners();
    return null;
  }

  Future<void> playSequence(DlnaDevice device, String playlistId, int startIndex) async {
    for (var playlist in _playlists) {
      for (int i = 0; i < playlist.items.length; i++) {
        if (playlist.items[i].isPlaying || playlist.items[i].isQueued) {
          playlist.items[i] = playlist.items[i].copyWith(isPlaying: false, isQueued: false);
        }
      }
    }
    _notifyListeners();

    final pIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex == -1) return;
    final playlist = _playlists[pIndex];
    if (playlist.items.isEmpty) return;
    if (startIndex < 0) startIndex = 0;

    playlist.lastPlayedIndex = startIndex;
    _saveToStorage();

    _startMonitor(device, playlistId);

    try {
      final dlnaService = DlnaService();
      await dlnaService.clearPlaylist(device);

      final firstItem = playlist.items[startIndex];
      String? url = await ensureStreamUrl(playlistId, firstItem.id);

      if (url != null) {
        await dlnaService.addToPlaylist(device, url, firstItem.title, firstItem.thumbnailUrl);
        await dlnaService.playFromPlaylist(device, 0);

        _playlists[pIndex].items[startIndex] = firstItem.copyWith(isPlaying: true, isQueued: true);
        _notifyListeners();

        _checkAndQueueNext(device, playlistId, startIndex);
      }
    } catch (e) {
      print("[Manager] Play sequence failed: $e");
    }
  }

  void reorderPlaylists(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final playlist = _playlists.removeAt(oldIndex);
    _playlists.insert(newIndex, playlist);
    _saveToStorage();
    _notifyListeners();
  }

  void reorder(int oldIndex, int newIndex, {String? playlistId}) {
    final pIndex = (playlistId == null)
        ? 0
        : _playlists.indexWhere((p) => p.id == playlistId);
    if (pIndex == -1) return;
    final list = _playlists[pIndex];

    if (oldIndex < newIndex) newIndex -= 1;
    final item = list.items.removeAt(oldIndex);

    list.items.insert(newIndex, item);
    _saveToStorage();
    _notifyListeners();

    final playingIndex = list.items.indexWhere((i) => i.isPlaying);
    if (playingIndex != -1) {
      _checkAndQueueNext(DlnaService().currentDevice!, list.id, playingIndex);
    }
  }

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