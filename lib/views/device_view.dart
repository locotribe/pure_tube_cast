// lib/views/device_view.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dlna_service.dart';
import 'kodi_launch_button.dart';

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
    _loadSettings();

    _deviceListSubscription = _dlnaService.deviceStream.listen((devices) {
      if (mounted) {
        setState(() {
          _devices = devices;
          _applyCustomSettings();
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deviceListSubscription.cancel();
    _searchTimeoutDisplayTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final namesString = prefs.getString('custom_device_names');
    if (namesString != null) {
      try {
        _customNames = Map<String, String>.from(jsonDecode(namesString));
      } catch (e) {
        print("Error loading custom names: $e");
      }
    }
    final macsString = prefs.getString('custom_device_macs');
    if (macsString != null) {
      try {
        _customMacs = Map<String, String>.from(jsonDecode(macsString));
      } catch (e) {
        print("Error loading custom macs: $e");
      }
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_device_names', jsonEncode(_customNames));
    await prefs.setString('custom_device_macs', jsonEncode(_customMacs));
  }

  // 【修正2】 オブジェクト不変性への対応 (copyWithを使用)
  void _applyCustomSettings() {
    // リスト内の各デバイスを確認し、カスタム設定があれば copyWith で新しいインスタンスに置き換える
    _devices = _devices.map((device) {
      String? newName = _customNames[device.ip];
      String? newMac = _customMacs[device.ip];

      // カスタム設定がある場合のみコピーを作成
      if (newName != null || newMac != null) {
        return device.copyWith(
          name: newName, // nullの場合は元の値が維持されるようcopyWith実装依存だが、ここでは上書きがある場合のみ渡す
          macAddress: newMac,
        );
      }
      return device;
    }).toList();
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
    });
    // 【修正3】 search() -> startSearch()
    _dlnaService.startSearch();

    _searchTimeoutDisplayTimer?.cancel();
    _searchTimeoutDisplayTimer = Timer(Duration(seconds: _searchDurationSec), () {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _onDeviceTap(DlnaDevice device) async {
    if (_selectedDeviceIp == device.ip) {
      _dlnaService.setDevice(null);
      setState(() {
        _selectedDeviceIp = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("接続を解除しました")),
      );
    } else {
      _dlnaService.setDevice(device);
      setState(() {
        _selectedDeviceIp = device.ip;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${device.name} に接続しました")),
      );
    }
  }

  void _showRenameDialog(DlnaDevice device) {
    // 表示用の初期値設定
    final TextEditingController nameController = TextEditingController(text: device.name);
    final TextEditingController macController = TextEditingController(text: device.macAddress ?? "");

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
                decoration: const InputDecoration(labelText: "表示名"),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: macController,
                decoration: const InputDecoration(
                  labelText: "MACアドレス (WOL用)",
                  hintText: "AA:BB:CC:DD:EE:FF",
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("キャンセル"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              final newMac = macController.text.trim();

              setState(() {
                if (newName.isNotEmpty) {
                  _customNames[device.ip] = newName;
                }
                if (newMac.isNotEmpty) {
                  _customMacs[device.ip] = newMac;
                }
                // 【修正4】 直接代入ではなく、設定保存後に再適用メソッドを呼ぶ
                _applyCustomSettings();
              });
              await _saveSettings();

              if (mounted) Navigator.pop(context);
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDevice(DlnaDevice device) async {
    setState(() {
      _customNames.remove(device.ip);
      _customMacs.remove(device.ip);
    });
    await _saveSettings();

    // 設定削除後、表示を更新（元の名前に戻る）
    // リストの更新のため、一度現在のリストに対して再適用を行うか再検索
    _startSearch(); // シンプルに再検索をかける

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${device.name} の設定を削除しました")),
      );
    }
  }

  void _showAddIpDialog() {
    final TextEditingController ipController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("IPアドレス手動追加"),
        content: TextField(
          controller: ipController,
          decoration: const InputDecoration(
              labelText: "IPアドレス",
              hintText: "192.168.1.xxx"
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("キャンセル"),
          ),
          ElevatedButton(
            onPressed: () {
              final ip = ipController.text.trim();
              if (ip.isNotEmpty) {
                // 【修正5】 addDirectDevice -> verifyAndAddManualDevice
                _dlnaService.verifyAndAddManualDevice(ip);
                if (mounted) Navigator.pop(context);
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _isSearching
                      ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 10),
                  Text(_isSearching ? "検索中..." : "${_devices.length}台 表示中"),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: _isSearching
                        ? const Icon(Icons.refresh, color: Colors.grey)
                        : const Icon(Icons.search),
                    // 【修正済】 startSearch呼び出し
                    onPressed: _isSearching ? null : _startSearch,
                    tooltip: "検索開始",
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
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.touch_app, size: 60, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  "右上の検索ボタンを押して\nデバイスを探してください",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          )
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
                      InkWell(
                        onTap: () => _onDeviceTap(device),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    device.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 12.0,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.wifi, size: 14, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(device.ip,
                                              style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                        ],
                                      ),
                                      if (device.macAddress != null && device.macAddress!.isNotEmpty)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.vpn_key, size: 14, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text(device.macAddress!,
                                                style: const TextStyle(fontSize: 13, color: Colors.grey)),
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

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Kodi起動ボタン
                          KodiLaunchButton(ipAddress: device.ip),

                          const SizedBox(width: 8),

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
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MacAddressFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length < oldValue.text.length) {
      return newValue;
    }
    final text = newValue.text.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    if (text.length > 12) return oldValue;

    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
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