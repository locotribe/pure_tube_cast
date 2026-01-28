// lib/views/shared_url_modal.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import '../managers/site_manager.dart';
import '../managers/playlist_manager.dart';
import '../services/dlna_service.dart';
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

  // 重複チェック用状態変数
  LocalPlaylistItem? _existingItem;
  String? _existingPlaylistId;
  bool _isUpdateMode = false;

  // 比較用の「骨格」文字列を生成するヘルパー
  String _generateSkeleton(String input) {
    String s = input.trim().toLowerCase();

    // 全角英数を半角へ (簡易版)
    s = s
        .replaceAll('０', '0')
        .replaceAll('１', '1')
        .replaceAll('Ｉ', 'I')
        .replaceAll('ｌ', 'l')
        .replaceAll('Ｏ', 'O')
        .replaceAll('ｏ', 'o');

    // 紛らわしい文字の統一 (l, I, 1, | -> 1 / O, 0 -> 0)
    s = s.replaceAll(RegExp(r'[lI1|]'), '1');
    s = s.replaceAll(RegExp(r'[O0]'), '0');

    // 空白の除去
    s = s.replaceAll(RegExp(r'\s'), '');

    return s;
  }

  DuplicateStatus _checkDuplicateLevel(String input) {
    final target = input.trim();
    if (target.isEmpty) return DuplicateStatus.none;

    // 1. 完全一致チェック
    final normalizedTarget = target.toLowerCase();
    for (var playlist in _playlistManager.currentPlaylists) {
      if (playlist.name.trim().toLowerCase() == normalizedTarget) {
        return DuplicateStatus.exactMatch;
      }
    }

    // 2. 視覚的類似チェック
    final skeletonTarget = _generateSkeleton(target);
    for (var playlist in _playlistManager.currentPlaylists) {
      if (_generateSkeleton(playlist.name) == skeletonTarget) {
        return DuplicateStatus.visualMatch;
      }
    }

    return DuplicateStatus.none;
  }

  void _showCreatePlaylistDialog() {
    final controller = TextEditingController();
    // 重複チェックの結果を管理
    final ValueNotifier<DuplicateStatus> statusNotifier =
    ValueNotifier(DuplicateStatus.none);

    // テキスト変更時に重複チェックを実行
    controller.addListener(() {
      statusNotifier.value = _checkDuplicateLevel(controller.text);
    });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("新規フォルダ作成"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: "フォルダ名",
                hintText: "例: 後で見る",
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            // エラー/警告メッセージ表示 (ステータス変化時のみ更新)
            ValueListenableBuilder<DuplicateStatus>(
              valueListenable: statusNotifier,
              builder: (context, status, child) {
                if (status == DuplicateStatus.exactMatch) {
                  return const Text(
                    "この名前のフォルダは既に存在します",
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  );
                } else if (status == DuplicateStatus.visualMatch) {
                  return const Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange, size: 16),
                      SizedBox(width: 4),
                      Expanded(
                          child: Text(
                            "紛らわしい名前のフォルダが存在します",
                            style: TextStyle(color: Colors.orange, fontSize: 12),
                          )),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("キャンセル"),
          ),
          // 【修正】AnimatedBuilderを使って、文字入力のたびにボタン状態を再評価する
          AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final text = controller.text.trim();
              // ボタン有効化の条件: 文字があり、かつ 完全一致の重複がないこと
              final bool isValid =
                  text.isNotEmpty && statusNotifier.value != DuplicateStatus.exactMatch;

              return ElevatedButton(
                onPressed: isValid
                    ? () {
                  final newName = controller.text.trim();
                  _playlistManager.createPlaylist(newName);

                  // 作成したプレイリストを選択状態にする
                  if (_playlistManager.currentPlaylists.isNotEmpty) {
                    final newId =
                        _playlistManager.currentPlaylists.last.id;
                    setState(() {
                      _selectedPlaylistId = newId;
                    });
                  }

                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(widget.parentContext).showSnackBar(
                    SnackBar(content: Text("「$newName」を作成しました")),
                  );
                }
                    : null, // 条件を満たさない場合は無効化
                child: const Text("作成"),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchPageInfo(); // 開いた瞬間に裏でタイトル取得を開始

    // プレイリストの初期選択（メインリストがあればそれ、なければ先頭）
    if (_playlistManager.currentPlaylists.isNotEmpty) {
      _selectedPlaylistId = _playlistManager.currentPlaylists.first.id;
    }

    // 描画後に重複チェックを実行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDuplicate();
    });
  }

  @override
  void dispose() {
    _manualUrlController.dispose();
    super.dispose();
  }

  /// 重複チェックとダイアログ表示
  void _checkDuplicate() {
    final match = _playlistManager.findItemByOriginalUrl(widget.url);
    if (match != null) {
      setState(() {
        _existingItem = match.item;
        _existingPlaylistId = match.playlist.id;
      });
      _showDuplicateDialog();
    }
  }

  /// 重複警告ダイアログ
  void _showDuplicateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("登録済みです"),
        content: Text(
            "この動画は既に登録されています。\n\nタイトル:\n${_existingItem?.title ?? '(不明)'}\n\nリンクの有効期限が切れている場合は「リンクを更新」を選択してください。"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // ダイアログを閉じる
              Navigator.pop(context); // モーダルを閉じてブラウザ(元画面)へ戻る
            },
            child: const Text("閉じる"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              if (_existingPlaylistId != null) {
                widget.onCastFinished(_existingPlaylistId!); // アプリ内の該当リストへ移動
              }
            },
            child: const Text("アプリで確認"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _isUpdateMode = true;
                // 更新モード時は既存のプレイリストを強制選択
                _selectedPlaylistId = _existingPlaylistId;
                // タイトルも既存のものを使う（必要であれば）
                if (_existingItem != null) {
                  _pageTitle = _existingItem!.title;
                }
              });
            },
            child: const Text("リンクを更新"),
          ),
        ],
      ),
    );
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

        // 1. まずOGP画像 (サムネイル) を探す
        var iconLink = document.querySelector('meta[property="og:image"]')?.attributes['content'];

        // 2. OGPがない場合は、従来のFaviconを探す (フォールバック)
        if (iconLink == null || iconLink.isEmpty) {
          iconLink = document.querySelector('link[rel="icon"]')?.attributes['href'];
          iconLink ??= document.querySelector('link[rel="shortcut icon"]')?.attributes['href'];
        }

        if (mounted) {
          setState(() {
            // 更新モードでなければタイトルを更新（更新モードなら既存タイトル維持）
            if (!_isUpdateMode && title.isNotEmpty) _pageTitle = title;

            if (iconLink != null && iconLink.isNotEmpty) {
              _pageIconUrl = Uri.parse(widget.url).resolve(iconLink!).toString();
            } else {
              _pageIconUrl = Uri.parse(widget.url).resolve('/favicon.ico').toString();
            }
            _isFetchingInfo = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (!_isUpdateMode) _pageTitle = "ページ情報の取得に失敗";
          _isFetchingInfo = false;
        });
      }
    }
  }

  /// 【修正】URLパラメータから有効期限を抽出するヘルパー (正規表現版)
  /// 正規表現を使うことで、URLの構造が複雑でも確実にパラメータ値を拾います
  DateTime? _parseExpiry(String url) {
    try {
      // 正規表現パターン: Expires=数字, expires=数字, e=数字, ttl=数字 などにマッチ
      // \d+ は数字の連続、caseSensitive: false で大文字小文字を区別しない
      final regExp = RegExp(r'(?:Expires|expires|expire|e|deadline|ttl)=(\d+)', caseSensitive: false);
      final match = regExp.firstMatch(url);

      if (match != null) {
        final val = match.group(1); // 数字部分を取得
        if (val != null) {
          final numVal = int.tryParse(val);
          if (numVal != null) {
            // Unix Timestamp (秒) か 相対時間 (秒) かを判定
            // 2000年1月1日 (946684800) より小さければ「相対時間（残り秒数）」とみなす
            if (numVal < 946684800) {
              return DateTime.now().add(Duration(seconds: numVal));
            } else {
              // Unix Timestamp
              return DateTime.fromMillisecondsSinceEpoch(numVal * 1000);
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPadding),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
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
                            _isUpdateMode ? "【リンク更新モード】 $_pageTitle" : (_isFetchingInfo ? "ページ情報を取得中..." : _pageTitle),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: _isUpdateMode ? Colors.orange : null,
                            ),
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

              // 更新モードでない場合のみ表示
              if (!_isUpdateMode) ...[
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
              ],

              // 手動登録 / 更新 エリア
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isUpdateMode ? "新しい動画URLを貼り付けて更新" : "抽出したURLを手動登録 (解析スキップ)",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _isUpdateMode ? Colors.red : Colors.orange,
                      ),
                    ),
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
                            // 貼り付け処理（省略）
                          },
                          tooltip: "貼り付け",
                        ),
                      ),
                      maxLines: 2,
                      minLines: 1,
                    ),
                    const SizedBox(height: 12),

                    // プレイリスト選択（更新モード時は無効化または固定表示）

                    // 【変更】Rowで囲んで右側に新規作成ボタンを追加
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
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
                            onChanged: _isUpdateMode ? null : (val) { // 更新モード時は変更不可
                              setState(() {
                                _selectedPlaylistId = val;
                              });
                            },
                          ),
                        ),

                        // 更新モードでない場合のみ新規作成ボタンを表示
                        if (!_isUpdateMode) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _showCreatePlaylistDialog, // 追加したメソッドを呼び出す
                            icon: const Icon(Icons.create_new_folder),
                            tooltip: "新規フォルダ作成",
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 16),

                    // アクションボタン
                    if (_isUpdateMode)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text("リンクを更新する"),
                          onPressed: _handleManualUpdate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      )
                    else
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

  /// 更新モード用ハンドラ
  void _handleManualUpdate() {
    final streamUrl = _manualUrlController.text.trim();
    if (streamUrl.isEmpty) {
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        const SnackBar(content: Text("動画URLを入力してください")),
      );
      return;
    }

    if (_existingItem == null || _existingPlaylistId == null) return;

    // 有効期限を解析
    final expiry = _parseExpiry(streamUrl);

    // マネージャー経由で更新
    _playlistManager.updateItemLink(
      playlistId: _existingPlaylistId!,
      itemId: _existingItem!.id,
      newStreamUrl: streamUrl,
      newExpirationDate: expiry,
    );

    Navigator.pop(context); // モーダルを閉じる

    ScaffoldMessenger.of(widget.parentContext).showSnackBar(
      SnackBar(content: Text("リンクを更新しました ${expiry != null ? '(期限あり)' : ''}")),
    );

    // 更新したリストへ遷移
    widget.onCastFinished(_existingPlaylistId!);
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

    String targetId = _selectedPlaylistId ?? "";
    if (targetId.isEmpty && _playlistManager.currentPlaylists.isNotEmpty) {
      targetId = _playlistManager.currentPlaylists.first.id;
    }

    // 有効期限解析 (新規追加時も有効)
    final expiry = _parseExpiry(streamUrl); // 追加

    // 1. リストに追加
    _playlistManager.addManualItem(
      targetPlaylistId: targetId,
      title: _pageTitle.isNotEmpty ? _pageTitle : "手動追加アイテム",
      originalUrl: widget.url,
      streamUrl: streamUrl,
      thumbnailUrl: _pageIconUrl,
      expirationDate: expiry, // 有効期限を渡す
    );

    Navigator.pop(context);

    if (playNow) {
      final device = _dlnaService.currentDevice;
      if (device != null) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          SnackBar(content: Text("${device.name} で再生を開始します")),
        );
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
// 判定結果を返すEnum
enum DuplicateStatus {
  none,        // 問題なし
  exactMatch,  // 完全一致（作成不可）
  visualMatch, // 視覚的に酷似（警告表示）
}