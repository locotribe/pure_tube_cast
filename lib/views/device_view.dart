import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dlna_service.dart';
// 【削除】ADBサービスのインポートを削除
// import '../services/adb_service.dart';

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
  Map<String, String> _customMacs = {};
  String? _selectedDeviceIp;

  late StreamSubscription _deviceListSubscription;
  Timer? _searchTimeoutDisplayTimer;

  final int _searchDurationSec = 15;

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
    await _loadCustomMacs();
    await _loadSavedIps();
    _startDeviceSearch();
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

  Future<void> _saveCustomName(String ip, String name) async {
    final prefs = await SharedPreferences.getInstance();
    _customNames[ip] = name;
    await prefs.setString('custom_names', jsonEncode(_customNames));
  }

  Future<void> _loadCustomMacs() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString('custom_macs');
    if (jsonStr != null) {
      try {
        _customMacs = Map<String, String>.from(jsonDecode(jsonStr));
      } catch (e) {}
    }
  }

  Future<void> _saveCustomMac(String ip, String mac) async {
    final prefs = await SharedPreferences.getInstance();
    _customMacs[ip] = mac;
    await prefs.setString('custom_macs', jsonEncode(_customMacs));
  }

  Future<void> _loadSavedIps() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> ips = prefs.getStringList('saved_ips') ?? [];
    for (var ip in ips) {
      String? name = _customNames[ip];
      _dlnaService.addForcedDevice(ip, customName: name);
    }
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startDeviceSearch();
    }
  }

  void _startDeviceSearch() {
    if (!mounted) return;
    setState(() => _isSearching = true);
    _dlnaService.startSearch(duration: _searchDurationSec);
    _searchTimeoutDisplayTimer?.cancel();
    _searchTimeoutDisplayTimer = Timer(Duration(seconds: _searchDurationSec), () {
      if (mounted) setState(() => _isSearching = false);
    });

    _deviceListSubscription = _dlnaService.deviceStream.listen((devices) {
      if (mounted) {
        setState(() {
          _devices = devices;
          for (int i = 0; i < _devices.length; i++) {
            var device = _devices[i];
            String? savedName = _customNames[device.ip];
            String? savedMac = _customMacs[device.ip];

            if ((savedName != null && device.name != savedName) ||
                (savedMac != null && device.macAddress != savedMac)) {
              _devices[i] = device.copyWith(
                  name: savedName ?? device.name,
                  macAddress: savedMac ?? device.macAddress
              );
            }
          }
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deviceListSubscription.cancel();
    _searchTimeoutDisplayTimer?.cancel();
    _dlnaService.stopSearch();
    super.dispose();
  }

  // ■■■■■ 接続確認のみ ■■■■■
  Future<void> _testConnection(DlnaDevice device) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("接続を確認しています..."), duration: Duration(milliseconds: 500)),
    );
    final isConnected = await _dlnaService.checkConnection(device);
    if (mounted) {
      if (isConnected) {
        _dlnaService.setDevice(device);
        setState(() => _selectedDeviceIp = device.ip);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${device.name} に接続しました")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("接続できませんでした。Kodiが起動していない可能性があります。"), backgroundColor: Colors.orange),
        );
      }
    }
  }

  // ■■■■■ WOL送信のみ ■■■■■
  Future<void> _sendWolOnly(DlnaDevice device) async {
    if (device.macAddress == null || device.macAddress!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("MACアドレス未設定。編集ボタンから設定してください。")),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("WOL送信: ${device.macAddress}")),
    );
    await _dlnaService.sendWakeOnLan(device.macAddress);
  }

  // 【削除】_launchKodiOnly メソッドを完全に削除

  void _showRenameDialog(DlnaDevice device) {
    final TextEditingController nameController = TextEditingController(text: device.name);
    final TextEditingController macController = TextEditingController(text: device.macAddress);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("デバイス設定"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "表示名", hintText: "リビングのTV"),
              ),
              const SizedBox(height: 16),
              // MACアドレス入力欄 (自動フォーマット付き)
              TextField(
                controller: macController,
                decoration: const InputDecoration(
                    labelText: "MACアドレス (WOL用)",
                    hintText: "AA:BB:CC:DD:EE:FF",
                    helperText: "数字と文字を入力すると自動で整形されます"
                ),
                inputFormatters: [
                  _MacAddressFormatter(),
                ],
                textCapitalization: TextCapitalization.characters,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("キャンセル")),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              final newMac = macController.text.trim();

              if (newName.isNotEmpty) {
                _dlnaService.updateDeviceName(device.ip, newName);
                await _saveCustomName(device.ip, newName);
              }
              setState(() => _customMacs[device.ip] = newMac);
              await _saveCustomMac(device.ip, newMac);

              if (mounted) Navigator.pop(context);
              _startDeviceSearch();
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // --- ヘッダー ---
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
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _startDeviceSearch, tooltip: "再検索"),
                  IconButton(icon: const Icon(Icons.add), onPressed: _showAddIpDialog, tooltip: "手動追加"),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // --- デバイスリスト ---
        Expanded(
          child: _devices.isEmpty
              ? const Center(child: Text("デバイスが見つかりません"))
              : ListView.builder(
            itemCount: _devices.length,
            itemBuilder: (context, index) {
              final device = _devices[index];
              final bool isConnected = _selectedDeviceIp == device.ip;

              return Card(
                color: isConnected
                    ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                    : null,
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- 上段：情報エリア（タップで接続確認） ---
                      InkWell(
                        onTap: () => _testConnection(device),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // デバイス名
                                  Text(
                                    device.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  // IPアドレスとMACアドレスを横並びで
                                  Wrap(
                                    spacing: 12.0,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.wifi, size: 14, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(device.ip, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                        ],
                                      ),
                                      if (device.macAddress != null && device.macAddress!.isNotEmpty)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.vpn_key, size: 14, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text(device.macAddress!, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                          ],
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (isConnected)
                              const Icon(Icons.link, color: Colors.green),
                          ],
                        ),
                      ),

                      const Divider(),

                      // --- 下段：操作ボタンエリア ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // WOLボタン
                          Tooltip(
                            message: "WOL (起動信号) を送信",
                            child: ElevatedButton.icon(
                              onPressed: () => _sendWolOnly(device),
                              icon: const Icon(Icons.tv, size: 18),
                              label: const Text("WOL"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade50,
                                foregroundColor: Colors.blue,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),

                          // 【削除】ADB起動ボタンを削除
                          /*
                          Tooltip(
                            message: "Kodiを起動 (ADB)",
                            child: ElevatedButton.icon(
                              onPressed: () => _launchKodiOnly(device),
                              icon: const Icon(Icons.rocket_launch, size: 18),
                              label: const Text("起動"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade50,
                                foregroundColor: Colors.deepOrange,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                          */

                          // 編集・削除
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                                onPressed: () => _showRenameDialog(device),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 20, color: Colors.grey),
                                onPressed: () => _deleteDevice(device),
                              ),
                            ],
                          ),
                        ],
                      ),
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

// MACアドレス整形フォーマッター (変更なし)
class _MacAddressFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length < oldValue.text.length) {
      return newValue;
    }
    // 数字とA-F以外を除去
    final text = newValue.text.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    if (text.length > 12) return oldValue;

    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      // 2文字ごとにコロンを入れる
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 2 == 0 && nonZeroIndex != text.length) {
        buffer.write(':');
      }
    }
    final string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}