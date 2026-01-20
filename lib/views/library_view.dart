import 'package:flutter/material.dart';
import '../models/playlist_model.dart';
import '../services/dlna_service.dart';
import '../pages/playlist_page.dart';
import '../logics/library_logic.dart'; // ロジッククラス

class LibraryView extends StatelessWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context) {
    final logic = LibraryLogic();

    return Stack(
      children: [
        // デバイス接続状態の監視
        StreamBuilder<DlnaDevice?>(
          stream: logic.connectedDeviceStream,
          initialData: logic.currentDevice,
          builder: (context, deviceSnapshot) {
            final currentDevice = deviceSnapshot.data;

            // プレイリスト一覧の監視
            return StreamBuilder<List<PlaylistModel>>(
              stream: logic.playlistsStream,
              initialData: logic.currentPlaylists,
              builder: (context, snapshot) {
                final playlists = snapshot.data ?? [];

                if (playlists.isEmpty) {
                  return const Center(child: Text("プレイリストがありません"));
                }

                return ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                  itemCount: playlists.length,
                  // 並べ替え時の処理
                  onReorder: (oldIndex, newIndex) {
                    logic.reorderPlaylists(oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    final bool isPlaying = playlist.items.any((item) => item.isPlaying);

                    return Card(
                      key: ValueKey(playlist.id),
                      elevation: isPlaying ? 4 : 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: isPlaying
                          ? RoundedRectangleBorder(side: const BorderSide(color: Colors.red, width: 1.5), borderRadius: BorderRadius.circular(12))
                          : null,
                      child: ListTile(
                        leading: SizedBox(
                          width: 48,
                          height: 48,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                  Icons.folder,
                                  color: isPlaying ? Colors.red : Colors.orange,
                                  size: 40
                              ),
                              if (isPlaying)
                                const Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Icon(Icons.play_circle_fill, color: Colors.white, size: 18),
                                ),
                              if (isPlaying)
                                const Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Icon(Icons.play_circle_outline, color: Colors.red, size: 18),
                                ),
                            ],
                          ),
                        ),
                        title: Text(
                          playlist.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isPlaying ? Colors.red : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text("${playlist.items.length} videos"),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PlaylistPage(playlistId: playlist.id),
                            ),
                          );
                        },
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_circle_fill, color: Colors.red, size: 32),
                              tooltip: "再生",
                              onPressed: (currentDevice != null && playlist.items.isNotEmpty)
                                  ? () {
                                final lastIndex = playlist.lastPlayedIndex;
                                // レジューム再生の確認
                                if (lastIndex > 0 && lastIndex < playlist.items.length) {
                                  _showResumeDialog(context, logic, currentDevice, playlist);
                                } else {
                                  logic.playPlaylist(currentDevice, playlist.id, index: 0);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text("「${playlist.name}」を再生します"))
                                  );
                                }
                              }
                                  : null,
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'rename') {
                                  _showRenameDialog(context, logic, playlist);
                                } else if (value == 'delete') {
                                  _showDeleteDialog(context, logic, playlist);
                                } else if (value == 'play_start') {
                                  if (currentDevice != null && playlist.items.isNotEmpty) {
                                    logic.playPlaylist(currentDevice, playlist.id, index: 0);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text("最初から再生します"))
                                    );
                                  }
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'play_start', child: Text("最初から再生")),
                                const PopupMenuItem(value: 'rename', child: Text("名前を変更")),
                                const PopupMenuItem(value: 'delete', child: Text("削除", style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: "add_playlist",
            onPressed: () => _showCreateDialog(context, logic),
            child: const Icon(Icons.create_new_folder),
          ),
        ),
      ],
    );
  }

  void _showResumeDialog(BuildContext context, LibraryLogic logic, DlnaDevice device, PlaylistModel playlist) {
    final lastItemTitle = playlist.items[playlist.lastPlayedIndex].title;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("再生オプション"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("前回の続きから再生しますか？"),
            const SizedBox(height: 8),
            Text("対象: $lastItemTitle", style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("キャンセル"),
          ),
          TextButton(
            onPressed: () {
              logic.playPlaylist(device, playlist.id, index: 0);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("最初から再生します")));
            },
            child: const Text("最初から"),
          ),
          ElevatedButton(
            onPressed: () {
              logic.playPlaylist(device, playlist.id, index: playlist.lastPlayedIndex);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("続きから再生します")));
            },
            child: const Text("続きから"),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context, LibraryLogic logic) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("新規プレイリスト"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "リスト名"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("キャンセル")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                logic.createPlaylist(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text("作成"),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, LibraryLogic logic, PlaylistModel playlist) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("名前を変更"),
        content: TextField(
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("キャンセル")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                logic.renamePlaylist(playlist.id, controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, LibraryLogic logic, PlaylistModel playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("削除"),
        content: Text("「${playlist.name}」を削除しますか？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("キャンセル")),
          TextButton(
            onPressed: () {
              logic.deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
            child: const Text("削除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}