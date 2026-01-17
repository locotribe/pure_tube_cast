import 'package:flutter/material.dart';
import '../managers/playlist_manager.dart';
import '../services/dlna_service.dart';

class PlaylistPage extends StatelessWidget {
  final DlnaDevice targetDevice;
  final DlnaService _dlnaService = DlnaService();

  PlaylistPage({super.key, required this.targetDevice});

  @override
  Widget build(BuildContext context) {
    final manager = PlaylistManager();

    return Scaffold(
      appBar: AppBar(
        title: const Text("再生リスト"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("リスト消去"),
                  content: const Text("リストを全てクリアしますか？"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("キャンセル")),
                    TextButton(
                      onPressed: () {
                        manager.clear();
                        Navigator.pop(ctx);
                      },
                      child: const Text("クリア", style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
          )
        ],
      ),
      body: StreamBuilder<List<LocalPlaylistItem>>(
        stream: manager.itemsStream,
        initialData: manager.currentItems,
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];

          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.playlist_remove, size: 60, color: Colors.grey),
                  SizedBox(height: 10),
                  Text("リストは空です", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            onReorder: (oldIndex, newIndex) {
              // 1. アプリ内リストを更新 (保存も自動で行われる)
              manager.reorder(oldIndex, newIndex);

              // 2. Kodiにも並べ替え命令を送る
              // (アプリ再起動後など、Kodi側のリストと同期が取れていない可能性もあるため、エラーが出ても無視する)
              try {
                _dlnaService.movePlaylistItem(targetDevice, oldIndex, newIndex < oldIndex ? newIndex : newIndex - 1);
              } catch (e) {
                print("[UI] Kodi reorder failed (sync issue?): $e");
              }
            },
            itemBuilder: (context, index) {
              final item = items[index];
              return Dismissible(
                // 【重要】indexではなく、アイテム固有のIDをキーにする（これでクラッシュが直る）
                key: ValueKey(item.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (direction) {
                  manager.removeItem(index);
                  try {
                    _dlnaService.removeFromPlaylist(targetDevice, index);
                  } catch (e) { /* 無視 */ }

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('削除しました'), duration: Duration(seconds: 1)),
                  );
                },
                child: Card(
                  // ReorderableListViewのアイテムキーもIDにする
                  key: ValueKey(item.id),
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(8),
                    leading: SizedBox(
                      width: 80,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.thumbnailUrl != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(
                                  item.thumbnailUrl!,
                                  width: 80,
                                  height: 45,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) => Container(
                                    width: 80, height: 45, color: Colors.grey.shade300,
                                    child: const Icon(Icons.broken_image, size: 20),
                                  ),
                                ),
                              )
                            else
                              const Icon(Icons.movie, size: 30),

                            const SizedBox(height: 2),
                            Text(
                              item.durationStr,
                              style: const TextStyle(fontSize: 11, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                    ),
                    title: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: item.isResolving
                        ? const Text("解析中...", style: TextStyle(color: Colors.orange, fontSize: 12))
                        : item.hasError
                        ? const Text("エラー", style: TextStyle(color: Colors.red, fontSize: 12))
                        : null,
                    onTap: () {
                      if (!item.isResolving && !item.hasError) {
                        _dlnaService.playFromPlaylist(targetDevice, index);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('再生中: ${item.title}'), duration: const Duration(seconds: 1)),
                        );
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}