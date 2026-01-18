import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dlna_service.dart';
import '../services/youtube_service.dart';
import '../models/playlist_model.dart';
import '../models/local_playlist_item.dart';

// 他のファイルが import 'playlist_manager.dart' した時に
// LocalPlaylistItem も使えるようにエクスポートしておく
export '../models/playlist_model.dart';
export '../models/local_playlist_item.dart';

class PlaylistManager {
  static final PlaylistManager _instance = PlaylistManager._internal();
  factory PlaylistManager() => _instance;

  PlaylistManager._internal() {
    _loadFromStorage();
  }

  // 複数リストを管理
  final List<PlaylistModel> _playlists = [];

  // ライブラリ画面用ストリーム（リストの一覧）
  final StreamController<List<PlaylistModel>> _playlistsController = StreamController.broadcast();
  Stream<List<PlaylistModel>> get playlistsStream => _playlistsController.stream;

  // 既存画面（PlaylistPage）互換用：現在アクティブなリストのアイテムを流す
  final StreamController<List<LocalPlaylistItem>> _itemsController = StreamController.broadcast();
  Stream<List<LocalPlaylistItem>> get itemsStream => _itemsController.stream;

  final YoutubeService _ytService = YoutubeService();

  List<PlaylistModel> get currentPlaylists => _playlists;

  // 互換性のため、デフォルト（先頭）のリストの中身を返す
  List<LocalPlaylistItem> get currentItems {
    if (_playlists.isEmpty) return [];
    return _playlists.first.items;
  }

  // --- 永続化と移行ロジック ---

  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonStr = jsonEncode(_playlists.map((e) => e.toJson()).toList());
    await prefs.setString('saved_playlists_v2', jsonStr); // 新しいキーを使用

    // ストリーム更新
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

    // 1. 新しい形式のデータを読み込む
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
      // 2. 新データがない場合、旧データを移行する
      print("[Manager] Migrating old data...");
      final String? oldJsonStr = prefs.getString('saved_playlist'); // 旧キー
      List<LocalPlaylistItem> oldItems = [];

      if (oldJsonStr != null) {
        try {
          final List<dynamic> jsonList = jsonDecode(oldJsonStr);
          oldItems = jsonList.map((e) => LocalPlaylistItem.fromJson(e)).toList();
        } catch (e) {}
      }

      // 「メインリスト」を作成して旧データを投入
      final mainList = PlaylistModel(
          id: 'default_main',
          name: 'メインリスト',
          items: oldItems
      );
      _playlists.add(mainList);

      // 保存
      await _saveToStorage();

      // 旧データは（安全のためすぐ消さずに）残すか、削除してもよい
      // await prefs.remove('saved_playlist');
    }

    _notifyListeners();
  }

  // --- プレイリスト操作 ---

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
    if (_playlists.isEmpty) {
      // リストが0個にならないよう、空のメインリストを作成
      createPlaylist("メインリスト");
    } else {
      _saveToStorage();
    }
  }

  void renamePlaylist(String playlistId, String newName) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      _playlists[index].name = newName;
      _saveToStorage();
    }
  }

  // --- アイテム操作 (targetPlaylistId を指定可能に) ---

  Future<void> processAndAdd(DlnaService dlnaService, Map<String, dynamic> metadata, {DlnaDevice? device, String? targetPlaylistId}) async {
    // ID指定がなければ先頭（メイン）リストに入れる
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
    _saveToStorage(); // 即保存
    _notifyListeners();

    print("[BG] Start resolving: ${newItem.title} in list: ${targetList.name}");

    try {
      final streamUrl = await _ytService.fetchStreamUrl(newItem.originalUrl);

      if (streamUrl != null) {
        // Kodiへの送信は「デバイス接続中」かつ「今すぐ再生的な意図がある場合」だが、
        // プレイリストへのバックグラウンド追加時はKodiへは送らないのが基本（再生時に送る）。
        // ただし、以前のロジックを維持するなら device!=null の時に送る。
        // ※ 複数リスト対応に伴い、Kodiへの自動同期は「再生時」に任せるのが安全ですが、
        //   既存機能維持のため、メインリストへの追加とみなして送信を試みます。

        if (device != null) {
          try {
            // 複数リストある場合、Kodi側のプレイリストとどう同期するかは課題だが、一旦送る
            // await dlnaService.addToPlaylist(...)
            // ★修正: 複数リスト管理になったため、勝手にKodiへ送ると混乱する可能性がある。
            // ここでは「解析完了」だけを行い、Kodiへの送信はユーザーが「再生」ボタンを押した時に任せるのが正解。
            // しかし、CastPageの「今すぐ再生」などのために、URL解決は必須。
          } catch(e) {}
        }

        final pIndex = _playlists.indexWhere((p) => p.id == targetList.id);
        if (pIndex != -1) {
          final iIndex = _playlists[pIndex].items.indexWhere((item) => item.id == newItem.id);
          if (iIndex != -1) {
            _playlists[pIndex].items[iIndex] = newItem.copyWith(streamUrl: streamUrl, isResolving: false);
            _saveToStorage();
            _notifyListeners();
          }
        }
      } else {
        throw Exception("Stream URL not found");
      }
    } catch (e) {
      print("[BG] Failed: $e");
      final pIndex = _playlists.indexWhere((p) => p.id == targetList.id);
      if (pIndex != -1) {
        final iIndex = _playlists[pIndex].items.indexWhere((item) => item.id == newItem.id);
        if (iIndex != -1) {
          _playlists[pIndex].items[iIndex] = newItem.copyWith(isResolving: false, hasError: true);
          _saveToStorage();
          _notifyListeners();
        }
      }
    }
  }

  // 並べ替え (ID対応)
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

  // 削除 (ID対応)
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

  // --- アイテム移動 ---

  void moveItemToPlaylist(String itemId, {required String? fromPlaylistId, required String toPlaylistId}) {
    // 元のリストを特定（nullならメインリスト）
    final fromList = (fromPlaylistId == null)
        ? _playlists.first
        : _playlists.firstWhere((p) => p.id == fromPlaylistId, orElse: () => _playlists.first);

    // 移動先のリストを特定
    final toListIndex = _playlists.indexWhere((p) => p.id == toPlaylistId);
    if (toListIndex == -1) return; // 移動先が見つからない
    final toList = _playlists[toListIndex];

    // 同じリストへの移動なら何もしない
    if (fromList.id == toList.id) return;

    // アイテムを探して移動
    final itemIndex = fromList.items.indexWhere((i) => i.id == itemId);
    if (itemIndex != -1) {
      final item = fromList.items.removeAt(itemIndex);
      toList.items.add(item);

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