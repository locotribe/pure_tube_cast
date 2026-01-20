import '../managers/playlist_manager.dart';
import '../services/dlna_service.dart';
import '../models/playlist_model.dart';

class LibraryLogic {
  final PlaylistManager _manager = PlaylistManager();
  final DlnaService _dlnaService = DlnaService();

  // --- Streams ---
  Stream<DlnaDevice?> get connectedDeviceStream => _dlnaService.connectedDeviceStream;
  Stream<List<PlaylistModel>> get playlistsStream => _manager.playlistsStream;

  // --- Current Data ---
  DlnaDevice? get currentDevice => _dlnaService.currentDevice;
  List<PlaylistModel> get currentPlaylists => _manager.currentPlaylists;

  // --- Actions ---

  /// プレイリストの並べ替え
  void reorderPlaylists(int oldIndex, int newIndex) {
    _manager.reorderPlaylists(oldIndex, newIndex);
  }

  /// 新規プレイリスト作成
  void createPlaylist(String name) {
    _manager.createPlaylist(name);
  }

  /// プレイリスト名変更
  void renamePlaylist(String id, String newName) {
    _manager.renamePlaylist(id, newName);
  }

  /// プレイリスト削除
  void deletePlaylist(String id) {
    _manager.deletePlaylist(id);
  }

  /// プレイリストを再生 (指定インデックスから)
  Future<void> playPlaylist(DlnaDevice device, String playlistId, {int index = 0}) async {
    await _manager.playSequence(device, playlistId, index);
  }
}