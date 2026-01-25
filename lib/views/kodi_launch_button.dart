// lib/views/kodi_launch_button.dart
import 'package:flutter/material.dart';
import '../services/adb_launch_service.dart';

class KodiLaunchButton extends StatelessWidget {
  final String ipAddress;

  const KodiLaunchButton({
    super.key,
    required this.ipAddress,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.rocket_launch),
      tooltip: 'Kodiを起動',
      onPressed: () async {
        // 処理中のコンテキストが破棄されていないか確認するための参照
        final messenger = ScaffoldMessenger.of(context);

        // ロジックの実行
        final bool success = await AdbLaunchService().launchKodi(ipAddress);

        // 結果をスナックバーで通知
        if (messenger.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? 'Kodi起動コマンドを送信しました'
                    : '接続に失敗しました。USBデバッグ許可を確認してください',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }
}