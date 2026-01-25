// lib/views/kodi_launch_button.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/adb_launch_service.dart';

class KodiLaunchButton extends StatefulWidget {
  final String ipAddress;

  const KodiLaunchButton({
    super.key,
    required this.ipAddress,
  });

  @override
  State<KodiLaunchButton> createState() => _KodiLaunchButtonState();
}

class _KodiLaunchButtonState extends State<KodiLaunchButton> {
  bool _isLoading = false;
  bool _isConnected = false;

  Future<void> _handlePress() async {
    setState(() {
      _isLoading = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    final service = AdbLaunchService();

    // 1. ADBコマンド送信 (起動/前面表示)
    final bool success = await service.launchKodi(widget.ipAddress);

    if (!success) {
      if (mounted) {
        setState(() => _isLoading = false);
        messenger.showSnackBar(
          const SnackBar(content: Text('接続に失敗しました。USBデバッグ許可を確認してください')),
        );
      }
      return;
    }

    // 2. 起動確認 (ポーリング)
    // ポート8080(Kodi)が応答するまで1秒おきにチェック (最大15回)
    bool isRunning = false;
    for (int i = 0; i < 15; i++) {
      if (!mounted) return;

      try {
        // タイムアウト短めで接続確認
        final socket = await Socket.connect(widget.ipAddress, 8080, timeout: const Duration(milliseconds: 500));
        socket.destroy();
        isRunning = true;
        break; // 接続できたらループを抜ける
      } catch (e) {
        // 失敗したら1秒待って再試行
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (isRunning) {
          _isConnected = true; // 緑色にする
        }
      });

      if (isRunning) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Kodiの起動を確認しました')),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('起動コマンドを送信しましたが、応答がありません')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 処理中はくるくる回るインジケータを表示
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return IconButton(
      icon: const Icon(Icons.rocket_launch),
      // 起動確認済みなら緑、そうでなければデフォルト色
      color: _isConnected ? Colors.green : null,
      tooltip: 'Kodiを起動',
      onPressed: _handlePress,
    );
  }
}