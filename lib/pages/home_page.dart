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
import '../views/shared_url_modal.dart';
import '../views/remote_view.dart';
import 'help_page.dart';

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
          _handlePlaylistImport(url, listId);
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

  void _handlePlaylistImport(String url, String listId) async {
    final existingIndex = _playlistManager.currentPlaylists.indexWhere((p) => p.remoteSourceId == listId);

    if (existingIndex != -1) {
      final existingPlaylist = _playlistManager.currentPlaylists[existingIndex];
      final bool? update = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("プレイリストの取り込み"),
          content: Text("このプレイリストは既に「${existingPlaylist.name}」として登録されています。\n新しく追加された動画のみを取り込みますか？"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("新規作成"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("差分を取り込む"),
            ),
          ],
        ),
      );

      if (update == null) return;
      if (update) {
        _importPlaylist(url, targetPlaylistId: existingPlaylist.id);
        return;
      }
    }

    _importPlaylist(url);
  }

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

  Future<void> _importPlaylist(String url, {String? targetPlaylistId}) async {
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

    final newId = await _playlistManager.importFromYoutubePlaylist(url, targetPlaylistId: targetPlaylistId);

    if (!mounted) return;
    Navigator.pop(context);

    if (newId != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("プレイリストを取り込みました")));
      setState(() {
        _selectedIndex = 1;
      });
      _libraryKey.currentState?.openPlaylist(newId);
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

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    return Scaffold(
      appBar: AppBar(
        title: const Text("動画キャスト"),
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
              child: Center( // const を削除 (ClipRRectなどはconstにできない場合があるため)
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white, // アイコンの背景を白くすると映える場合が多いです
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(2), // 白枠をつける場合
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          'assets/icon.png',
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '動画キャスト for Kodi',
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
              title: const Text("モード設定"),
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
            const Divider(), // 区切り線を入れると見やすいです
            ExpansionTile(
              leading: const Icon(Icons.help_outline),
              title: const Text("ヘルプ & 使い方"),
              childrenPadding: const EdgeInsets.only(left: 20), // インデントをつけて階層を表現
              children: [
                _buildHelpLink(context, "1. 接続と準備", 'connection'),
                _buildHelpLink(context, "2. サイト管理", 'sites'),
                _buildHelpLink(context, "3. 再生・ライブラリ", 'playback'),
                _buildHelpLink(context, "4. 整理・活用", 'organize'),
                _buildHelpLink(context, "5. リンク更新", 'update'),
                _buildHelpLink(context, "6. リモコン", 'remote'),
                _buildHelpLink(context, "7. 困ったときは", 'troubleshoot'),
                _buildHelpLink(context, "8. アプリ設定", 'settings'),

                // 「すべて見る」オプション（一番上へ）
                ListTile(
                  title: const Text("マニュアルTOPへ", style: TextStyle(color: Colors.grey)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const HelpPage()),
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
          const RemoteView(),
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
          BottomNavigationBarItem(
            icon: Icon(Icons.gamepad),
            label: "リモコン",
          ),
        ],
        selectedItemColor: Colors.red,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  Widget _buildHelpLink(BuildContext context, String title, String sectionId) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: const Icon(Icons.article_outlined, size: 20, color: Colors.blueGrey),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => HelpPage(initialSection: sectionId)),
        );
      },
    );
  }
}