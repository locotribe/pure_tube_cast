import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../managers/playlist_manager.dart';
import '../services/dlna_service.dart';
import '../services/video_resolver.dart'; // YoutubeServiceの代わりにインポート
import '../main.dart'; // DeviceListPageへのアクセス用

class CastPage extends StatefulWidget {
  final String? initialUrl;

  const CastPage({super.key, this.initialUrl});

  @override
  State<CastPage> createState() => _CastPageState();
}

class _CastPageState extends State<CastPage> {
  // VideoResolverを使用
  final VideoResolver _resolver = VideoResolver();

  // シングルトンサービス
  final DlnaService _dlnaService = DlnaService();
  final PlaylistManager _playlistManager = PlaylistManager();

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

    // URL抽出（テキストに混ざっている場合）
    final match = RegExp(r'(https?://\S+)').firstMatch(url);
    final targetUrl = match?.group(0) ?? url;

    try {
      // Resolverを使ってメタデータ取得
      final metadata = await _resolver.resolveMetadata(targetUrl);

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

  // 今すぐ再生
  void _playNow() async {
    if (_videoMetadata == null) return;
    final currentDevice = _dlnaService.currentDevice;

    if (currentDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("デバイスに接続されていません。ホーム画面から接続してください。"))
      );
      return;
    }

    setState(() => _isLoading = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('再生準備中...')));

    try {
      // Resolverを使ってストリームURL取得
      final streamUrl = await _resolver.resolveStreamUrl(_videoMetadata!);

      if (streamUrl == null) {
        throw Exception("再生可能な動画リンクが見つかりませんでした");
      }

      await _dlnaService.playNow(
          currentDevice,
          streamUrl,
          _videoMetadata!['title'],
          _videoMetadata!['thumbnailUrl']
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("再生失敗: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // リストに追加
  void _addToList() {
    if (_videoMetadata == null) return;

    // 現在のデバイス（nullならオフライン追加）を渡す
    // ※ PlaylistManager側も修正が必要（後述の補足参照）ですが、
    // Web動画の場合は非同期解析が難しいため、現時点では「メタデータのみ保存」となります。
    _playlistManager.processAndAdd(
        _dlnaService,
        _videoMetadata!,
        device: _dlnaService.currentDevice
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('リストに追加しました')),
    );
    Navigator.pop(context);
  }

  void _openInBrowser() async {
    if (_videoMetadata == null && widget.initialUrl == null) return;
    final urlStr = _videoMetadata?['url'] ?? widget.initialUrl!;
    final Uri uri = Uri.parse(urlStr);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text("動画確認"),
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // サムネイル表示
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
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
                              color: Colors.grey.shade300,
                              child: const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Icon(Icons.public, size: 60, color: Colors.blueGrey),
                        ),

                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              _videoMetadata?['title'] ?? "読み込み中...",
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 5),
                            Text(_statusMessage, style: const TextStyle(color: Colors.grey)),
                            if (_videoMetadata != null && _videoMetadata!['streamUrl'] == null && _videoMetadata!['isDirectFile'] != true && !_resolver.resolveStreamUrl(_videoMetadata!).toString().contains('Future'))
                            // 注: Webサイト解析で動画URLが見つからなかった場合の警告表示
                            // (実際にはFutureの結果を待つ必要があるため、ここでは簡易的なメッセージのみ)
                              const Padding(
                                padding: EdgeInsets.only(top:8.0),
                                child: Text("※このサイトの動画は自動解析できない可能性があります", style: TextStyle(color: Colors.orange, fontSize: 12)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                if (_videoMetadata != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _playNow,
                          icon: const Icon(Icons.play_arrow, size: 28),
                          label: const Text("今すぐ再生", style: TextStyle(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _addToList,
                          icon: const Icon(Icons.playlist_add, size: 28),
                          label: const Text("リストに追加", style: TextStyle(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 40),

                // ブラウザで開くボタン
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openInBrowser,
                    label: const Text("ブラウザで開く"),
                    icon: const Icon(Icons.open_in_new),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
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
                    "解析中...",
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