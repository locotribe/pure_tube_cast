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

  final ScrollController _scrollController = ScrollController();

  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  bool _hasInitialScrolled = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToPlayingItem(List<LocalPlaylistItem> items) {
    if (_hasInitialScrolled) return;
    final playingIndex = items.indexWhere((item) => item.isPlaying);
    if (playingIndex != -1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          const double itemHeight = 90.0;
          final double screenHeight = _scrollController.position.viewportDimension;
          double targetOffset = (playingIndex * itemHeight) - (screenHeight / 2) + (itemHeight / 2);
          if (targetOffset < 0) targetOffset = 0;
          if (targetOffset > _scrollController.position.maxScrollExtent) {
            targetOffset = _scrollController.position.maxScrollExtent;
          }
          _scrollController.jumpTo(targetOffset);
        }
      });
    }
    _hasInitialScrolled = true;
  }

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

  // 【追加】リセット確認ダイアログ
  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("再生リストクリア"),
        content: const Text("現在の送信済み再生リストをリセットしますか？\n※現在再生されている動画は停止しません"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("キャンセル")),
          TextButton(
            onPressed: () {
              if (_dlnaService.currentDevice != null) {
                _manager.stopSession(_dlnaService.currentDevice!);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('リセットしました')));
              }
              Navigator.pop(ctx);
            },
            child: const Text("リセット", style: TextStyle(color: Colors.red)),
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

            if (!_hasInitialScrolled && items.isNotEmpty) {
              _scrollToPlayingItem(items);
            }

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
                    // 【追加】再生リストクリア
                    if (isConnected)
                      IconButton(
                        icon: const Icon(Icons.playlist_remove, color: Colors.red),
                        tooltip: "再生リストクリア",
                        onPressed: _showResetDialog,
                      ),

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
    const double scrollbarThickness = 12.0;
    const bool isScrollbarInteractive = true;

    if (_isSelectionMode) {
      return Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        thickness: scrollbarThickness,
        interactive: isScrollbarInteractive,
        radius: const Radius.circular(8.0),
        child: ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
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
        ),
      );
    }

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      thickness: scrollbarThickness,
      interactive: isScrollbarInteractive,
      radius: const Radius.circular(8.0),
      child: ReorderableListView.builder(
        scrollController: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        itemCount: items.length,
        onReorder: (oldIndex, newIndex) {
          _manager.reorder(oldIndex, newIndex, playlistId: widget.playlistId);
        },
        itemBuilder: (context, index) {
          final item = items[index];
          final isPlaying = item.isPlaying;

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
              elevation: isPlaying ? 4 : 2,
              color: isPlaying ? Colors.red.shade50 : null,
              shape: isPlaying
                  ? RoundedRectangleBorder(side: const BorderSide(color: Colors.red, width: 2), borderRadius: BorderRadius.circular(12))
                  : null,
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                contentPadding: const EdgeInsets.all(8),

                leading: SizedBox(
                  width: 80,
                  height: 45,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: item.thumbnailUrl != null
                              ? Image.network(item.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.movie))
                              : const Icon(Icons.movie, color: Colors.grey),
                        ),
                      ),
                      if (isPlaying)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: Icon(Icons.equalizer, color: Colors.red, size: 24),
                          ),
                        ),
                    ],
                  ),
                ),

                title: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                      color: isPlaying ? Colors.red : Colors.black
                  ),
                ),

                subtitle: Row(
                  children: [
                    Text(item.durationStr, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 12),
                    if (item.hasError) ...[
                      const Icon(Icons.error, size: 16, color: Colors.red),
                      const SizedBox(width: 4),
                      const Text("エラー", style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                    ] else if (item.isResolving) ...[
                      const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 6),
                      const Text("解析中...", style: TextStyle(color: Colors.orange, fontSize: 12)),
                    ] else if (item.isQueued) ...[
                      const Icon(Icons.check_circle, size: 16, color: Colors.green),
                      const SizedBox(width: 4),
                      const Text("送信済", style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
                onTap: () {
                  _showDetailDialog(context, item, index, isConnected, currentDevice);
                },
              ),
            ),
          );
        },
      ),
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

                  // 【修正】タップ時は「ジャンプ」か「新規」かを自動判定するメソッドを呼ぶ
                  Navigator.pop(ctx);
                  await _manager.playOrJump(currentDevice, pid, index);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMoveToDialog(BuildContext context, LocalPlaylistItem item) {
    // ... (既存のまま) ...
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