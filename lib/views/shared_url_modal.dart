import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import '../managers/site_manager.dart';
import '../managers/playlist_manager.dart'; // 追加
import '../services/dlna_service.dart'; // 追加
import '../pages/cast_page.dart';

/// HomePageから呼び出すエントリポイント
void showSharedUrlModal({
  required BuildContext context,
  required String url,
  required Function(String playlistId) onCastFinished,
  required VoidCallback onSiteAdded,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true, // キーボード表示に対応するためtrue
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => _SharedUrlModalContent(
      url: url,
      onCastFinished: onCastFinished,
      onSiteAdded: onSiteAdded,
      parentContext: context,
    ),
  );
}

class _SharedUrlModalContent extends StatefulWidget {
  final String url;
  final Function(String playlistId) onCastFinished;
  final VoidCallback onSiteAdded;
  final BuildContext parentContext;

  const _SharedUrlModalContent({
    required this.url,
    required this.onCastFinished,
    required this.onSiteAdded,
    required this.parentContext,
  });

  @override
  State<_SharedUrlModalContent> createState() => _SharedUrlModalContentState();
}

class _SharedUrlModalContentState extends State<_SharedUrlModalContent> {
  final SiteManager _siteManager = SiteManager();
  final PlaylistManager _playlistManager = PlaylistManager();
  final DlnaService _dlnaService = DlnaService();

  // 手動入力用コントローラー
  final TextEditingController _manualUrlController = TextEditingController();

  // 選択中のプレイリストID
  String? _selectedPlaylistId;

  // サイト情報（タイトルなど）取得用
  String _pageTitle = "読み込み中...";
  String? _pageIconUrl;
  bool _isFetchingInfo = true;

  @override
  void initState() {
    super.initState();
    _fetchPageInfo(); // 開いた瞬間に裏でタイトル取得を開始

    // プレイリストの初期選択（メインリストがあればそれ、なければ先頭）
    if (_playlistManager.currentPlaylists.isNotEmpty) {
      _selectedPlaylistId = _playlistManager.currentPlaylists.first.id;
    }
  }

  @override
  void dispose() {
    _manualUrlController.dispose();
    super.dispose();
  }

  /// 共有されたURL（Webページ）のタイトル等を取得
  Future<void> _fetchPageInfo() async {
    try {
      final response = await http
          .get(Uri.parse(widget.url))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final document = parser.parse(response.body);
        final title = document.querySelector('title')?.text?.trim() ?? "";

        var iconLink = document.querySelector('link[rel="icon"]')?.attributes['href'];
        iconLink ??= document.querySelector('link[rel="shortcut icon"]')?.attributes['href'];

        if (mounted) {
          setState(() {
            if (title.isNotEmpty) _pageTitle = title;
            if (iconLink != null && iconLink.isNotEmpty) {
              _pageIconUrl = Uri.parse(widget.url).resolve(iconLink).toString();
            } else {
              // faviconフォールバック
              _pageIconUrl = Uri.parse(widget.url).resolve('/favicon.ico').toString();
            }
            _isFetchingInfo = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pageTitle = "ページ情報の取得に失敗";
          _isFetchingInfo = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // キーボードで隠れないようにパディング調整
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPadding),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85, // 画面の85%まで
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ヘッダー
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    if (_pageIconUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Image.network(_pageIconUrl!, width: 24, height: 24, errorBuilder: (_,__,___)=>const Icon(Icons.public, size: 24)),
                      )
                    else
                      const Icon(Icons.link, size: 24, color: Colors.grey),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isFetchingInfo ? "ページ情報を取得中..." : _pageTitle,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            widget.url,
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // 1. 通常のアクション（自動解析・サイト登録）
              ListTile(
                leading: const Icon(Icons.movie_creation, color: Colors.red),
                title: const Text("動画として自動解析"),
                subtitle: const Text("YouTubeや一般的な動画サイト"),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToCastPage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.public, color: Colors.blue),
                title: const Text("Webサイトとして登録"),
                onTap: () {
                  Navigator.pop(context);
                  _handleSiteRegistration();
                },
              ),

              const Divider(),

              // 2. 手動登録エリア（新機能）
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("抽出したURLを手動登録 (解析スキップ)",
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                    const SizedBox(height: 8),
                    const Text(
                      "拡張機能などで取得した .m3u8 / .mp4 のURLを貼り付けてください。",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),

                    // URL入力欄
                    TextField(
                      controller: _manualUrlController,
                      decoration: InputDecoration(
                        labelText: "動画URL (m3u8, mp4...)",
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.paste),
                          onPressed: () async {
                            // クリップボードから貼り付け等はOS機能で可能だが、ボタンとしても用意可
                            // ここではシンプルに実装省略（TextFieldの標準機能で貼り付け可能）
                          },
                          tooltip: "貼り付け",
                        ),
                      ),
                      maxLines: 2,
                      minLines: 1,
                    ),
                    const SizedBox(height: 12),

                    // プレイリスト選択
                    DropdownButtonFormField<String>(
                      value: _selectedPlaylistId,
                      decoration: const InputDecoration(
                        labelText: "保存先フォルダ",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: _playlistManager.currentPlaylists.map((p) {
                        return DropdownMenuItem(
                          value: p.id,
                          child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedPlaylistId = val;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    // アクションボタン
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text("リストに追加"),
                            onPressed: () => _handleManualAdd(playNow: false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.play_arrow),
                            label: const Text("追加して再生"),
                            onPressed: () => _handleManualAdd(playNow: true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// 手動追加処理
  void _handleManualAdd({required bool playNow}) async {
    final streamUrl = _manualUrlController.text.trim();
    if (streamUrl.isEmpty) {
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        const SnackBar(content: Text("動画URLを入力してください")),
      );
      return;
    }

    // 保存先ID（未選択なら新規作成するか既存の先頭を使うなどの処理はManager側で吸収済みだが、IDは必須）
    String targetId = _selectedPlaylistId ?? "";
    if (targetId.isEmpty && _playlistManager.currentPlaylists.isNotEmpty) {
      targetId = _playlistManager.currentPlaylists.first.id;
    }

    // 1. リストに追加（バイパス処理）
    _playlistManager.addManualItem(
      targetPlaylistId: targetId,
      title: _pageTitle.isNotEmpty ? _pageTitle : "手動追加アイテム",
      originalUrl: widget.url, // 共有元のページURL
      streamUrl: streamUrl,    // 手動入力された動画URL
      thumbnailUrl: _pageIconUrl, // ページのアイコンを仮サムネとして使用
    );

    Navigator.pop(context); // モーダルを閉じる

    // 2. 再生リクエスト（playNowの場合）
    if (playNow) {
      final device = _dlnaService.currentDevice;
      if (device != null) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          SnackBar(content: Text("${device.name} で再生を開始します")),
        );
        // Kodiへ送信
        await _dlnaService.playNow(
          device,
          streamUrl,
          _pageTitle,
          _pageIconUrl,
        );
      } else {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          const SnackBar(content: Text("リストに追加しました（デバイス未接続）")),
        );
      }
    } else {
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        const SnackBar(content: Text("リストに追加しました")),
      );
    }

    // コールバックでライブラリ画面へ遷移させる
    widget.onCastFinished(targetId);
  }

  // --- 以下、既存の自動解析用ロジック ---

  void _navigateToCastPage() async {
    final result = await Navigator.push(
      widget.parentContext,
      MaterialPageRoute(builder: (context) => CastPage(initialUrl: widget.url)),
    );

    if (result != null && result is String) {
      widget.onCastFinished(result);
    }
  }

  void _handleSiteRegistration() {
    if (_siteManager.isRegistered(widget.url)) {
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        const SnackBar(content: Text("このサイトは既に登録されています")),
      );
      return;
    }
    // 情報は取得済みなので、ダイアログを即表示
    _showAddSiteDialog(
        initialName: _pageTitle, initialUrl: widget.url, initialIconUrl: _pageIconUrl);
  }

  void _showAddSiteDialog(
      {String? initialName, String? initialUrl, String? initialIconUrl}) {
    final nameController = TextEditingController(text: initialName);
    final urlController = TextEditingController(text: initialUrl);

    showDialog(
      context: widget.parentContext,
      builder: (context) => AlertDialog(
        title: const Text("サイトを登録"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (initialIconUrl != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Image.network(initialIconUrl,
                      width: 32,
                      height: 32,
                      errorBuilder: (_, __, ___) => const Icon(Icons.public)),
                ),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                    labelText: "サイト名", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                    labelText: "URL", border: OutlineInputBorder()),
                keyboardType: TextInputType.url,
                maxLines: 3,
                minLines: 1,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("キャンセル")),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final url = urlController.text.trim();
              if (name.isNotEmpty && url.isNotEmpty) {
                _siteManager.addSite(name, url, iconUrl: initialIconUrl);
                Navigator.pop(context);
                ScaffoldMessenger.of(widget.parentContext).showSnackBar(
                    SnackBar(content: Text("$name を追加しました")));
                widget.onSiteAdded();
              }
            },
            child: const Text("追加"),
          ),
        ],
      ),
    );
  }
}