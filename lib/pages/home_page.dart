import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../views/device_view.dart';
import '../views/web_video_view.dart';
import '../views/library_view.dart';
import '../pages/playlist_page.dart';
import 'cast_page.dart';
import 'settings_page.dart';
import '../logics/home_logic.dart'; // ロジッククラスをインポート

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  StreamSubscription? _intentStreamSubscription;
  final HomeLogic _logic = HomeLogic(); // ロジッククラスのインスタンス

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

  // ロジッククラスを使用して判定を行うように修正
  void _handleSharedText(String url) {
    if (!mounted) return;

    final action = _logic.determineAction(url);

    switch (action) {
      case UrlAction.importPlaylist:
        _importPlaylist(url);
        break;

      case UrlAction.addSite:
        if (_logic.isSiteRegistered(url)) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("このサイトは既に登録されています")));
        } else {
          _fetchInfoAndShowAddDialog(url);
        }
        break;

      case UrlAction.castVideo:
        _navigateToCastPage(url);
        break;

      case UrlAction.unknown:
        _showSelectionModal(url);
        break;
    }
  }

  // --- 各アクション (UI処理) ---

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

    // ロジッククラスに処理を委譲
    final newId = await _logic.importPlaylist(url);

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

    // ロジッククラスに処理を委譲
    final info = await _logic.fetchSiteInfo(url);

    if (!mounted) return;
    Navigator.pop(context);

    _showAddSiteDialog(
        initialName: info['title'],
        initialUrl: url,
        initialIconUrl: info['iconUrl']
    );
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
                // ロジッククラスに処理を委譲
                _logic.addSite(name, url, iconUrl: initialIconUrl);
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
                  if (_logic.isSiteRegistered(url)) {
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
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: "設定",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
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
              children: [
                // 0: 動画サイト (常に保持)
                const WebVideoView(),
                // 1: ライブラリ (常に保持)
                const LibraryView(),
                // 2: 接続 (選択時のみビルドすることで、タブを押した時に検索開始、離れたら停止させる)
                _selectedIndex == 2 ? const DeviceView() : const SizedBox(),
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