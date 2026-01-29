import 'package:flutter/material.dart';

class HelpPage extends StatefulWidget {
  final String? initialSection;

  const HelpPage({super.key, this.initialSection});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  // HomePageのドロワーメニューの引数(ID)と、このページのジャンプ先を紐付け
  final Map<String, GlobalKey> _sectionKeys = {
    'connection': GlobalKey(),
    'sites': GlobalKey(),
    'playback': GlobalKey(),
    'organize': GlobalKey(),
    'update': GlobalKey(),
    'remote': GlobalKey(),
    'troubleshoot': GlobalKey(),
    'settings': GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    // 指定されたセクションがある場合、描画後に自動スクロール
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
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 32),

            // 1. 接続と準備
            _buildSectionTitle("1. デバイスとの接続設定", key: _sectionKeys['connection']),
            _buildDescription("PureTube Castを使用するには、テレビ側のFire TVやAndroid TVで「ADBデバッグ」が有効である必要があります。"),
            _buildStepItem("1", "テレビ側の準備", "設定 > マイFire TV > 開発者オプション から「ADBデバッグ」をONにします。"),
            _buildStepItem("2", "アプリでの接続", "「接続」タブから対象のデバイスを選択します。リストに出ない場合は右上の「+」からIPアドレスを直接入力してください。"),
            _buildIconExplanation(Icons.rocket_launch, "Kodiの遠隔起動", "ロケットアイコンをタップすると、テレビ側でKodiが起動していない場合でも、スマホから強制的に起動・前面表示させることができます。"),

            const SizedBox(height: 32),

            // 2. 動画サイトの管理
            _buildSectionTitle("2. 動画サイトの登録", key: _sectionKeys['sites']),
            _buildDescription("よく使う動画サイトを登録しておくと、アプリ内ブラウザから素早く動画を探せます。"),
            _buildStepItem("A", "サイトの追加", "「動画サイト」タブの「＋サイトを追加」から、名前とURLを入力して登録します。"),
            _buildStepItem("B", "共有からの登録", "スマホのブラウザでサイトを閲覧中に「共有」から本アプリを選ぶと、そのサイトをブックマークとして保存できます。"),

            const SizedBox(height: 32),

            // 3. 動画の再生・ライブラリ
            _buildSectionTitle("3. キャストとライブラリ", key: _sectionKeys['playback']),
            _buildDescription("YouTubeアプリやブラウザから動画をテレビへ送ります。"),
            _buildStepItem("!", "基本操作", "共有メニューから本アプリを選択。「今すぐ再生」で即時キャスト、「ライブラリに保存」で後で見るリストに追加されます。"),
            _buildStepItem("★", "プレイリストの一括取込", "YouTubeのプレイリストURLを共有すると、リスト内の全動画を自動で解析し、一括でライブラリに取り込むことが可能です。"),

            const SizedBox(height: 12),
            _buildStatusTable(),

            const SizedBox(height: 32),

            // 4. ライブラリの整理
            _buildSectionTitle("4. プレイリストと整理", key: _sectionKeys['organize']),
            _buildDescription("取り込んだ動画は、用途に合わせてフォルダ（プレイリスト）に分けることができます。"),
            _buildIconExplanation(Icons.create_new_folder, "フォルダ管理", "ライブラリ画面右下の「＋」ボタンから、新しいフォルダを作成・命名できます。"),
            _buildIconExplanation(Icons.drag_handle, "並び替え", "フォルダや動画を長押しすると、上下にドラッグして順番を自由に入れ替えられます。"),
            _buildIconExplanation(Icons.swipe, "削除", "不要になった動画は、左にスワイプすることで簡単に削除できます。"),

            const SizedBox(height: 32),

            // 5. リンクの更新
            _buildSectionTitle("5. 期限切れリンクの更新", key: _sectionKeys['update']),
            _buildDescription("一部の動画サイトでは、一定時間が経過すると動画の再生URLが無効になります。その場合は以下の手順で更新してください。"),
            _buildStepItem("1", "再読み込み", "ライブラリで「警告アイコン」が出ている動画をタップし、「ブラウザで開く」を選択します。"),
            _buildStepItem("2", "再共有", "開いたブラウザ上で再度「共有」ボタンを押し、本アプリを選択します。"),
            _buildStepItem("3", "更新確定", "「既存のアイテムを更新」というメニューが表示されるので、それを選択してリンクを新しく塗り替えます。"),

            const SizedBox(height: 32),

            // 6. リモコン操作
            _buildSectionTitle("6. 高度なリモコン操作", key: _sectionKeys['remote']),
            _buildDescription("キャスト中、スマホをリモコンとして使用できます。"),
            _buildIconExplanation(Icons.fast_forward, "可変速シーク", "早送り・巻き戻しボタンは、押す回数に応じて「2倍→4倍→8倍→16倍→32倍」と加速します。「1.0x」ボタンで通常再生に戻ります。"),
            _buildIconExplanation(Icons.replay_10, "10秒スキップ", "少しだけ戻したり進めたりしたい時に便利です。"),
            _buildIconExplanation(Icons.volume_up, "音量制御", "テレビ本体ではなく、Kodiアプリ内のシステム音量をスライダーで微調整します。"),

            const SizedBox(height: 32),

            // 7. トラブルシューティング
            _buildSectionTitle("7. 困ったときは", key: _sectionKeys['troubleshoot']),
            _buildQandA(
              "Q. キャストボタンを押してもテレビが反応しない",
              "A. テレビ画面に「ADB接続を許可しますか？」という確認が出ている場合があります。「常に許可」にチェックを入れてOKを押してください。",
            ),
            _buildQandA(
              "Q. 解析エラー(Error)と表示される",
              "A. 通信状態が悪いか、動画サイトの仕様変更により解析できなくなっている可能性があります。アプリのアップデートを確認してください。",
            ),

            const SizedBox(height: 32),

            // 8. 設定
            _buildSectionTitle("8. 外観・その他の設定", key: _sectionKeys['settings']),
            _buildIconExplanation(Icons.palette, "テーマ設定", "ドロワーの「モード設定」から、ライトモード・ダークモードを切り替えられます。夜間の使用にはダークモードがおすすめです。"),

            const Divider(height: 60),
            Center(
              child: Column(
                children: [
                  Text("PureTube Cast", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700)),
                  const SizedBox(height: 4),
                  Text("Version 1.18.8", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  // --- 共通ウィジェット部品 ---

  Widget _buildHeader() {
    return const Center(
      child: Column(
        children: [
          Icon(Icons.auto_stories_outlined, size: 72, color: Colors.blueGrey),
          SizedBox(height: 16),
          Text("使い方ガイド", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          SizedBox(height: 8),
          Text("アプリを最大限に活用するための手引き", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {Key? key}) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.only(bottom: 8.0),
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.redAccent, width: 2.5)),
      ),
      child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildDescription(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(text, style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87)),
    );
  }

  Widget _buildStepItem(String badge, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: Colors.blueGrey.shade100,
            child: Text(badge, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(height: 1.4, fontSize: 14, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconExplanation(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 24, color: Colors.blueGrey.shade600),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text(description, style: const TextStyle(color: Colors.black54, fontSize: 13.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTable() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("ライブラリ内のアイコン解説", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey)),
          const SizedBox(height: 10),
          _statusRow(Icons.check_circle, Colors.green, "送信完了", "Kodiへの送信に成功した状態"),
          _statusRow(Icons.refresh, Colors.orange, "解析中", "動画のURLを取得している最中"),
          _statusRow(Icons.warning, Colors.red, "期限切れ", "再生URLが無効になった状態。要更新"),
          _statusRow(Icons.error, Colors.red, "解析失敗", "サイトからURLを取得できなかった状態"),
        ],
      ),
    );
  }

  Widget _statusRow(IconData icon, Color color, String label, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          SizedBox(width: 70, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          Expanded(child: Text(desc, style: const TextStyle(fontSize: 12, color: Colors.black54))),
        ],
      ),
    );
  }

  Widget _buildQandA(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Q. $question", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
          const SizedBox(height: 8),
          Text("A. $answer", style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5)),
        ],
      ),
    );
  }
}