import 'package:flutter/material.dart';
import '../managers/playlist_manager.dart';
import '../services/dlna_service.dart';
import 'connection_page.dart';

class PlaylistPage extends StatefulWidget {
  final String? playlistId;

  const PlaylistPage({super.key, this.playlistId});

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  final DlnaService _dlnaService = DlnaService();
  final PlaylistManager _manager = PlaylistManager();

  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedIds.clear();
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("削除"),
        content: Text("${_selectedIds.length}件のアイテムを削除しますか？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("キャンセル")),
          TextButton(
            onPressed: () {
              _manager.removeItems(_selectedIds, playlistId: widget.playlistId);
              Navigator.pop(ctx);
              _toggleSelectionMode();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('削除しました')));
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

        return StreamBuilder<List<PlaylistModel>>(
          stream: _manager.playlistsStream,
          initialData: _manager.currentPlaylists,
          builder: (context, snapshot) {
            final playlists = snapshot.data ?? [];

            final targetList = widget.playlistId != null
                ? playlists.firstWhere((p) => p.id == widget.playlistId, orElse: () => playlists.isNotEmpty ? playlists.first : PlaylistModel(id: 'dummy', name: 'Error', items: []))
                : (playlists.isNotEmpty ? playlists.first : null);

            if (targetList == null) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            final items = targetList.items;

            return Scaffold(
              appBar: AppBar(
                title: _isSelectionMode
                    ? Text("${_selectedIds.length}件選択中")
                    : Text(targetList.name),
                leading: _isSelectionMode
                    ? IconButton(icon: const Icon(Icons.close), onPressed: _toggleSelectionMode)
                    : const BackButton(),
                actions: [
                  if (_isSelectionMode) ...[
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: _selectedIds.isNotEmpty ? _deleteSelectedItems : null,
                    ),
                  ] else ...[
                    IconButton(
                      icon: Icon(
                        isConnected ? Icons.cast_connected : Icons.cast,
                        color: isConnected ? Colors.green : Colors.grey,
                      ),
                      tooltip: isConnected ? "接続中: ${currentDevice?.name}" : "デバイス未接続",
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ConnectionPage()),
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'select') _toggleSelectionMode();
                        else if (value == 'clear') _showClearAllDialog();
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'select',
                          child: Row(children: [Icon(Icons.check_box_outlined), SizedBox(width: 8), Text('選択して削除')]),
                        ),
                        const PopupMenuItem(
                          value: 'clear',
                          child: Row(children: [Icon(Icons.delete_sweep, color: Colors.red), SizedBox(width: 8), Text('リストを全消去', style: TextStyle(color: Colors.red))]),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              body: items.isEmpty
                  ? const Center(child: Text("リストは空です", style: TextStyle(color: Colors.grey)))
                  : _buildListBody(items, isConnected, currentDevice),
            );
          },
        );
      },
    );
  }

  Widget _buildListBody(List<LocalPlaylistItem> items, bool isConnected, DlnaDevice? currentDevice) {
    if (_isSelectionMode) {
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final isSelected = _selectedIds.contains(item.id);
          return Card(
            color: isSelected ? Colors.blue.shade50 : null,
            child: ListTile(
              leading: Checkbox(value: isSelected, onChanged: (_) => _toggleItemSelection(item.id)),
              title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _toggleItemSelection(item.id),
            ),
          );
        },
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      onReorder: (oldIndex, newIndex) {
        _manager.reorder(oldIndex, newIndex, playlistId: widget.playlistId);
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
          confirmDismiss: (direction) async {
            return await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text("確認"),
                content: Text("「${item.title}」\nを削除しますか？"),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("キャンセル")),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("削除", style: TextStyle(color: Colors.red))),
                ],
              ),
            );
          },
          onDismissed: (direction) {
            _manager.removeItem(index, playlistId: widget.playlistId);
          },
          child: Card(
            key: ValueKey(item.id),
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              contentPadding: const EdgeInsets.all(8),
              leading: SizedBox(
                width: 80,
                child: item.thumbnailUrl != null
                    ? Image.network(item.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.movie))
                    : const Icon(Icons.movie),
              ),
              title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Row(
                children: [
                  if (item.hasError) ...[
                    const Icon(Icons.error_outline, size: 16, color: Colors.red),
                    const SizedBox(width: 4),
                    const Text("取得エラー", style: TextStyle(color: Colors.red, fontSize: 12)),
                  ] else if (item.isResolving) ...[
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    const Text("解析中...", style: TextStyle(color: Colors.orange, fontSize: 12)),
                  ] else ...[
                    Text(item.durationStr),
                  ],
                ],
              ),
              onTap: () {
                // index をしっかり渡す
                _showDetailDialog(context, item, index, isConnected, currentDevice);
              },
            ),
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
        content: const Text("このリストの中身を全てクリアしますか？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("キャンセル")),
          TextButton(
            onPressed: () {
              _manager.clear(playlistId: widget.playlistId);
              Navigator.pop(ctx);
            },
            child: const Text("クリア", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // indexを受け取るように修正
  void _showDetailDialog(BuildContext context, LocalPlaylistItem item, int index, bool isConnected, DlnaDevice? currentDevice) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.thumbnailUrl != null)
              AspectRatio(aspectRatio: 16 / 9, child: Image.network(item.thumbnailUrl!, fit: BoxFit.cover)),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.drive_file_move_outline),
            label: const Text("移動"),
            onPressed: () {
              Navigator.pop(ctx);
              _showMoveToDialog(context, item);
            },
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("閉じる")),
              const SizedBox(width: 8),

              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text("再生"),
                style: ElevatedButton.styleFrom(backgroundColor: isConnected ? Colors.red : Colors.grey, foregroundColor: Colors.white),
                onPressed: () async {
                  if (!isConnected || currentDevice == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('デバイスに接続してください')));
                    return;
                  }

                  final pid = widget.playlistId ?? _manager.currentPlaylists.first.id;

                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('連続再生を開始します')));

                  // index を使って連続再生
                  await _manager.playSequence(currentDevice, pid, index);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMoveToDialog(BuildContext context, LocalPlaylistItem item) {
    final playlists = _manager.currentPlaylists;
    final currentListId = widget.playlistId ?? (playlists.isNotEmpty ? playlists.first.id : null);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("移動先のリストを選択"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final list = playlists[index];
              final isCurrent = list.id == currentListId;

              return ListTile(
                leading: Icon(Icons.folder, color: isCurrent ? Colors.grey : Colors.orange),
                title: Text(
                  list.name,
                  style: TextStyle(color: isCurrent ? Colors.grey : Colors.black),
                ),
                subtitle: Text("${list.items.length} items"),
                enabled: !isCurrent,
                onTap: () {
                  _manager.moveItemToPlaylist(
                    item.id,
                    fromPlaylistId: widget.playlistId,
                    toPlaylistId: list.id,
                  );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("「${list.name}」へ移動しました")),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("キャンセル")),
        ],
      ),
    );
  }
}