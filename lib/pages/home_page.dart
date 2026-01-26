// lib/pages/home_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

import '../views/device_view.dart';
import '../views/web_video_view.dart';
import '../views/library_view.dart';
import '../managers/site_manager.dart';
import '../managers/playlist_manager.dart';
import 'cast_page.dart';
import '../managers/theme_manager.dart';
// 【追加】作成したモジュールをインポート
import '../views/shared_url_modal.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  StreamSubscription? _intentStreamSubscription;
  final SiteManager _siteManager = SiteManager();
  final PlaylistManager _playlistManager = PlaylistManager();

  final GlobalKey<LibraryViewState> _libraryKey = GlobalKey();

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

  void _handleSharedText(String url) {
    if (!mounted) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    // 1. YouTubeの判定
    if (uri.host.contains('youtube.com') || uri.host.contains('youtu.be')) {

      // A. プレイリスト一括取込判定
      if (uri.queryParameters.containsKey('list')) {
        final listId = uri.queryParameters['list']!;
        if (!listId.startsWith('RD')) {
          _importPlaylist(url);
          return;
        }
      }

      // B. チャンネル・トップ -> サイト登録
      if (uri.path.startsWith('/@') || uri.path.startsWith('/channel') || uri.path.isEmpty || uri.path == '/') {
        if (_siteManager.isRegistered(url)) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("このサイトは既に登録されています")));
          return;
        }
        _fetchInfoAndShowAddDialog(url);
        return;
      }

      // C. 動画 -> 動画解析
      bool isVideo = false;
      if (uri.queryParameters.containsKey('v')) isVideo = true;
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) isVideo = true;
      if (uri.path.startsWith('/shorts/')) isVideo = true;

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

    // 4. 判定不能 -> 選択メニュー (モジュールへ委譲)
    // 【修正】_showSelectionModal(url) を削除し、showSharedUrlModal に置き換え
    showSharedUrlModal(
      context: context,
      url: url,
      onCastFinished: (playlistId) {
        if (!mounted) return;
        setState(() {
          _selectedIndex = 1; // ライブラリタブへ切り替え
        });
        _libraryKey.currentState?.openPlaylist(playlistId);
      },
      onSiteAdded: () {
        if (!mounted) return;
        if (_selectedIndex != 0) setState(() => _selectedIndex = 0);
      },
    );
  }

  // --- 各アクション ---

  void _navigateToCastPage(String url) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CastPage(initialUrl: url)),
    );

    if (result != null && result is String) {
      if (!mounted) return;
      setState(() {
        _selectedIndex = 1;
      });
      _libraryKey.currentState?.openPlaylist(result);
    }
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
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("プレイリストの取得に失敗しました")));
    }
  }

  // WebVideoViewや直接共有で使用するため残す
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

  // WebVideoViewで使用するため残す
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

  // 【削除】_showSelectionModal は shared_url_modal.dart に移行したため削除

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    return Scaffold(
      appBar: AppBar(
        title: const Text("PureTube Cast"),
        elevation: 0,
        actions: [],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cast_connected, color: Colors.white, size: 48),
                    SizedBox(height: 10),
                    Text(
                      'PureTube Cast',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ExpansionTile(
              leading: const Icon(Icons.settings),
              title: const Text("設定"),
              initiallyExpanded: false,
              children: [
                StreamBuilder<ThemeMode>(
                  stream: themeManager.themeStream,
                  initialData: themeManager.currentThemeMode,
                  builder: (context, snapshot) {
                    final currentMode = snapshot.data ?? ThemeMode.system;
                    return Column(
                      children: [
                        RadioListTile<ThemeMode>(
                          title: const Text("ライトモード"),
                          secondary: const Icon(Icons.wb_sunny),
                          value: ThemeMode.light,
                          groupValue: currentMode,
                          onChanged: (value) => themeManager.setThemeMode(value!),
                        ),
                        RadioListTile<ThemeMode>(
                          title: const Text("ダークモード"),
                          secondary: const Icon(Icons.nightlight_round),
                          value: ThemeMode.dark,
                          groupValue: currentMode,
                          onChanged: (value) => themeManager.setThemeMode(value!),
                        ),
                        RadioListTile<ThemeMode>(
                          title: const Text("システムのデフォルト"),
                          secondary: const Icon(Icons.settings_brightness),
                          value: ThemeMode.system,
                          groupValue: currentMode,
                          onChanged: (value) => themeManager.setThemeMode(value!),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          WebVideoView(onAddSite: () => _showAddSiteDialog()),
          LibraryView(key: _libraryKey),
          const DeviceView(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.public),
            label: "動画サイト",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_copy),
            label: "ライブラリ",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_remote),
            label: "接続",
          ),
        ],
        selectedItemColor: Colors.red,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}