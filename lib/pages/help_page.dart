import 'package:flutter/material.dart';

class HelpPage extends StatefulWidget {
  final String? initialSection;

  const HelpPage({super.key, this.initialSection});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  // ジャンプ先のキー一覧
  final Map<String, GlobalKey> _sectionKeys = {
    'connection': GlobalKey(),
    'sites': GlobalKey(),
    'playback': GlobalKey(),
    'organize': GlobalKey(),
    'update': GlobalKey(),
    'remote': GlobalKey(),
    'troubleshoot': GlobalKey(), // 新規追加
    'settings': GlobalKey(),     // 新規追加
  };

  @override
  void initState() {
    super.initState();
    // 画面描画後に指定セクションへスクロール
    if (widget.initialSection != null && _sectionKeys.containsKey(widget.initialSection)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final key = _sectionKeys[widget.initialSection]!;
        if (key.currentContext != null) {
          Scrollable.ensureVisible(
            key.currentContext!,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
            alignment: 0.0,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ヘルプ & 使い方"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),

            // 1. 接続と準備
            _buildSectionTitle("1. 接続と準備", key: _sectionKeys['connection']),
            _buildStepItem(
              "1",
              "初期設定",
              "Fire TV等の設定で「ADBデバッグ」をONにし、Kodiアプリを起動しておきます。",
            ),
            _buildStepItem(
              "2",
              "デバイス接続",
              "「接続」タブでデバイスを選びます。リストにない場合は右上の「+」からIPを手動入力してください。",
            ),
            _buildIconExplanation(Icons.edit, "名前の変更",
                "デバイスカードの鉛筆アイコンを押すと、デバイスに好きな名前（例：リビング）を付けられます。"),
            _buildIconExplanation(Icons.rocket_launch, "Kodi起動ボタン",
                "ロケットアイコンを押すと、スマホから遠隔でテレビ側のKodiアプリを起動・前面表示できます（ADB接続時）。"),

            const SizedBox(height: 24),

            // 2. 動画サイトの管理
            _buildSectionTitle("2. 動画サイトの管理", key: _sectionKeys['sites']),
            _buildStepItem(
              "A",
              "サイトの追加",
              "「動画サイト」タブの一番最後にある「＋サイトを追加」パネルをタップするか、ブラウザからサイトのURLを本アプリに共有することで、よく見るサイトをホーム画面に登録できます。",
            ),
            _buildStepItem(
              "B",
              "編集・削除",
              "登録したサイトカードの右上にある「編集（鉛筆）」アイコンをタップすると、名前の変更や削除が行えます。（YouTubeは削除できません）",
            ),

            const SizedBox(height: 24),

            // 3. 動画の再生・ライブラリ
            _buildSectionTitle("3. 動画の再生・ライブラリ", key: _sectionKeys['playback']),
            _buildStepItem(
              "!",
              "基本のキャスト",
              "YouTubeアプリやブラウザの「共有」メニューから「PureTube Cast」を選びます。「今すぐ再生」で即座にテレビへ、「リストに追加」でライブラリに保存されます。",
            ),
            _buildStepItem(
              "★",
              "プレイリスト一括取込",
              "YouTubeアプリで「動画」ではなく「プレイリスト」を共有すると、中身の動画をまとめてライブラリに取り込むことができます。",
            ),

            const SizedBox(height: 8),
            const Text("ライブラリのアイコン・ステータス意味", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildStatusRow(Icons.check_circle, Colors.green, "送信済み", "Kodiへの送信が完了したアイテムです。"),
            _buildStatusRow(Icons.refresh, Colors.orange, "解析中", "動画の実際のURLを取得しています。"),
            _buildStatusRow(Icons.error, Colors.red, "エラー", "URLの解析に失敗しました。リンク切れの可能性があります。"),
            _buildStatusRow(Icons.warning, Colors.red, "期限切れ", "動画リンクの有効期限が切れています。更新が必要です。"),

            const SizedBox(height: 24),

            // 4. ライブラリの整理・活用
            _buildSectionTitle("4. ライブラリの整理・活用", key: _sectionKeys['organize']),
            _buildIconExplanation(Icons.create_new_folder, "フォルダ作成",
                "右下のボタンで新しいフォルダ（プレイリスト）を作成できます。"),
            _buildIconExplanation(Icons.drag_handle, "並び替え",
                "フォルダや動画アイテムを「長押し」してドラッグすることで、好きな順番に並び替えられます。"),
            _buildIconExplanation(Icons.swipe, "スワイプ削除",
                "動画アイテムを横にスワイプすると、素早くリストから削除できます。"),
            _buildIconExplanation(Icons.drive_file_move_outline, "動画の移動",
                "動画をタップして詳細を開き、「移動」ボタンを押すと、別のフォルダへ動画を引っ越しできます。"),
            _buildIconExplanation(Icons.checklist, "一括操作",
                "フォルダ内のメニュー（右上の︙）から「選択して削除」を選ぶと、複数の動画をまとめて削除できます。"),

            const SizedBox(height: 24),

            // 5. リンクの更新
            _buildSectionTitle("5. リンクの更新（期限切れ対策）", key: _sectionKeys['update']),
            _buildStepItem(
              "!",
              "更新手順",
              "1. ライブラリで期限切れの動画をタップします。\n2. 「この動画をブラウザで開く」をタップします。\n3. ブラウザでページが開いたら、再度「共有」から本アプリを選びます。\n4. 「リンクを更新」ボタンが表示されるのでタップします。",
            ),

            const SizedBox(height: 24),

            // 6. リモコン操作
            _buildSectionTitle("6. リモコン操作", key: _sectionKeys['remote']),
            _buildIconExplanation(Icons.fast_forward, "倍速再生",
                "押すたびに速度が上がります（2x, 4x...）。「標準(1.0x)」ボタンで戻ります。"),
            _buildIconExplanation(Icons.replay_10, "10秒スキップ",
                "動画を10秒巻き戻し/早送りします。"),
            _buildIconExplanation(Icons.volume_up, "音量調整",
                "スライダーでKodi側の音量を調整できます。"),
            _buildIconExplanation(Icons.link_off, "接続解除",
                "右上のリンク解除アイコンを押すと、現在のデバイスとの接続を切断します。"),

            const SizedBox(height: 24),

            // 7. トラブルシューティング (新規)
            _buildSectionTitle("7. 困ったときは", key: _sectionKeys['troubleshoot']),
            _buildQandA(
              "Q. 接続しても「Unauthorized」等のエラーが出る",
              "A. 初回接続時、テレビ画面に「USBデバッグを許可しますか？」というポップアップが表示されます。\n必ず「常に許可」にチェックを入れて「OK」を押してください。",
            ),
            _buildQandA(
              "Q. デバイスが見つからない",
              "A. スマホとテレビが「同じWi-Fi」に繋がっているか確認してください。ゲスト用Wi-Fiなどは機器同士の通信が遮断されることがあります。",
            ),
            _buildQandA(
              "Q. 動画が再生されない",
              "A. テレビ側のKodiアプリが起動しているか確認してください。また、ロケットアイコンを押してKodiを前面に表示させてみてください。",
            ),

            const SizedBox(height: 24),

            // 8. 設定 (新規)
            _buildSectionTitle("8. アプリ設定", key: _sectionKeys['settings']),
            _buildIconExplanation(Icons.settings_brightness, "テーマ切り替え",
                "メニューの設定から、ダークモード・ライトモード・システム設定の切り替えが可能です。夜間の利用にはダークモードがおすすめです。"),

            const Divider(height: 40),
            Center(
              child: Text(
                "PureTube Cast v1.18.3",
                style: TextStyle(color: Theme.of(context).disabledColor),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Center(
      child: Column(
        children: [
          Icon(Icons.help_outline, size: 64, color: Colors.blueGrey),
          SizedBox(height: 16),
          Text(
            "使い方マニュアル",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {Key? key}) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 12.0, top: 8.0),
      padding: const EdgeInsets.only(bottom: 4.0),
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.redAccent, width: 2)),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStepItem(String badge, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey),
            ),
            child: Text(badge, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(height: 1.4, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconExplanation(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: Colors.blueGrey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(description, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(IconData icon, Color color, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black87, fontSize: 13),
                children: [
                  TextSpan(text: "$title: ", style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Q&A用のウィジェット（新規）
  Widget _buildQandA(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Q.", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(width: 8),
              Expanded(child: Text(question, style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("A.", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: Text(answer, style: const TextStyle(fontSize: 14))),
            ],
          ),
        ],
      ),
    );
  }
}