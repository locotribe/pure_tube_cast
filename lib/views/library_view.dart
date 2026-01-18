import 'package:flutter/material.dart';
import '../managers/playlist_manager.dart';
import '../pages/playlist_page.dart'; // 詳細画面へ飛ぶために必要

class LibraryView extends StatelessWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = PlaylistManager();

    return Stack(
      children: [
        StreamBuilder<List<PlaylistModel>>(
          stream: manager.playlistsStream,
          initialData: manager.currentPlaylists,
          builder: (context, snapshot) {
            final playlists = snapshot.data ?? [];

            if (playlists.isEmpty) {
              return const Center(child: Text("プレイリストがありません"));
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80), // FABとかぶらないよう下余白
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: const Icon(Icons.folder, color: Colors.orange, size: 40),
                    title: Text(playlist.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("${playlist.items.length} videos"),
                    onTap: () {
                      // リストの中身へ遷移
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PlaylistPage(playlistId: playlist.id),
                        ),
                      );
                    },
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'rename') {
                          _showRenameDialog(context, manager, playlist);
                        } else if (value == 'delete') {
                          _showDeleteDialog(context, manager, playlist);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'rename', child: Text("名前を変更")),
                        const PopupMenuItem(value: 'delete', child: Text("削除", style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
        // 右下の追加ボタン
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

  // --- ダイアログ（PlaylistsPageと同じもの） ---
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