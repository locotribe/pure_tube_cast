import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../views/device_view.dart';
import '../views/web_video_view.dart';
import '../views/library_view.dart';
import '../managers/site_manager.dart';
import 'cast_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // タブの選択インデックス (0:動画サイト, 1:ライブラリ, 2:接続)
  int _selectedIndex = 0;

  StreamSubscription? _intentStreamSubscription;
  final SiteManager _siteManager = SiteManager();

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

  // --- 共有受け取りロジック ---
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

  void _handleSharedText(String sharedText) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CastPage(initialUrl: sharedText),
      ),
    );
  }

  // --- サイト追加ダイアログ ---
  void _showAddSiteDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("サイトを登録"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: "サイト名 (例: Vimeo)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: "URL (例: https://...)",
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("キャンセル"),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final url = urlController.text.trim();
              if (name.isNotEmpty && url.isNotEmpty) {
                _siteManager.addSite(name, url);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("$name を追加しました")),
                );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("PureTube Cast"),
        elevation: 0,
        actions: [
          // 【変更】一番左(index 0)が動画サイトになったので条件を変更
          if (_selectedIndex == 0)
            IconButton(
              icon: const Icon(Icons.add_link),
              tooltip: "サイトを追加",
              onPressed: _showAddSiteDialog,
            ),
        ],
      ),
      resizeToAvoidBottomInset: false,

      body: Column(
        children: [
          // --- 上部カスタムタブバー ---
          Container(
            color: Theme.of(context).primaryColor.withOpacity(0.05),
            child: Row(
              children: [
                // 【変更】並び順を入れ替え: Web(0) -> Library(1) -> Connect(2)
                _buildTabItem(0, Icons.public, "動画サイト"),
                _buildTabItem(1, Icons.folder_copy, "ライブラリ"),
                _buildTabItem(2, Icons.settings_remote, "接続"),
              ],
            ),
          ),

          // --- メインコンテンツ ---
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: const [
                // 【変更】並び順を入れ替え
                WebVideoView(),  // index 0 (起動直後はここ)
                LibraryView(),   // index 1
                DeviceView(),    // index 2
              ],
            ),
          ),
        ],
      ),
    );
  }

  // タブボタンの構築
  Widget _buildTabItem(int index, IconData icon, String label) {
    final bool isSelected = _selectedIndex == index;
    final Color color = isSelected ? Colors.red : Colors.grey;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedIndex = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? Colors.red : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}