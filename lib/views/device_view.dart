import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/dlna_service.dart';
import '../logics/device_view_logic.dart';

class DeviceView extends StatefulWidget {
  const DeviceView({super.key});

  @override
  State<DeviceView> createState() => _DeviceViewState();
}

class _DeviceViewState extends State<DeviceView> with WidgetsBindingObserver {
  final DeviceViewLogic _logic = DeviceViewLogic();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _logic.init().then((_) {
      _logic.startSearch();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _logic.startSearch();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _logic.dispose();
    super.dispose();
  }

  // ■■■■■ 接続/切断のトグル ■■■■■
  Future<void> _onDeviceTap(DlnaDevice device, bool isConnected) async {
    if (isConnected) {
      // 接続解除
      _logic.disconnect();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("接続を解除しました")),
      );
    } else {
      // 接続確認
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("接続を確認しています..."), duration: Duration(milliseconds: 500)),
      );
      final success = await _logic.checkConnection(device);
      if (mounted) {
        if (success) {
          _logic.setSelectDevice(device);
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
  }

  // ■■■■■ WOL送信 ■■■■■
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
    await _logic.sendWol(device.macAddress!);
  }

  // ■■■■■ アプリ起動 (ADB) ■■■■■
  // 【追加】ロケットアイコン押下時の処理
  Future<void> _launchApp(DlnaDevice device) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("${device.name} へ起動コマンドを送信中...")),
    );

    try {
      await _logic.launchAppViaAdb(device);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("起動コマンドを送信しました")),
        );
      }
    } catch (e) {
      if (mounted) {
        // エラー詳細を表示（接続拒否やタイムアウトなど）
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("起動失敗: $e"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

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

              await _logic.updateDeviceSettings(device, newName, newMac);

              if (mounted) Navigator.pop(context);
              // 設定反映のため再検索
              _logic.startSearch();
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

                    await _logic.addManualIp(ip);

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
    await _logic.removeDevice(device);
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
              ValueListenableBuilder<bool>(
                valueListenable: _logic.isSearching,
                builder: (context, isSearching, child) {
                  return StreamBuilder<List<DlnaDevice>>(
                    stream: _logic.devicesStream,
                    initialData: const [],
                    builder: (context, snapshot) {
                      final count = snapshot.data?.length ?? 0;
                      return Row(
                        children: [
                          isSearching
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.check_circle, color: Colors.green, size: 20),
                          const SizedBox(width: 10),
                          Text(isSearching ? "検索中..." : "$count台 見つかりました"),
                        ],
                      );
                    },
                  );
                },
              ),
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _logic.startSearch, tooltip: "再検索"),
                  IconButton(icon: const Icon(Icons.add), onPressed: _showAddIpDialog, tooltip: "手動追加"),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // --- デバイスリスト ---
        Expanded(
          child: StreamBuilder<List<DlnaDevice>>(
            stream: _logic.devicesStream,
            initialData: const [],
            builder: (context, snapshot) {
              final devices = snapshot.data ?? [];

              if (devices.isEmpty) {
                return const Center(child: Text("デバイスが見つかりません"));
              }

              return StreamBuilder<DlnaDevice?>(
                stream: _logic.connectedDeviceStream,
                initialData: _logic.currentConnectedDevice,
                builder: (context, connectedSnapshot) {
                  final connectedDevice = connectedSnapshot.data;

                  return ListView.builder(
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      final bool isConnected = connectedDevice?.ip == device.ip;

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
                              // --- 上段：情報エリア（タップで接続/切断） ---
                              InkWell(
                                onTap: () => _onDeviceTap(device, isConnected),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            device.name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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

                              // --- 下段：操作ボタン ---
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
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
                                  Row(
                                    children: [
                                      // 【追加】ロケットアイコン (Kodi起動)
                                      IconButton(
                                        icon: const Icon(Icons.rocket_launch, size: 20, color: Colors.deepOrange),
                                        tooltip: "Kodiを起動 (ADB)",
                                        onPressed: () => _launchApp(device),
                                      ),
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
                  );
                },
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