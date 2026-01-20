import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/playlist_model.dart';
import '../../models/local_playlist_item.dart';

class PlaylistStorageService {
  static const String _storageKeyV2 = 'saved_playlists_v2';
  static const String _storageKeyOld = 'saved_playlist';

  Future<void> savePlaylists(List<PlaylistModel> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonStr = jsonEncode(playlists.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKeyV2, jsonStr);
  }

  Future<List<PlaylistModel>> loadPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final String? newJsonStr = prefs.getString(_storageKeyV2);
    final List<PlaylistModel> playlists = [];

    if (newJsonStr != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(newJsonStr);
        playlists.addAll(jsonList.map((e) => PlaylistModel.fromJson(e)).toList());
      } catch (e) {
        print("[Storage] Load failed: $e");
      }
    } else {
      // 旧データの移行処理
      final String? oldJsonStr = prefs.getString(_storageKeyOld);
      if (oldJsonStr != null) {
        try {
          final List<dynamic> jsonList = jsonDecode(oldJsonStr);
          final oldItems = jsonList.map((e) => LocalPlaylistItem.fromJson(e)).toList();
          final mainList = PlaylistModel(
              id: 'default_main',
              name: 'メインリスト',
              items: oldItems.cast<LocalPlaylistItem>()
          );
          playlists.add(mainList);
          // 保存して移行完了とする
          await savePlaylists(playlists);
        } catch (e) {}
      }
    }
    return playlists;
  }
}