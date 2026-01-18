import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dlna_service.dart';

class DeviceView extends StatefulWidget {
  const DeviceView({super.key});

  @override
  State<DeviceView> createState() => _DeviceViewState();
}

class _DeviceViewState extends State<DeviceView> with WidgetsBindingObserver {
  final DlnaService _dlnaService = DlnaService();

  List<DlnaDevice> _devices = [];
  bool _isSearching = false;
  Map<String, String> _customNames = {};
  String? _selectedDeviceIp;

  late StreamSubscription _deviceListSubscription;
  Timer? _searchTimeoutDisplayTimer;

  final int _searchDurationSec = 15;
  final int _targetDeviceCount = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  // IP追加ダイアログ (変更なし)
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
      if (isConnected) {
        // 接続成功時は自動的にセット
        _dlnaService.setDevice(device);
        setState(() => _selectedDeviceIp = device.ip);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${device.name} に接続しました")),
        );
      } else {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("接続失敗"),
            content: const Icon(Icons.error, color: Colors.red, size: 50),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
          ),
        );
      }
    }
  }

  // SharedPreferences関連 (変更なし)
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
    // ScaffoldではなくColumnを返す
    return Column(
      children: [
        // ヘッダー兼操作バー
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _isSearching
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 10),
                  Text(_isSearching ? "検索中..." : "${_devices.length}台 見つかりました"),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _startDeviceSearch,
                    tooltip: "再検索",
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _showAddIpDialog,
                    tooltip: "手動追加",
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _devices.isEmpty
              ? const Center(child: Text("デバイスが見つかりません"))
              : ListView.builder(
            itemCount: _devices.length,
            itemBuilder: (context, index) {
              final device = _devices[index];
              // 現在接続中のデバイス判定
              final bool isConnected = _selectedDeviceIp == device.ip;

              return Card(
                // 【修正】接続中の色をダークモードでも見やすく（半透明にするなど）
                color: isConnected
                    ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                    : null,
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: Icon(
                      Icons.tv,
                      // 【修正】アイコン色
                      color: isConnected ? Theme.of(context).colorScheme.primary : Colors.grey
                  ),
                  title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(device.ip),
                  onTap: () {
                    // タップで接続テスト＆接続
                    _testConnection(device);
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isConnected)
                        const Padding(
                          padding: EdgeInsets.only(right: 8.0),
                          child: Text("接続中", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                        ),
                      IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _showRenameDialog(device)),
                      IconButton(icon: const Icon(Icons.delete, size: 20), onPressed: () => _deleteDevice(device)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}