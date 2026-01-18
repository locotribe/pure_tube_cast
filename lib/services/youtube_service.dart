import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// 動画メタデータの取得 (既存)
  Future<Map<String, dynamic>?> fetchMetadata(String url) async {
    try {
      final videoId = VideoId(url);
      final video = await _yt.videos.get(videoId);
      String durationStr = _formatDuration(video.duration);

      return {
        'id': video.id.value,
        'url': url,
        'title': video.title,
        'thumbnailUrl': video.thumbnails.highResUrl,
        'duration': durationStr,
      };
    } catch (e) {
      print("[DEBUG] Metadata Fetch Error: $e");
      return null;
    }
  }

  /// 【追加】プレイリスト情報の取得
  Future<Map<String, dynamic>?> fetchPlaylistInfo(String url) async {
    try {
      final playlistId = PlaylistId(url);

      // プレイリストの情報を取得
      final playlist = await _yt.playlists.get(playlistId);

      // 動画一覧を取得 (最大200件まで取得するように制限しても良いですが、一旦全件取得します)
      final videos = await _yt.playlists.getVideos(playlistId).toList();

      return {
        'title': playlist.title,
        'items': videos.map((v) => {
          'title': v.title,
          'url': v.url,
          'thumbnailUrl': v.thumbnails.highResUrl,
          'duration': _formatDuration(v.duration),
        }).toList(),
      };
    } catch (e) {
      print("[DEBUG] Playlist Fetch Error: $e");
      return null;
    }
  }

  /// ストリームURLの取得 (既存)
  Future<String?> fetchStreamUrl(String url) async {
    try {
      final videoId = VideoId(url);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final streamInfo = manifest.muxed.withHighestBitrate();
      return streamInfo.url.toString();
    } catch (e) {
      return null;
    }
  }

  String _formatDuration(Duration? d) {
    if (d == null) return "--:--";
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  void dispose() {
    _yt.close();
  }
}