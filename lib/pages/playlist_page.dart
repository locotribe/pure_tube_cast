import 'package:flutter/material.dart';
import '../managers/playlist_manager.dart';
import '../services/dlna_service.dart';
import '../main.dart'; // DeviceListPageへの遷移用

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key});

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  // シングルトン化されたサービス
  final DlnaService _dlnaService = DlnaService();
  final PlaylistManager _manager = PlaylistManager();

  // 選択モードの状態管理
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedIds.clear(); // モード切替時に選択をリセット
    });
  }

  void _toggleItemSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _deleteSelectedItems() {
    if (_selectedIds.isEmpty) return;

    // 確認ダイアログ
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("削除"),
        content: Text("${_selectedIds.length}件のアイテムを削除しますか？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("キャンセル")),
          TextButton(
            onPressed: () {
              // マネージャーで一括削除
              _manager.removeItems(_selectedIds);

              Navigator.pop(ctx); // ダイアログを閉じる
              _toggleSelectionMode(); // 通常モードに戻す

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('削除しました')),
              );
            },
            child: const Text("削除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DlnaDevice?>(
      stream: _dlnaService.connectedDeviceStream,
      initialData: _dlnaService.currentDevice,
      builder: (context, deviceSnapshot) {
        final currentDevice = deviceSnapshot.data;
        final isConnected = currentDevice != null;

        return Scaffold(
          appBar: AppBar(
            // 選択モード時は「x件選択中」、通常時はタイトル
            title: _isSelectionMode
                ? Text("${_selectedIds.length}件選択中")
                : const Text("再生リスト"),
            leading: _isSelectionMode
                ? IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleSelectionMode,
            )
                : const BackButton(), // 通常の戻るボタン
            actions: [
              if (_isSelectionMode) ...[
                // 選択モード用アクション
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: _selectedIds.isNotEmpty ? _deleteSelectedItems : null,
                ),
              ] else ...[
                // 通常モード用アクション
                // 接続状態アイコン
                IconButton(
                  icon: Icon(
                    isConnected ? Icons.cast_connected : Icons.cast,
                    color: isConnected ? Colors.green : Colors.grey,
                  ),
                  tooltip: isConnected ? "接続中: ${currentDevice?.name}" : "デバイス未接続",
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const DeviceListPage()),
                    );
                  },
                ),
                // メニュー
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'select') {
                      _toggleSelectionMode();
                    } else if (value == 'clear') {
                      _showClearAllDialog();
                    }
                  },
                  itemBuilder: (BuildContext context) {
                    return [
                      const PopupMenuItem<String>(
                        value: 'select',
                        child: Row(
                          children: [
                            Icon(Icons.check_box_outlined, color: Colors.black87),
                            SizedBox(width: 8),
                            Text('選択して削除'),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'clear',
                        child: Row(
                          children: [
                            Icon(Icons.delete_sweep, color: Colors.red),
                            SizedBox(width: 8),
                            Text('リストを全消去', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ];
                  },
                ),
              ],
            ],
          ),
          body: StreamBuilder<List<LocalPlaylistItem>>(
            stream: _manager.itemsStream,
            initialData: _manager.currentItems,
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

              // 選択モード時は通常のListView
              if (_isSelectionMode) {
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isSelected = _selectedIds.contains(item.id);

                    return Card(
                      color: isSelected ? Colors.blue.shade50 : null,
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleItemSelection(item.id),
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: item.thumbnailUrl != null
                            ? SizedBox(
                          width: 50,
                          child: Image.network(item.thumbnailUrl!, fit: BoxFit.cover),
                        )
                            : null,
                        onTap: () => _toggleItemSelection(item.id),
                      ),
                    );
                  },
                );
              }

              // 通常モード
              return ReorderableListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                onReorder: (oldIndex, newIndex) {
                  _manager.reorder(oldIndex, newIndex);
                  if (isConnected && currentDevice != null) {
                    try {
                      _dlnaService.movePlaylistItem(currentDevice, oldIndex, newIndex < oldIndex ? newIndex : newIndex - 1);
                    } catch (e) {
                      print("[UI] Kodi reorder failed: $e");
                    }
                  }
                },
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Dismissible(
                    key: ValueKey(item.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (direction) {
                      _manager.removeItem(index);
                      if (isConnected && currentDevice != null) {
                        try {
                          _dlnaService.removeFromPlaylist(currentDevice, index);
                        } catch (e) { /* 無視 */ }
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('削除しました'), duration: Duration(seconds: 1)),
                      );
                    },
                    child: Card(
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
                          // ログ追加
                          print("[UI] Playlist item tapped: ${item.title} (ID: ${item.id})");
                          _showDetailDialog(context, item, index, isConnected, currentDevice);
                        },
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("リスト消去"),
        content: const Text("リストを全てクリアしますか？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("キャンセル")),
          TextButton(
            onPressed: () {
              _manager.clear();
              Navigator.pop(ctx);
            },
            child: const Text("クリア", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showDetailDialog(BuildContext context, LocalPlaylistItem item, int index, bool isConnected, DlnaDevice? currentDevice) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.thumbnailUrl != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  item.thumbnailUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => Container(
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.broken_image, size: 50),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                item.title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("閉じる"),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text("この動画から再生"),
            style: ElevatedButton.styleFrom(
              backgroundColor: isConnected ? Colors.red : Colors.grey,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              print("[UI] 'Play' button pressed for index: $index");
              if (isConnected && currentDevice != null && !item.isResolving && !item.hasError) {
                try {
                  await _dlnaService.playFromPlaylist(currentDevice, index);
                  print("[UI] Play command request finished");
                } catch(e) {
                  print("[UI] Play command failed: $e");
                }
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('再生中: ${item.title}'), duration: const Duration(seconds: 1)),
                );
              } else if (!isConnected) {
                print("[UI] Button pressed but device not connected");
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('デバイスに接続してください')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}