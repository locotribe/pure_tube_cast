import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

import '../views/device_view.dart';
import '../views/web_video_view.dart';
import '../views/library_view.dart';
import '../managers/site_manager.dart';
import '../managers/playlist_manager.dart'; // PlaylistManager追加
import '../pages/playlist_page.dart';
import 'cast_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  StreamSubscription? _intentStreamSubscription;
  final SiteManager _siteManager = SiteManager();
  final PlaylistManager _playlistManager = PlaylistManager(); // 追加

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

  void _setupSharingListener() {
    _intentStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
          (List<SharedMediaFile> value) {
        if (value.isNotEmpty) _handleSharedText(value.first.path);
      },
      onError: (err) => print("[HomePage] Share Error: $err"),
    );

    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) _handleSharedText(value.first.path);
    });
  }

  // 【改修】ミックスリスト対策を含む自動判定ロジック
  void _handleSharedText(String url) {
    if (!mounted) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    // 1. YouTubeの判定
    if (uri.host.contains('youtube.com') || uri.host.contains('youtu.be')) {

      // A. プレイリスト一括取込判定
      // listパラメータがあり、かつ "RD" (Mix) で始まらないもの
      if (uri.queryParameters.containsKey('list')) {
        final listId = uri.queryParameters['list']!;
        if (!listId.startsWith('RD')) {
          _importPlaylist(url);
          return;
        }
        // RD(Mix)の場合は、単体動画として下の処理（C）へ流す
      }

      // B. チャンネル・トップ -> サイト登録
      // @channel, /channel/, またはパス無し
      if (uri.path.startsWith('/@') || uri.path.startsWith('/channel') || uri.path.isEmpty || uri.path == '/') {
        if (_siteManager.isRegistered(url)) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("このサイトは既に登録されています")));
          return;
        }
        _fetchInfoAndShowAddDialog(url);
        return;
      }

      // C. 動画 (vパラメータ, youtu.be, shorts, またはMixリストの動画) -> 動画解析
      bool isVideo = false;
      if (uri.queryParameters.containsKey('v')) isVideo = true;
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) isVideo = true;
      if (uri.path.startsWith('/shorts/')) isVideo = true;
      // Mixリストもここまで来れば動画として扱われる

      if (isVideo) {
        _navigateToCastPage(url);
        return;
      }
    }

    // 2. 他サイトのトップページ判定 -> サイト登録
    if (uri.path.isEmpty || uri.path == '/') {
      if (_siteManager.isRegistered(url)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("このサイトは既に登録されています")));
        return;
      }
      _fetchInfoAndShowAddDialog(url);
      return;
    }

    // 3. 動画ファイル直リンク -> 動画解析
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.endsWith('.mp4') || lowerUrl.endsWith('.m3u8') || lowerUrl.endsWith('.mov')) {
      _navigateToCastPage(url);
      return;
    }

    // 4. 判定不能 -> 選択メニュー
    _showSelectionModal(url);
  }

  // --- 各アクション ---

  void _navigateToCastPage(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CastPage(initialUrl: url)),
    );
  }

  Future<void> _importPlaylist(String url) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text("プレイリストを取得中...", style: TextStyle(color: Colors.white, decoration: TextDecoration.none, fontSize: 14)),
          ],
        ),
      ),
    );

    final newId = await _playlistManager.importFromYoutubePlaylist(url);

    if (!mounted) return;
    Navigator.pop(context);

    if (newId != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("プレイリストを取り込みました")));
      setState(() => _selectedIndex = 1);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => PlaylistPage(playlistId: newId)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("プレイリストの取得に失敗しました")));
    }
  }

  Future<void> _fetchInfoAndShowAddDialog(String url) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    String title = "";
    String? iconUrl;

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final document = parser.parse(response.body);
        title = document.querySelector('title')?.text ?? "";

        var iconLink = document.querySelector('link[rel="icon"]')?.attributes['href'];
        iconLink ??= document.querySelector('link[rel="shortcut icon"]')?.attributes['href'];
        iconLink ??= document.querySelector('link[rel="apple-touch-icon"]')?.attributes['href'];

        if (iconLink != null && iconLink.isNotEmpty) {
          iconUrl = Uri.parse(url).resolve(iconLink).toString();
        } else {
          iconUrl = Uri.parse(url).resolve('/favicon.ico').toString();
        }
      }
    } catch (e) {
      print("[HomePage] Fetch error: $e");
    }

    if (!mounted) return;
    Navigator.pop(context);

    _showAddSiteDialog(initialName: title, initialUrl: url, initialIconUrl: iconUrl);
  }

  void _showAddSiteDialog({String? initialName, String? initialUrl, String? initialIconUrl}) {
    final nameController = TextEditingController(text: initialName);
    final urlController = TextEditingController(text: initialUrl);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("サイトを登録"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (initialIconUrl != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Image.network(initialIconUrl, width: 32, height: 32, errorBuilder: (_,__,___)=>const Icon(Icons.public)),
                ),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "サイト名", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(labelText: "URL", border: OutlineInputBorder()),
                keyboardType: TextInputType.url,
                maxLines: 3, minLines: 1,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("キャンセル")),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final url = urlController.text.trim();
              if (name.isNotEmpty && url.isNotEmpty) {
                _siteManager.addSite(name, url, iconUrl: initialIconUrl);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$name を追加しました")));
                if (_selectedIndex != 0) setState(() => _selectedIndex = 0);
              }
            },
            child: const Text("追加"),
          ),
        ],
      ),
    );
  }

  void _showSelectionModal(String url) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text("共有されたURLの操作", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.movie_creation, color: Colors.red, size: 32),
                title: const Text("動画として解析"),
                subtitle: const Text("動画リストに追加します"),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToCastPage(url);
                },
              ),
              ListTile(
                leading: const Icon(Icons.public, color: Colors.blue, size: 32),
                title: const Text("Webサイトとして登録"),
                subtitle: const Text("タイトルを取得して登録します"),
                onTap: () {
                  Navigator.pop(context);
                  if (_siteManager.isRegistered(url)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("このサイトは既に登録されています")));
                    return;
                  }
                  _fetchInfoAndShowAddDialog(url);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("PureTube Cast"),
        elevation: 0,
        actions: [
          if (_selectedIndex == 0)
            IconButton(
              icon: const Icon(Icons.add_link),
              tooltip: "サイトを追加",
              onPressed: () => _showAddSiteDialog(),
            ),
        ],
      ),
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          Container(
            color: Theme.of(context).primaryColor.withOpacity(0.05),
            child: Row(
              children: [
                _buildTabItem(0, Icons.public, "動画サイト"),
                _buildTabItem(1, Icons.folder_copy, "ライブラリ"),
                _buildTabItem(2, Icons.settings_remote, "接続"),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: const [
                WebVideoView(),
                LibraryView(),
                DeviceView(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label) {
    final bool isSelected = _selectedIndex == index;
    final Color color = isSelected ? Colors.red : Colors.grey;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isSelected ? Colors.red : Colors.transparent, width: 3))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color), const SizedBox(height: 4), Text(label, style: TextStyle(color: color, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 12))]),
        ),
      ),
    );
  }
}