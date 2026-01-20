import '../managers/playlist_manager.dart';
import '../services/dlna_service.dart';
import '../models/playlist_model.dart';

class PlaylistPageLogic {
  final PlaylistManager _manager = PlaylistManager();
  final DlnaService _dlnaService = DlnaService();

  // --- Streams ---
  Stream<DlnaDevice?> get connectedDeviceStream => _dlnaService.connectedDeviceStream;
  Stream<List<PlaylistModel>> get playlistsStream => _manager.playlistsStream;

  // --- Current Data ---
  DlnaDevice? get currentDevice => _dlnaService.currentDevice;
  List<PlaylistModel> get currentPlaylists => _manager.currentPlaylists;

  // --- Actions ---

  /// アイテムを削除
  void removeItem(int index, String? playlistId) {
    _manager.removeItem(index, playlistId: playlistId);
  }

  /// 選択された複数のアイテムを削除
  void removeItems(Set<String> ids, String? playlistId) {
    _manager.removeItems(ids, playlistId: playlistId);
  }

  /// アイテムの並べ替え
  void reorderItems(int oldIndex, int newIndex, String? playlistId) {
    _manager.reorder(oldIndex, newIndex, playlistId: playlistId);
  }

  /// プレイリストの中身を全消去
  void clearPlaylist(String? playlistId) {
    _manager.clear(playlistId: playlistId);
  }

  /// 再生セッションを停止 (リセット)
  void stopSession(DlnaDevice device) {
    _manager.stopSession(device);
  }

  /// 再生またはジャンプを実行
  Future<void> playOrJump(DlnaDevice device, String? playlistId, int index) async {
    final pid = playlistId ?? (currentPlaylists.isNotEmpty ? currentPlaylists.first.id : null);
    if (pid != null) {
      await _manager.playOrJump(device, pid, index);
    }
  }

  /// アイテムを別のプレイリストへ移動
  void moveItem(String itemId, String? fromPlaylistId, String toPlaylistId) {
    _manager.moveItemToPlaylist(
        itemId,
        fromPlaylistId: fromPlaylistId,
        toPlaylistId: toPlaylistId
    );
  }

  /// 指定IDのプレイリストを取得 (なければデフォルトまたはダミーを返す)
  PlaylistModel getTargetPlaylist(String? playlistId) {
    final playlists = currentPlaylists;
    if (playlistId != null) {
      return playlists.firstWhere(
            (p) => p.id == playlistId,
        orElse: () => playlists.isNotEmpty
            ? playlists.first
            : PlaylistModel(id: 'dummy', name: 'Error', items: []),
      );
    } else {
      return playlists.isNotEmpty
          ? playlists.first
          : PlaylistModel(id: 'dummy', name: 'No Playlist', items: []);
    }
  }
}