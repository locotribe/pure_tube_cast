import 'package:flutter/material.dart';

import '../logics/cast_logic.dart'; // ロジッククラスをインポート
import 'playlist_page.dart';

class CastPage extends StatefulWidget {
  final String? initialUrl;

  const CastPage({super.key, this.initialUrl});

  @override
  State<CastPage> createState() => _CastPageState();
}

class _CastPageState extends State<CastPage> {
  final CastLogic _logic = CastLogic();

  String _statusMessage = "読み込み中...";
  Map<String, dynamic>? _videoMetadata;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) {
      _processUrl(widget.initialUrl!);
    } else {
      _statusMessage = "URLが指定されていません";
    }
  }

  Future<void> _processUrl(String url) async {
    print("[CastPage] Processing URL: $url");
    if (mounted) {
      setState(() {
        _isLoading = true;
        _statusMessage = "情報を取得中...";
        _videoMetadata = null;
      });
    }

    try {
      final metadata = await _logic.resolveVideo(url);

      if (mounted) {
        if (metadata != null) {
          setState(() {
            _videoMetadata = metadata;
            _statusMessage = "操作を選択してください";
            _isLoading = false;
          });
        } else {
          setState(() {
            _statusMessage = "動画情報の取得に失敗しました";
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() {
        _statusMessage = "エラー: $e";
        _isLoading = false;
      });
    }
  }

  // --- プレイリスト選択と追加の共通ロジック ---

  // 戻り値: 追加先のプレイリストID (キャンセル時はnull)
  Future<String?> _selectPlaylistAndAdd() async {
    if (_videoMetadata == null) return null;

    final playlists = _logic.getPlaylists();

    // リストが空なら作成（基本ありえないが念のため）
    if (playlists.isEmpty) {
      _logic.createPlaylist("メインリスト");
    }

    String? targetId;

    // リストが複数ある場合は選択させる
    if (playlists.length > 1) {
      targetId = await showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text("追加先のリストを選択", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final list = playlists[index];
                    return ListTile(
                      leading: const Icon(Icons.folder, color: Colors.orange),
                      title: Text(list.name),
                      subtitle: Text("${list.items.length} items"),
                      onTap: () => Navigator.pop(context, list.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          );
        },
      );

      // キャンセルされた場合
      if (targetId == null) return null;

    } else {
      // 1つしかない場合はそれを使う
      targetId = playlists.first.id;
    }

    // 選択されたリストに追加（バックグラウンド処理）
    await _logic.addToLocalPlaylist(_videoMetadata!, targetId);

    return targetId;
  }


  // --- アクション ---

  // 1. リストに追加して続ける (YouTubeに戻る: 最小化)
  void _addAndContinue() async {
    final targetId = await _selectPlaylistAndAdd();
    if (targetId == null) return; // キャンセル

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("リストに追加しました")),
      );
    }

    // アプリ最小化
    await _logic.minimizeApp();

    if (mounted) Navigator.pop(context);
  }

  // 2. リストに追加して確認 (リスト画面へ)
  void _addAndCheck() async {
    final targetId = await _selectPlaylistAndAdd();
    if (targetId == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("リストに追加しました")),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => PlaylistPage(playlistId: targetId)),
      );
    }
  }

  // 3. リストに追加して今すぐ再生
  Future<void> _addAndPlayNow() async {
    final currentDevice = _logic.getCurrentDevice();
    if (currentDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("デバイスに接続されていません"))
      );
      return;
    }

    // まずリストに追加（UI選択含む）
    final targetId = await _selectPlaylistAndAdd();
    if (targetId == null) return;

    setState(() => _isLoading = true);

    try {
      // Kodiにも追加して再生する処理
      final streamUrl = await _logic.resolveStreamUrl(_videoMetadata!);

      if (streamUrl != null) {
        // Kodiに対して「今すぐ再生」を実行 (リストはクリアされるが即再生)
        await _logic.playNowOnDevice(
            currentDevice,
            streamUrl,
            _videoMetadata!
        );
      }

    } catch (e) {
      print("[CastPage] Play Now Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("再生エラー: $e")),
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
      // 該当のプレイリスト画面へ移動
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => PlaylistPage(playlistId: targetId)),
      );
    }
  }

  void _openInBrowser() async {
    if (_videoMetadata == null && widget.initialUrl == null) return;
    final urlStr = _videoMetadata?['url'] ?? widget.initialUrl!;
    _logic.openInBrowser(urlStr);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text("カートに追加"),
            leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      if (_videoMetadata != null && _videoMetadata!['thumbnailUrl'] != null)
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.network(
                            _videoMetadata!['thumbnailUrl'],
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Icon(Icons.playlist_add_check, size: 60, color: Colors.blueGrey),
                        ),

                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              _videoMetadata?['title'] ?? "読み込み中...",
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 5),
                            Text(_statusMessage, style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                if (_videoMetadata != null) ...[
                  // A: 続ける (最小化)
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: _addAndContinue,
                      icon: const Icon(Icons.reply, size: 26),
                      label: const Text("リストに追加して 続ける", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // B: 確認
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: OutlinedButton.icon(
                      onPressed: _addAndCheck,
                      icon: const Icon(Icons.playlist_play, size: 26),
                      label: const Text("リストに追加して 確認", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.blue, width: 2),
                        foregroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // C: 今すぐ再生
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: _addAndPlayNow,
                      icon: const Icon(Icons.play_arrow, size: 26),
                      label: const Text("リストに追加して 今すぐ再生", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 30),
                TextButton.icon(
                  onPressed: _openInBrowser,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text("ブラウザで開く"),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                ),
              ],
            ),
          ),
        ),

        if (_isLoading)
          Container(
            color: Colors.black.withOpacity(0.5),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 20),
                  Text(
                    "処理中...",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}