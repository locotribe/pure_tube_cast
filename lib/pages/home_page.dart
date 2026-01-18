import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

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
                  _navigateToCastPage(sharedText);
                },
              ),
              ListTile(
                leading: const Icon(Icons.public, color: Colors.blue, size: 32),
                title: const Text("Webサイトとして登録"),
                subtitle: const Text("タイトルとアイコンを取得して登録します"),
                onTap: () {
                  Navigator.pop(context);
                  _fetchInfoAndShowAddDialog(sharedText); // 【変更】メソッド名変更
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _navigateToCastPage(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CastPage(initialUrl: url)),
    );
  }

  // 【改修】タイトルとアイコンを取得
  Future<void> _fetchInfoAndShowAddDialog(String url) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    String title = "";
    String? iconUrl;

    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final document = parser.parse(response.body);
        title = document.querySelector('title')?.text ?? "";

        // アイコン(favicon)の抽出
        // 1. <link rel="icon">
        var iconLink = document.querySelector('link[rel="icon"]')?.attributes['href'];
        // 2. <link rel="shortcut icon">
        iconLink ??= document.querySelector('link[rel="shortcut icon"]')?.attributes['href'];
        // 3. <link rel="apple-touch-icon"> (スマホ向け)
        iconLink ??= document.querySelector('link[rel="apple-touch-icon"]')?.attributes['href'];

        if (iconLink != null && iconLink.isNotEmpty) {
          // 相対パスを絶対パスに変換
          iconUrl = uri.resolve(iconLink).toString();
        } else {
          // 見つからない場合はルートのfavicon.icoを試す
          iconUrl = uri.resolve('/favicon.ico').toString();
        }
      }
    } catch (e) {
      print("[HomePage] Fetch error: $e");
    }

    if (!mounted) return;
    Navigator.pop(context); // ローディングを閉じる

    // ダイアログ表示
    _showAddSiteDialog(initialName: title, initialUrl: url, initialIconUrl: iconUrl);
  }

  // 【改修】iconUrlを受け取り、保存するように変更
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
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Image.network(initialIconUrl, width: 48, height: 48, errorBuilder: (_,__,___) => const SizedBox()),
                ),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "サイト名", border: OutlineInputBorder(), hintText: "サイト名を入力"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(labelText: "URL", border: OutlineInputBorder()),
                keyboardType: TextInputType.url,
                maxLines: 3,
                minLines: 1,
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
                // iconUrlも渡す
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