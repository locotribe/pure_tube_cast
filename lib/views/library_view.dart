// lib/views/library_view.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../managers/playlist_manager.dart';
import '../services/dlna_service.dart';

class LibraryView extends StatefulWidget {
  const LibraryView({super.key});

  @override
  LibraryViewState createState() => LibraryViewState();
}

class LibraryViewState extends State<LibraryView> {
  final DlnaService _dlnaService = DlnaService();
  final PlaylistManager _manager = PlaylistManager();
  final ScrollController _scrollController = ScrollController();

  // 状態管理用
  String? _selectedPlaylistId; // 選択中のプレイリストID（nullなら一覧表示）
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  bool _hasInitialScrolled = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // --- ナビゲーション制御 ---

  void openPlaylist(String playlistId) {
    setState(() {
      _selectedPlaylistId = playlistId;
      _hasInitialScrolled = false;
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _closePlaylist() {
    if (_isSelectionMode) {
      _toggleSelectionMode();
    } else {
      setState(() {
        _selectedPlaylistId = null;
        _hasInitialScrolled = false;
      });
    }
  }

  // --- 詳細リスト用ロジック ---

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
              _manager.removeItems(_selectedIds, playlistId: _selectedPlaylistId);
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
              _manager.clear(playlistId: _selectedPlaylistId);
              Navigator.pop(ctx);
            },
            child: const Text("クリア", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // --- ダイアログ関連 ---

  void _showCreateDialog() {
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
                _manager.createPlaylist(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text("作成"),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(PlaylistModel playlist) {
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
                _manager.renamePlaylist(playlist.id, controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(PlaylistModel playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("削除"),
        content: Text("「${playlist.name}」を削除しますか？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("キャンセル")),
          TextButton(
            onPressed: () {
              _manager.deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
            child: const Text("削除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showResumeDialog(DlnaDevice device, PlaylistModel playlist) {
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
              _manager.playSequence(device, playlist.id, 0);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("最初から再生します")));
            },
            child: const Text("最初から"),
          ),
          ElevatedButton(
            onPressed: () {
              _manager.playSequence(device, playlist.id, playlist.lastPlayedIndex);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("続きから再生します")));
            },
            child: const Text("続きから"),
          ),
        ],
      ),
    );
  }

  void _showDetailDialog(LocalPlaylistItem item, int index, bool isConnected, DlnaDevice? currentDevice) {
    Widget expiryInfo = const SizedBox.shrink();
    Widget updateHelpMsg = const SizedBox.shrink();

    if (item.expirationDate != null) {
      final now = DateTime.now();
      final diff = item.expirationDate!.difference(now);
      final isExpired = diff.isNegative;
      final dateStr = "${item.expirationDate!.month}/${item.expirationDate!.day} "
          "${item.expirationDate!.hour.toString().padLeft(2, '0')}:${item.expirationDate!.minute.toString().padLeft(2, '0')}";

      expiryInfo = Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isExpired ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isExpired ? Colors.red : Colors.blue),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isExpired ? Icons.warning : Icons.timer,
                size: 16, color: isExpired ? Colors.red : Colors.blue),
            const SizedBox(width: 8),
            Text(
              isExpired ? "有効期限切れ ($dateStr)" : "有効期限: $dateStr",
              style: TextStyle(
                color: isExpired ? Colors.red : Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );

      if (isExpired) {
        updateHelpMsg = Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Icon(Icons.info_outline, size: 16, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "リンクの有効期限が切れています。\n下のボタンからブラウザで開き、新しい動画URLをコピーした後、ブラウザの『共有』機能からこのアプリを選んで戻ると、リンクを更新できます。",
                  style: TextStyle(fontSize: 11, color: Colors.brown),
                ),
              ),
            ],
          ),
        );
      }
    }

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
              child: Column(
                children: [
                  Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  expiryInfo,
                  updateHelpMsg,
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 【修正】移動・閉じるを上段、再生を下段に配置してオーバーフローを回避
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.drive_file_move_outline),
                      label: const Text("移動"),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showMoveToDialog(item);
                      },
                    ),
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("閉じる")),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text("再生"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isConnected ? Colors.red : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () async {
                      if (!isConnected || currentDevice == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('デバイスに接続してください')));
                        return;
                      }
                      final pid = _selectedPlaylistId ?? _manager.currentPlaylists.first.id;
                      Navigator.pop(ctx);
                      await _manager.playOrJump(currentDevice, pid, index);
                    },
                  ),
                ),

                const SizedBox(height: 12),
                const Divider(),

                // 既存の「ブラウザで開く」ボタン（変更なし）
                TextButton.icon(
                  icon: const Icon(Icons.open_in_browser, color: Colors.blue),
                  label: const Text("この動画をブラウザで開く", style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
                  onPressed: () async {
                    try {
                      final uri = Uri.parse(item.originalUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ブラウザを開けませんでした')));
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('無効なURLです')));
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMoveToDialog(LocalPlaylistItem item) {
    final playlists = _manager.currentPlaylists;
    final currentListId = _selectedPlaylistId;
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
                  style: TextStyle(color: isCurrent ? Colors.grey : Theme.of(context).colorScheme.onSurface),
                ),
                subtitle: Text("${list.items.length} items"),
                enabled: !isCurrent,
                onTap: () {
                  _manager.moveItemToPlaylist(
                    item.id,
                    fromPlaylistId: _selectedPlaylistId,
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

  // --- メインビルド ---

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

            // 詳細表示モード
            if (_selectedPlaylistId != null) {
              final targetList = playlists.firstWhere(
                      (p) => p.id == _selectedPlaylistId,
                  orElse: () => PlaylistModel(id: 'dummy', name: 'Error', items: [])
              );

              if (targetList.id == 'dummy') {
                WidgetsBinding.instance.addPostFrameCallback((_) => _closePlaylist());
                return const Center(child: CircularProgressIndicator());
              }

              return _buildDetailView(targetList, isConnected, currentDevice);
            }

            // 一覧表示モード
            return _buildFolderListView(playlists, isConnected, currentDevice);
          },
        );
      },
    );
  }

  // --- ビュー構築 (一覧) ---

  Widget _buildFolderListView(List<PlaylistModel> playlists, bool isConnected, DlnaDevice? currentDevice) {
    if (playlists.isEmpty) {
      return Stack(
        children: [
          const Center(child: Text("プレイリストがありません")),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: "add_playlist",
              onPressed: _showCreateDialog,
              child: const Icon(Icons.create_new_folder),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
          itemCount: playlists.length,
          onReorder: (oldIndex, newIndex) {
            _manager.reorderPlaylists(oldIndex, newIndex);
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
                onTap: () => openPlaylist(playlist.id),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_circle_fill, color: Colors.red, size: 32),
                      tooltip: "再生",
                      onPressed: (currentDevice != null && playlist.items.isNotEmpty)
                          ? () {
                        final lastIndex = playlist.lastPlayedIndex;
                        if (lastIndex > 0 && lastIndex < playlist.items.length) {
                          _showResumeDialog(currentDevice, playlist);
                        } else {
                          _manager.playSequence(currentDevice, playlist.id, 0);
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
                          _showRenameDialog(playlist);
                        } else if (value == 'delete') {
                          _showDeleteDialog(playlist);
                        } else if (value == 'play_start') {
                          if (currentDevice != null && playlist.items.isNotEmpty) {
                            _manager.playSequence(currentDevice, playlist.id, 0);
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
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: "add_playlist",
            onPressed: _showCreateDialog,
            child: const Icon(Icons.create_new_folder),
          ),
        ),
      ],
    );
  }

  // --- ビュー構築 (詳細) ---

  Widget _buildDetailView(PlaylistModel targetList, bool isConnected, DlnaDevice? currentDevice) {
    final items = targetList.items;

    if (!_hasInitialScrolled && items.isNotEmpty) {
      _scrollToPlayingItem(items);
    }

    // Androidの戻るボタンハンドリング
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closePlaylist();
      },
      child: Column(
        children: [
          // サブ操作バー
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _closePlaylist,
                ),
                Expanded(
                  child: _isSelectionMode
                      ? Text("${_selectedIds.length}件選択中", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                      : Text(targetList.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                ),
                if (_isSelectionMode)
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: _selectedIds.isNotEmpty ? _deleteSelectedItems : null,
                  ),
                if (!_isSelectionMode) ...[
                  if (isConnected)
                    IconButton(
                      icon: const Icon(Icons.playlist_remove, color: Colors.red),
                      tooltip: "再生リストクリア",
                      onPressed: _showResetDialog,
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
          ),

          // リスト本体
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text("リストは空です", style: TextStyle(color: Colors.grey)))
                : _buildDetailListBody(items, isConnected, currentDevice),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailListBody(List<LocalPlaylistItem> items, bool isConnected, DlnaDevice? currentDevice) {
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
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        onReorder: (oldIndex, newIndex) {
          _manager.reorder(oldIndex, newIndex, playlistId: _selectedPlaylistId);
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
              _manager.removeItem(index, playlistId: _selectedPlaylistId);
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

                      // サムネイル上の有効期限バッジ
                      if (item.expirationDate != null)
                        Builder(
                          builder: (context) {
                            final now = DateTime.now();
                            final diff = item.expirationDate!.difference(now);
                            final isExpired = diff.isNegative;

                            if (isExpired) {
                              return Container(
                                color: Colors.black.withOpacity(0.7),
                                alignment: Alignment.center,
                                child: const Text(
                                  "期限切れ",
                                  style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              );
                            }

                            String text;
                            Color bgColor;
                            if (diff.inHours < 1) {
                              text = "残り${diff.inMinutes}分";
                              bgColor = Colors.red;
                            } else if (diff.inHours < 24) {
                              text = "残り${diff.inHours}時間";
                              bgColor = Colors.orange;
                            } else {
                              text = "${item.expirationDate!.month}/${item.expirationDate!.day}まで";
                              bgColor = Colors.blueGrey;
                            }

                            return Positioned(
                              bottom: 0, left: 0, right: 0,
                              child: Container(
                                color: bgColor.withOpacity(0.8),
                                padding: const EdgeInsets.symmetric(vertical: 1),
                                alignment: Alignment.center,
                                child: Text(
                                  text,
                                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                ),
                              ),
                            );
                          },
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
                    color: isPlaying ? Colors.red : Theme.of(context).colorScheme.onSurface,
                  ),
                ),

                subtitle: Row(
                  children: [
                    Text(item.durationStr, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 12),

                    // 有効期限テキスト表示
                    if (item.expirationDate != null) ...[
                      Builder(
                          builder: (context) {
                            final diff = item.expirationDate!.difference(DateTime.now());
                            final isExpired = diff.isNegative;
                            String text;
                            Color color;

                            if (isExpired) {
                              text = "⚠ 期限切れ";
                              color = Colors.red;
                            } else if (diff.inHours < 3) {
                              text = "残り${diff.inHours}時間${diff.inMinutes % 60}分";
                              color = Colors.orange;
                            } else {
                              text = "${item.expirationDate!.month}/${item.expirationDate!.day} ${item.expirationDate!.hour}:${item.expirationDate!.minute.toString().padLeft(2,'0')}";
                              color = Colors.grey;
                            }

                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text(
                                text,
                                style: TextStyle(color: color, fontSize: 12, fontWeight: isExpired ? FontWeight.bold : FontWeight.normal),
                              ),
                            );
                          }
                      ),
                    ],

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
                  _showDetailDialog(item, index, isConnected, currentDevice);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}