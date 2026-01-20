import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/dlna_device.dart';

class KodiRpcClient {
  static const int _kodiPort = 8080;

  /// 汎用RPC送信メソッド
  Future<dynamic> _sendRequest(DlnaDevice device, String method, [Map<String, dynamic>? params]) async {
    final url = Uri.parse('http://${device.ip}:$_kodiPort/jsonrpc');
    final body = {
      "jsonrpc": "2.0",
      "method": method,
      "id": 1,
    };
    if (params != null) {
      body["params"] = params;
    }

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded.containsKey('error')) {
          // エラーでも停止などは許容したい場合があるため、ログを出してnullを返すかthrowするか
          // ここではthrowするが、呼び出し側でcatchが必要
          throw Exception("Kodi Error: ${decoded['error']}");
        }
        return decoded['result'];
      }
      throw Exception("HTTP Error ${response.statusCode}");
    } catch (e) {
      throw Exception("Connection failed: $e");
    }
  }

  String _formatUrl(String url) {
    if (url.contains('youtube.com') || url.contains('youtu.be')) {
      String? videoId;
      final uri = Uri.parse(url);
      if (uri.queryParameters.containsKey('v')) {
        videoId = uri.queryParameters['v'];
      } else if (uri.host.contains('youtu.be')) {
        videoId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      } else if (uri.path.contains('/shorts/')) {
        videoId = uri.pathSegments.last;
      }

      if (videoId != null) {
        return 'plugin://plugin.video.youtube/play/?video_id=$videoId';
      }
    }
    return url;
  }

  // --- 再生制御 ---

  Future<void> playNow(DlnaDevice device, String url, String title, {String? thumbnailUrl}) async {
    final targetUrl = _formatUrl(url);
    await _sendRequest(device, 'Playlist.Clear', {'playlistid': 1});
    await _sendRequest(device, 'Playlist.Add', {
      'playlistid': 1,
      'item': {
        'file': targetUrl,
        'art': {'thumb': thumbnailUrl ?? ''},
        'title': title,
      }
    });
    await _sendRequest(device, 'Player.Open', {'item': {'playlistid': 1, 'position': 0}});
  }

  Future<void> addToPlaylist(DlnaDevice device, String url, String title, {String? thumbnailUrl}) async {
    final targetUrl = _formatUrl(url);
    await _sendRequest(device, 'Playlist.Add', {
      'playlistid': 1,
      'item': {
        'file': targetUrl,
        'art': {'thumb': thumbnailUrl ?? ''},
        'title': title,
      }
    });
  }

  // 【追加】割り込み追加 (Insert)
  Future<void> insertItem(DlnaDevice device, int position, String url, String title, {String? thumbnailUrl}) async {
    final targetUrl = _formatUrl(url);
    await _sendRequest(device, 'Playlist.Insert', {
      'playlistid': 1,
      'position': position,
      'item': {
        'file': targetUrl,
        'art': {'thumb': thumbnailUrl ?? ''},
        'title': title,
      }
    });
  }

  Future<List<KodiPlaylistItem>> getPlaylist(DlnaDevice device) async {
    try {
      final result = await _sendRequest(device, 'Playlist.GetItems', {
        'playlistid': 1,
        'properties': ['title', 'file', 'thumbnail', 'duration']
      });

      if (result != null && result['items'] != null) {
        final List<dynamic> items = result['items'];
        return items.map((item) => KodiPlaylistItem.fromJson(item)).toList();
      }
    } catch (_) {}
    return [];
  }

  // 【追加】プレイヤー状態取得
  Future<Map<String, dynamic>> getPlayerProperties(DlnaDevice device) async {
    try {
      // まずActivePlayerを取得
      final players = await _sendRequest(device, 'Player.GetActivePlayers');
      if (players is List && players.isNotEmpty) {
        final playerId = players[0]['playerid'];

        // プロパティを取得
        final result = await _sendRequest(device, 'Player.GetProperties', {
          'playerid': playerId,
          'properties': ['speed', 'time', 'totaltime', 'position', 'playlistid', 'percentage']
        });
        return result ?? {};
      }
    } catch (_) {}
    return {}; // 再生していない、またはエラー
  }

  Future<void> stop(DlnaDevice device) async {
    try {
      final players = await _sendRequest(device, 'Player.GetActivePlayers');
      if (players is List && players.isNotEmpty) {
        final playerId = players[0]['playerid'];
        await _sendRequest(device, 'Player.Stop', {'playerid': playerId});
      }
    } catch (_) {}
  }

  Future<void> clearPlaylist(DlnaDevice device) async {
    await _sendRequest(device, 'Playlist.Clear', {'playlistid': 1});
  }

  Future<void> jumpToItem(DlnaDevice device, int index) async {
    await _sendRequest(device, 'Player.Open', {
      'item': {'playlistid': 1, 'position': index}
    });
  }

  Future<void> removeItem(DlnaDevice device, int index) async {
    await _sendRequest(device, 'Playlist.Remove', {
      'playlistid': 1,
      'position': index
    });
  }

  Future<void> moveItem(DlnaDevice device, int oldIndex, int newIndex) async {
    await _sendRequest(device, 'Playlist.Swap', {
      'playlistid': 1,
      'position1': oldIndex,
      'position2': newIndex
    });
  }

  Future<void> seek(DlnaDevice device, double percentage) async {
    try {
      final players = await _sendRequest(device, 'Player.GetActivePlayers');
      if (players is List && players.isNotEmpty) {
        final playerId = players[0]['playerid'];
        await _sendRequest(device, 'Player.Seek', {
          'playerid': playerId,
          'value': percentage
        });
      }
    } catch (_) {}
  }

  Future<void> setVolume(DlnaDevice device, int volume) async {
    await _sendRequest(device, 'Application.SetVolume', {'volume': volume});
  }
}