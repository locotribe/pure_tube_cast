import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // MethodChannel用
import 'package:url_launcher/url_launcher.dart';

import '../managers/playlist_manager.dart';
import '../services/dlna_service.dart';
import '../services/video_resolver.dart';
import 'playlist_page.dart';

class CastPage extends StatefulWidget {
  final String? initialUrl;

  const CastPage({super.key, this.initialUrl});

  @override
  State<CastPage> createState() => _CastPageState();
}

class _CastPageState extends State<CastPage> {
  final VideoResolver _resolver = VideoResolver();
  final DlnaService _dlnaService = DlnaService();
  final PlaylistManager _playlistManager = PlaylistManager();

  // Androidネイティブ連携用チャンネル
  static const platform = MethodChannel('com.example.pure_tube_cast/app_control');

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

    final match = RegExp(r'(https?://\S+)').firstMatch(url);
    final targetUrl = match?.group(0) ?? url;

    try {
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

  // 1. リストに追加して続ける (YouTubeに戻る: 最小化)
  void _addAndContinue() async {
    if (_videoMetadata == null) return;

    // リストに追加
    _playlistManager.processAndAdd(
        _dlnaService,
        _videoMetadata!,
        device: _dlnaService.currentDevice
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("リストに追加しました")),
    );

    // 【変更】アプリを最小化して、裏にあるYouTubeを表示させる
    try {
      await platform.invokeMethod('moveTaskToBack');
    } catch (e) {
      print("[CastPage] Failed to minimize app: $e");
      // 失敗時のフォールバックとして従来のlaunchUrlを使う手もあるが、
      // 基本的にAndroidなら成功するのでエラーログのみ
    }

    // 万が一戻ってきたときのために画面を閉じておく
    if (mounted) Navigator.pop(context);
  }

  // 2. リストに追加して確認 (リスト画面へ)
  void _addAndCheck() {
    if (_videoMetadata == null) return;

    _playlistManager.processAndAdd(
        _dlnaService,
        _videoMetadata!,
        device: _dlnaService.currentDevice
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("リストに追加しました")),
    );

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const PlaylistPage()),
      );
    }
  }

  // 3. リストに追加して今すぐ再生
  Future<void> _addAndPlayNow() async {
    if (_videoMetadata == null) return;

    final currentDevice = _dlnaService.currentDevice;
    if (currentDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("デバイスに接続されていません"))
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _playlistManager.processAndAdd(
          _dlnaService,
          _videoMetadata!,
          device: currentDevice
      );

      final index = _playlistManager.currentItems.length - 1;
      await _dlnaService.playFromPlaylist(currentDevice, index);

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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const PlaylistPage()),
      );
    }
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
                          child: Icon(Icons.playlist_add_check, size: 60, color: Colors.blueGrey),
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