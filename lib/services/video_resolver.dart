import 'youtube_service.dart';
import 'web_video_service.dart';

class VideoResolver {
  final YoutubeService _ytService = YoutubeService();
  final WebVideoService _webService = WebVideoService();

  /// URLに応じてメタデータを取得
  Future<Map<String, dynamic>?> resolveMetadata(String url) async {
    if (_isYoutubeUrl(url)) {
      print("[Resolver] Detected YouTube URL");
      return await _ytService.fetchMetadata(url);
    } else {
      print("[Resolver] Detected Web URL");
      return await _webService.fetchMetadata(url);
    }
  }

  /// URLに応じて再生用ストリームURLを取得
  Future<String?> resolveStreamUrl(Map<String, dynamic> metadata) async {
    final url = metadata['url'];

    // Web解析ですでにstreamUrlが見つかっている、または直リンクの場合
    if (metadata['streamUrl'] != null) {
      return metadata['streamUrl'];
    }
    if (metadata['isDirectFile'] == true) {
      return url;
    }

    if (_isYoutubeUrl(url)) {
      return await _ytService.fetchStreamUrl(url);
    }

    // ここに来る＝Webサイトだが解析時に動画URLが見つからなかった場合
    return null;
  }

  bool _isYoutubeUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host.contains('youtube.com') || uri.host.contains('youtu.be');
  }
}