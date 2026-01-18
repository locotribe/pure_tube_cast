import 'package:flutter/material.dart';
import '../managers/playlist_manager.dart';
import '../services/dlna_service.dart';
import '../pages/playlist_page.dart';

class LibraryView extends StatelessWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = PlaylistManager();
    final dlnaService = DlnaService();

    return Stack(
      children: [
        StreamBuilder<DlnaDevice?>(
          stream: dlnaService.connectedDeviceStream,
          initialData: dlnaService.currentDevice,
          builder: (context, deviceSnapshot) {
            final currentDevice = deviceSnapshot.data;

            return StreamBuilder<List<PlaylistModel>>(
              stream: manager.playlistsStream,
              initialData: manager.currentPlaylists,
              builder: (context, snapshot) {
                final playlists = snapshot.data ?? [];

                if (playlists.isEmpty) {
                  return const Center(child: Text("プレイリストがありません"));
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    final bool isPlaying = playlist.items.any((item) => item.isPlaying);

                    return Card(
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
                            color: isPlaying ? Colors.red : Colors.black,
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
                                // 【修正】履歴を確認して分岐
                                final lastIndex = playlist.lastPlayedIndex;

                                // 途中まで再生していた履歴がある場合は確認ダイアログ
                                if (lastIndex > 0 && lastIndex < playlist.items.length) {
                                  _showResumeDialog(context, manager, currentDevice, playlist);
                                } else {
                                  // 履歴がない(0)なら最初から
                                  manager.playSequence(
                                      currentDevice,
                                      playlist.id,
                                      0
                                  );
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
                                  _showRenameDialog(context, manager, playlist);
                                } else if (value == 'delete') {
                                  _showDeleteDialog(context, manager, playlist);
                                } else if (value == 'play_start') {
                                  if (currentDevice != null && playlist.items.isNotEmpty) {
                                    manager.playSequence(currentDevice, playlist.id, 0);
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
            onPressed: () => _showCreateDialog(context, manager),
            child: const Icon(Icons.create_new_folder),
          ),
        ),
      ],
    );
  }

  // 【追加】再開確認ダイアログ
  void _showResumeDialog(BuildContext context, PlaylistManager manager, DlnaDevice device, PlaylistModel playlist) {
    // 再開する曲のタイトルを取得
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
            onPressed: () => Navigator.pop(context), // キャンセル
            child: const Text("キャンセル"),
          ),
          TextButton(
            onPressed: () {
              // 最初から再生
              manager.playSequence(device, playlist.id, 0);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("最初から再生します")));
            },
            child: const Text("最初から"),
          ),
          ElevatedButton(
            onPressed: () {
              // 続きから再生
              manager.playSequence(device, playlist.id, playlist.lastPlayedIndex);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("続きから再生します")));
            },
            child: const Text("続きから"),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context, PlaylistManager manager) {
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
                manager.createPlaylist(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text("作成"),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, PlaylistManager manager, PlaylistModel playlist) {
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
                manager.renamePlaylist(playlist.id, controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, PlaylistManager manager, PlaylistModel playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("削除"),
        content: Text("「${playlist.name}」を削除しますか？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("キャンセル")),
          TextButton(
            onPressed: () {
              manager.deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
            child: const Text("削除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}