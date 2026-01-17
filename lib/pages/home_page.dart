import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart'; // DeviceListPage, CastPageへのアクセス
import '../services/dlna_service.dart';
import 'playlist_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription? _intentStreamSubscription;

  @override
  void initState() {
    super.initState();
    _setupSharingListener();
  }

  @override
  void dispose() {
    _intentStreamSubscription?.cancel();
    super.dispose();
  }

  // YouTubeなどからの共有を監視
  void _setupSharingListener() {
    // アプリ起動中の共有受信
    _intentStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
          (List<SharedMediaFile> value) {
        if (value.isNotEmpty) _handleSharedText(value.first.path);
      },
      onError: (err) => print("[HomePage] Share Error: $err"),
    );

    // アプリ停止状態からの共有起動
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) _handleSharedText(value.first.path);
    });
  }

  void _handleSharedText(String sharedText) {
    // 共有されたら CastPage（動画確認画面）へ遷移
    // contextが有効か確認
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CastPage(initialUrl: sharedText),
      ),
    );
  }

  void _openYouTube() async {
    final Uri appUrl = Uri.parse('vnd.youtube://');
    final Uri webUrl = Uri.parse('https://www.youtube.com');
    if (await canLaunchUrl(appUrl)) {
      await launchUrl(appUrl, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("PureTube Cast")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 1. デバイス管理
            _buildMenuButton(
              icon: Icons.settings_remote,
              label: "デバイス管理",
              color: Colors.blueGrey,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DeviceListPage()),
                );
              },
            ),
            const SizedBox(height: 20),
            // 2. YouTubeを開く
            _buildMenuButton(
              icon: Icons.play_circle_fill,
              label: "YouTubeを開く",
              color: Colors.red,
              onTap: _openYouTube,
            ),
            const SizedBox(height: 20),
            // 3. プレイリスト
            _buildMenuButton(
              icon: Icons.playlist_play,
              label: "プレイリスト",
              color: Colors.orange,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PlaylistPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 250,
      height: 80,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 32),
        label: Text(label, style: const TextStyle(fontSize: 20)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
        ),
      ),
    );
  }
}