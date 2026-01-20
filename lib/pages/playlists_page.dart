import 'package:flutter/material.dart';
import '../models/playlist_model.dart';
import 'playlist_page.dart';
import '../logics/library_logic.dart'; // ロジッククラスを再利用

class PlaylistsPage extends StatelessWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // LibraryViewと同じロジッククラスを使用
    final logic = LibraryLogic();

    return Scaffold(
      appBar: AppBar(title: const Text("ライブラリ")),
      body: StreamBuilder<List<PlaylistModel>>(
        stream: logic.playlistsStream,
        initialData: logic.currentPlaylists,
        builder: (context, snapshot) {
          final playlists = snapshot.data ?? [];

          if (playlists.isEmpty) {
            return const Center(child: Text("プレイリストがありません"));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
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
                    // タップしたらそのリストの中身（PlaylistPage）へ移動
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
                        _showRenameDialog(context, logic, playlist);
                      } else if (value == 'delete') {
                        _showDeleteDialog(context, logic, playlist);
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context, logic),
        child: const Icon(Icons.create_new_folder),
      ),
    );
  }

  // --- ダイアログ ---

  void _showCreateDialog(BuildContext context, LibraryLogic logic) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("新規プレイリスト"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "リスト名 (例: お気に入り)"),
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
        content: Text("「${playlist.name}」を削除しますか？\n中の動画もすべて削除されます。"),
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