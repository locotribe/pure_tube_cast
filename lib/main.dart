import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart'; // import残存（念のため）
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'managers/playlist_manager.dart';
import 'pages/playlist_page.dart';
import 'pages/home_page.dart'; // 新規作成したページ
import 'services/youtube_service.dart';
import 'services/dlna_service.dart';

final DlnaService _dlnaService = DlnaService();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  print("[DEBUG] === App Started ===");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PureTube Cast',
      theme: ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const HomePage(), // 変更: DeviceListPage -> HomePage
    );
  }
}

// ----------------------------------------------------------------
// 画面1: デバイス管理（変更: 接続を設定して戻る画面へ）
// ----------------------------------------------------------------
class DeviceListPage extends StatefulWidget {
  const DeviceListPage({super.key});

  @override
  State<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<DeviceListPage> with WidgetsBindingObserver {
  List<DlnaDevice> _devices = [];
  bool _isSearching = false;
  Map<String, String> _customNames = {};
  // 選択中のIP (ローカルstate)
  String? _selectedDeviceIp;

  late StreamSubscription _deviceListSubscription;
  Timer? _searchTimeoutDisplayTimer;

  final int _searchDurationSec = 15;
  final int _targetDeviceCount = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 現在接続中のデバイスがあればそれを初期選択にする
    if (_dlnaService.currentDevice != null) {
      _selectedDeviceIp = _dlnaService.currentDevice!.ip;
    }
    _loadSettingsAndStart();
  }

  Future<void> _loadSettingsAndStart() async {
    await _loadCustomNames();
    await _loadSavedIps();
    _startDeviceSearch();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startDeviceSearch();
    }
  }

  void _startDeviceSearch() {
    if (!mounted) return;
    setState(() => _isSearching = true);
    _dlnaService.startSearch(duration: _searchDurationSec, targetCount: _targetDeviceCount);
    _searchTimeoutDisplayTimer?.cancel();
    _searchTimeoutDisplayTimer = Timer(Duration(seconds: _searchDurationSec), () {
      if (mounted) setState(() => _isSearching = false);
    });

    _deviceListSubscription = _dlnaService.deviceStream.listen((devices) {
      if (mounted) {
        setState(() {
          _devices = devices;
          for (var device in _devices) {
            if (_customNames.containsKey(device.ip) && device.name != _customNames[device.ip]) {
              _dlnaService.updateDeviceName(device.ip, _customNames[device.ip]!);
            }
          }
        });
      }
    });
  }

  void _showAddIpDialog() {
    final TextEditingController ipController = TextEditingController();
    bool isVerifying = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text("IPアドレス追加"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Fire TV (Kodi) のIPアドレスを入力してください。"),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ipController,
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "例: 192.168.1.xxx"),
                    keyboardType: TextInputType.number,
                    enabled: !isVerifying,
                  ),
                  if (isVerifying) ...[const SizedBox(height: 20), const Text("接続テスト中...")]
                ],
              ),
            ),
            actions: [
              if (!isVerifying)
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("キャンセル")),
              if (!isVerifying)
                ElevatedButton(
                  onPressed: () async {
                    final ip = ipController.text.trim();
                    if (ip.isEmpty) return;
                    setStateDialog(() => isVerifying = true);
                    String? savedName = _customNames[ip];
                    await _dlnaService.verifyAndAddManualDevice(ip, customName: savedName);
                    await _addSavedIp(ip);
                    if (mounted) {
                      Navigator.pop(context);
                      setStateDialog(() => isVerifying = false);
                    }
                  },
                  child: const Text("追加"),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteDevice(DlnaDevice device) async {
    _dlnaService.removeDevice(device.ip);
    await _removeSavedIp(device.ip);
    if (_selectedDeviceIp == device.ip) setState(() => _selectedDeviceIp = null);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${device.name} を削除しました")));
  }

  void _showRenameDialog(DlnaDevice device) {
    final TextEditingController nameController = TextEditingController(text: device.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("名前を変更"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: "新しい名前を入力"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("キャンセル")),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isNotEmpty) {
                _dlnaService.updateDeviceName(device.ip, newName);
                await _saveCustomName(device.ip, newName);
                Navigator.pop(context);
              }
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }

  Future<void> _testConnection(DlnaDevice device) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("接続を確認しています..."), duration: Duration(milliseconds: 500)),
    );
    final isConnected = await _dlnaService.checkConnection(device);
    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(isConnected ? "接続成功" : "接続失敗"),
          content: Icon(
            isConnected ? Icons.check_circle : Icons.error,
            color: isConnected ? Colors.green : Colors.red,
            size: 50,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                // 成功したら選択状態にする
                if (isConnected) {
                  setState(() => _selectedDeviceIp = device.ip);
                }
              },
              child: const Text("OK"),
            )
          ],
        ),
      );
    }
  }

  // 変更: 接続を確定して戻る
  void _connectAndReturn() {
    if (_selectedDeviceIp == null) return;

    final device = _devices.firstWhere(
            (d) => d.ip == _selectedDeviceIp,
        orElse: () => _devices.first
    );

    _dlnaService.setDevice(device);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("${device.name} に接続しました")),
    );
    Navigator.pop(context); // 呼び出し元に戻る
  }

  Future<void> _addSavedIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> ips = prefs.getStringList('saved_ips') ?? [];
    if (!ips.contains(ip)) {
      ips.add(ip);
      await prefs.setStringList('saved_ips', ips);
    }
  }

  Future<void> _removeSavedIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> ips = prefs.getStringList('saved_ips') ?? [];
    ips.remove(ip);
    await prefs.setStringList('saved_ips', ips);
  }

  Future<void> _saveCustomName(String ip, String name) async {
    final prefs = await SharedPreferences.getInstance();
    _customNames[ip] = name;
    await prefs.setString('custom_names', jsonEncode(_customNames));
  }

  Future<void> _loadCustomNames() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString('custom_names');
    if (jsonStr != null) {
      try {
        _customNames = Map<String, String>.from(jsonDecode(jsonStr));
      } catch (e) {}
    }
  }

  Future<void> _loadSavedIps() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> ips = prefs.getStringList('saved_ips') ?? [];
    for (var ip in ips) {
      String? name = _customNames[ip];
      _dlnaService.addForcedDevice(ip, customName: name);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deviceListSubscription.cancel();
    _searchTimeoutDisplayTimer?.cancel();
    _dlnaService.stopSearch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('デバイス接続'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddIpDialog),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _startDeviceSearch),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade100,
            width: double.infinity,
            child: Row(
              children: [
                _isSearching
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 10),
                Text(_isSearching ? "検索中 ($_searchDurationSec秒)..." : "検索完了: ${_devices.length}台"),
              ],
            ),
          ),
          Expanded(
            child: _devices.isEmpty
                ? const Center(child: Text("デバイスが見つかりません"))
                : ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final device = _devices[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    leading: Radio<String>(
                      value: device.ip,
                      groupValue: _selectedDeviceIp,
                      onChanged: (String? value) => setState(() => _selectedDeviceIp = value),
                    ),
                    title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(device.ip),
                    onTap: () {
                      setState(() => _selectedDeviceIp = device.ip);
                      _testConnection(device);
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.edit, color: Colors.blueGrey), onPressed: () => _showRenameDialog(device)),
                        IconButton(icon: const Icon(Icons.delete, color: Colors.grey), onPressed: () => _deleteDevice(device)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      // 変更: FABは「接続（設定）」ボタンに変更
      floatingActionButton: _selectedDeviceIp != null
          ? FloatingActionButton.extended(
        onPressed: _connectAndReturn,
        label: const Text("このデバイスに接続", style: TextStyle(color: Colors.white)),
        icon: const Icon(Icons.link, color: Colors.white),
        backgroundColor: Colors.green,
      )
          : null,
    );
  }
}

// ----------------------------------------------------------------
// 画面2: キャスト待機・操作画面（変更: URLを受け取る仕様へ）
// ----------------------------------------------------------------
class CastPage extends StatefulWidget {
  // 変更: デバイス必須を廃止し、URLを受け取る形へ
  final String? initialUrl;

  const CastPage({super.key, this.initialUrl});

  @override
  State<CastPage> createState() => _CastPageState();
}

class _CastPageState extends State<CastPage> {
  final YoutubeService _ytService = YoutubeService();
  final PlaylistManager _playlistManager = PlaylistManager();

  String _statusMessage = "読み込み中...";
  Map<String, dynamic>? _videoMetadata;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 変更: HomePageから渡されたURLを処理
    if (widget.initialUrl != null) {
      _processSharedText(widget.initialUrl!);
    } else {
      _statusMessage = "URLが指定されていません";
    }
  }

  Future<void> _processSharedText(String sharedText) async {
    print("[CastPage] Processing URL: $sharedText");
    if (mounted) {
      setState(() {
        _isLoading = true;
        _statusMessage = "基本情報を取得中...";
        _videoMetadata = null;
      });
    }

    final match = RegExp(r'(https?://\S+)').firstMatch(sharedText);
    if (match != null) {
      final url = match.group(0)!;
      try {
        final metadata = await _ytService.fetchMetadata(url);
        if (mounted) {
          if (metadata != null) {
            setState(() {
              _videoMetadata = metadata;
              _statusMessage = "操作を選択してください";
              _isLoading = false;
            });
          } else {
            setState(() {
              _statusMessage = "動画情報の取得に失敗しました";
              _isLoading = false;
            });
          }
        }
      } catch (e) {
        if (mounted) setState(() {
          _statusMessage = "エラー: $e";
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() {
        _statusMessage = "有効なURLが見つかりませんでした";
        _isLoading = false;
      });
    }
  }

  // 今すぐ再生
  void _playNow() async {
    if (_videoMetadata == null) return;
    final currentDevice = _dlnaService.currentDevice;

    if (currentDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("デバイスに接続されていません。デバイス管理から接続してください。"))
      );
      return;
    }

    setState(() => _isLoading = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('再生準備中...')));

    try {
      final streamUrl = await _ytService.fetchStreamUrl(_videoMetadata!['url']);
      if (streamUrl == null) throw Exception("Stream URL取得失敗");

      await _dlnaService.playNow(
          currentDevice,
          streamUrl,
          _videoMetadata!['title'],
          _videoMetadata!['thumbnailUrl']
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("再生失敗: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // リストに追加（オフラインでも可）
  void _addToList() {
    if (_videoMetadata == null) return;

    // 現在のデバイス（nullならオフライン追加）を渡す
    _playlistManager.processAndAdd(
        _dlnaService,
        _videoMetadata!,
        device: _dlnaService.currentDevice
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('リストに追加しました')),
    );

    // 追加したら一覧に戻るか、そのまま閉じるか
    // ここでは閉じる
    Navigator.pop(context);
  }

  void _openYouTube() async {
    final Uri appUrl = Uri.parse('vnd.youtube://');
    final Uri webUrl = Uri.parse('https://www.youtube.com');
    if (await canLaunchUrl(appUrl)) {
      await launchUrl(appUrl, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 接続状態の監視はしない（再生ボタン押下時にチェック）
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text("動画確認"),
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // サムネイル表示
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      if (_videoMetadata != null)
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.network(_videoMetadata!['thumbnailUrl'], fit: BoxFit.cover),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Icon(Icons.video_library, size: 60, color: Colors.red),
                        ),

                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              _videoMetadata?['title'] ?? "読み込み中...",
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 5),
                            Text(_statusMessage, style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                if (_videoMetadata != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _playNow,
                          icon: const Icon(Icons.play_arrow, size: 28),
                          label: const Text("今すぐ再生", style: TextStyle(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _addToList,
                          icon: const Icon(Icons.playlist_add, size: 28),
                          label: const Text("リストに追加", style: TextStyle(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 40),

                // YouTubeに戻るボタン
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openYouTube,
                    label: const Text("YouTubeに戻る"),
                    icon: const Icon(Icons.open_in_new),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (_isLoading)
          Container(
            color: Colors.black.withOpacity(0.5),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 20),
                  Text(
                    "処理中...",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}