import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dlna_service.dart';
import '../services/youtube_service.dart';

// 再生リストのアイテム情報
class LocalPlaylistItem {
  final String id;
  final String title;
  final String originalUrl;
  final String? streamUrl;
  final String? thumbnailUrl;
  final String durationStr;

  bool isResolving;
  bool hasError;

  LocalPlaylistItem({
    String? id,
    required this.title,
    required this.originalUrl,
    this.streamUrl,
    this.thumbnailUrl,
    this.durationStr = "--:--",
    this.isResolving = false,
    this.hasError = false,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString() + Random().nextInt(1000).toString();

  LocalPlaylistItem copyWith({
    String? streamUrl,
    bool? isResolving,
    bool? hasError,
  }) {
    return LocalPlaylistItem(
      id: id,
      title: title,
      originalUrl: originalUrl,
      thumbnailUrl: thumbnailUrl,
      durationStr: durationStr,
      streamUrl: streamUrl ?? this.streamUrl,
      isResolving: isResolving ?? this.isResolving,
      hasError: hasError ?? this.hasError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'originalUrl': originalUrl,
      'streamUrl': streamUrl,
      'thumbnailUrl': thumbnailUrl,
      'durationStr': durationStr,
      'isResolving': false,
      'hasError': hasError,
    };
  }

  factory LocalPlaylistItem.fromJson(Map<String, dynamic> json) {
    return LocalPlaylistItem(
      id: json['id'],
      title: json['title'],
      originalUrl: json['originalUrl'],
      streamUrl: json['streamUrl'],
      thumbnailUrl: json['thumbnailUrl'],
      durationStr: json['durationStr'] ?? "--:--",
      isResolving: false,
      hasError: json['hasError'] ?? false,
    );
  }
}

class PlaylistManager {
  static final PlaylistManager _instance = PlaylistManager._internal();
  factory PlaylistManager() => _instance;

  PlaylistManager._internal() {
    _loadFromStorage();
  }

  final List<LocalPlaylistItem> _items = [];
  final StreamController<List<LocalPlaylistItem>> _streamController = StreamController.broadcast();
  final YoutubeService _ytService = YoutubeService();

  Stream<List<LocalPlaylistItem>> get itemsStream => _streamController.stream;
  List<LocalPlaylistItem> get currentItems => _items;

  // --- 永続化ロジック ---

  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonStr = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString('saved_playlist', jsonStr);
    print("[Manager] Playlist saved: ${_items.length} items");
  }

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('saved_playlist');
    if (jsonStr != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        _items.clear();
        _items.addAll(jsonList.map((e) => LocalPlaylistItem.fromJson(e)).toList());
        _streamController.add(List.from(_items));
        print("[Manager] Playlist loaded: ${_items.length} items");
      } catch (e) {
        print("[Manager] Load failed: $e");
      }
    }
  }

  // --- UIからの操作 ---

  Future<void> processAndAdd(DlnaService dlnaService, Map<String, dynamic> metadata, {DlnaDevice? device}) async {
    print("[Manager] processAndAdd start: ${metadata['title']}");

    final newItem = LocalPlaylistItem(
      title: metadata['title'],
      originalUrl: metadata['url'],
      thumbnailUrl: metadata['thumbnailUrl'],
      durationStr: metadata['duration'],
      isResolving: true,
    );

    _items.add(newItem);
    _streamController.add(List.from(_items));
    _saveToStorage();

    print("[BG] Start resolving: ${newItem.title}");

    try {
      final streamUrl = await _ytService.fetchStreamUrl(newItem.originalUrl);

      if (streamUrl != null) {
        // デバイスが接続されている場合のみ送信
        if (device != null) {
          try {
            print("[Manager] Sending to Kodi playlist...");
            await dlnaService.addToPlaylist(device, streamUrl, newItem.title, newItem.thumbnailUrl);
            print("[Manager] Success: Sent to Kodi");
          } catch(e) {
            print("[Manager] Failed to add to Kodi: $e");
          }
        } else {
          print("[BG] Device not connected. Saved locally only.");
        }

        final index = _items.indexWhere((item) => item.id == newItem.id);
        if (index != -1) {
          _items[index] = newItem.copyWith(streamUrl: streamUrl, isResolving: false);
          _streamController.add(List.from(_items));
          _saveToStorage(); // 更新したら保存
        }
      } else {
        throw Exception("Stream URL not found");
      }
    } catch (e) {
      print("[BG] Failed: $e");
      final index = _items.indexWhere((item) => item.id == newItem.id);
      if (index != -1) {
        _items[index] = newItem.copyWith(isResolving: false, hasError: true);
        _streamController.add(List.from(_items));
        _saveToStorage();
      }
    }
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final item = _items.removeAt(oldIndex);
    _items.insert(newIndex, item);
    _streamController.add(List.from(_items));
    _saveToStorage();
  }

  void removeItem(int index) {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      _streamController.add(List.from(_items));
      _saveToStorage();
    }
  }

  void removeItems(Set<String> ids) {
    _items.removeWhere((item) => ids.contains(item.id));
    _streamController.add(List.from(_items));
    _saveToStorage(); // 削除したら保存
  }

  void clear() {
    _items.clear();
    _streamController.add([]);
    _saveToStorage();
  }
}