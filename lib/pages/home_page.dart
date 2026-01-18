import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:http/http.dart' as http; // 追加
import 'package:html/parser.dart' as parser; // 追加

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

  // 【改修】共有されたテキスト(URL)の処理分岐
  void _handleSharedText(String sharedText) {
    if (!mounted) return;

    // URL共有時にアクションを選択させる
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
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
                  Navigator.pop(context); // シートを閉じる
                  _navigateToCastPage(sharedText);
                },
              ),
              ListTile(
                leading: const Icon(Icons.public, color: Colors.blue, size: 32),
                title: const Text("Webサイトとして登録"),
                subtitle: const Text("タイトルを取得してブックマークします"),
                onTap: () {
                  Navigator.pop(context); // シートを閉じる
                  _fetchTitleAndShowAddDialog(sharedText);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // 1. 動画として解析（従来通りのフロー）
  void _navigateToCastPage(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CastPage(initialUrl: url),
      ),
    );
  }

  // 2. タイトルを取得してサイト登録ダイアログを表示
  Future<void> _fetchTitleAndShowAddDialog(String url) async {
    // ローディング表示
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    String title = "";
    try {
      // ページのHTMLを取得してタイトル抽出
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final document = parser.parse(response.body);
        title = document.querySelector('title')?.text ?? "";
      }
    } catch (e) {
      print("[HomePage] Title fetch error: $e");
    }

    if (!mounted) return;
    Navigator.pop(context); // ローディングを閉じる

    // 取得した情報でダイアログを開く
    _showAddSiteDialog(initialName: title, initialUrl: url);
  }

  // --- サイト追加ダイアログ ---
  // 【改修】初期値を受け取れるように変更
  void _showAddSiteDialog({String? initialName, String? initialUrl}) {
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
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: "サイト名 (例: Vimeo)",
                  border: OutlineInputBorder(),
                  hintText: "サイト名を入力",
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
                maxLines: 3, // URLが長い場合に見やすくする
                minLines: 1,
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

                // 登録完了のフィードバックと、タブ移動（もし別のタブにいたら）
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("$name を追加しました")),
                );

                // 動画サイトタブへ移動して追加を確認しやすくする
                if (_selectedIndex != 0) {
                  setState(() {
                    _selectedIndex = 0;
                  });
                }
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
          if (_selectedIndex == 0)
            IconButton(
              icon: const Icon(Icons.add_link),
              tooltip: "サイトを追加",
              onPressed: () => _showAddSiteDialog(), // 手動追加時は引数なし
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
                WebVideoView(),  // index 0
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