import 'youtube_service.dart';
import 'web_video_service.dart';

class VideoResolver {
  final YoutubeService _ytService = YoutubeService();
  final WebVideoService _webService = WebVideoService();

  Future<Map<String, dynamic>?> resolveMetadata(String url) async {
    if (_isYoutubeUrl(url)) {
      print("[Resolver] Detected YouTube URL");
      return await _ytService.fetchMetadata(url);
    } else {
      print("[Resolver] Detected Web URL");
      return await _webService.fetchMetadata(url);
    }
  }

  /// 再生用URLの解決
  Future<String?> resolveStreamUrl(Map<String, dynamic> metadata) async {
    final url = metadata['url'];

    // YouTubeの場合は、ここで初めて解析して「生URL」を取得する
    if (_isYoutubeUrl(url)) {
      print("[Resolver] Fetching raw stream URL for Kodi...");
      final streamUrl = await _ytService.fetchStreamUrl(url);
      if (streamUrl != null) {
        return streamUrl; // これが mp4 (googlevideo.com) のURL
      }
      // 失敗した場合は null を返す (解析エラー)
      return null;
    }

    // 他のWeb動画
    if (metadata['streamUrl'] != null && metadata['streamUrl'].toString().isNotEmpty) {
      return metadata['streamUrl'];
    }
    if (metadata['isDirectFile'] == true) {
      return url;
    }

    return null;
  }

  bool _isYoutubeUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host.contains('youtube.com') || uri.host.contains('youtu.be');
  }
}