import 'dart:io';

class WolService {
  /// Wake-on-LAN パケットを送信する
  Future<void> sendWakeOnLan(String? mac) async {
    if (mac == null || mac.isEmpty) return;

    // MACアドレスの整形 (コロンやハイフンを除去)
    final String cleanMac = mac.replaceAll(':', '').replaceAll('-', '').trim();
    if (cleanMac.length != 12) return;

    try {
      // Magic Packetの生成
      // ヘッダー: FF FF FF FF FF FF
      final List<int> packet = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF];

      final List<int> macBytes = [];
      for (int i = 0; i < 12; i += 2) {
        macBytes.add(int.parse(cleanMac.substring(i, i + 2), radix: 16));
      }

      // MACアドレスを16回繰り返す
      for (int i = 0; i < 16; i++) {
        packet.addAll(macBytes);
      }

      // ブロードキャスト送信
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(packet, InternetAddress('255.255.255.255'), 9);
      socket.close();

      print("[WOL] Sent to $mac");
    } catch (e) {
      print("[WOL] Error: $e");
    }
  }
}