import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// 【高速】動画のメタデータ（タイトル、画像、時間）のみを取得
  Future<Map<String, dynamic>?> fetchMetadata(String url) async {
    try {
      final videoId = VideoId(url);
      final video = await _yt.videos.get(videoId);

      String durationStr = _formatDuration(video.duration);

      print("[DEBUG] YoutubeService: Metadata fetched: ${video.title}");

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

  /// 【低速】再生用のストリームURLを取得（バックグラウンド実行用）
  Future<String?> fetchStreamUrl(String url) async {
    try {
      final videoId = VideoId(url);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final streamInfo = manifest.muxed.withHighestBitrate();
      print("[DEBUG] YoutubeService: Stream URL resolved");
      return streamInfo.url.toString();
    } catch (e) {
      print("[DEBUG] Stream Fetch Error: $e");
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