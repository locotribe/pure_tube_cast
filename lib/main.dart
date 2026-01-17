import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/home_page.dart'; // HomePageへ遷移するため
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
      home: const HomePage(),
    );
  }
}

// ----------------------------------------------------------------
// 画面1: デバイス管理
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
    Navigator.pop(context);
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