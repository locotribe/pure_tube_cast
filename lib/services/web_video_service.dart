import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

class WebVideoService {
  /// 一般サイトのメタデータ取得
  Future<Map<String, dynamic>?> fetchMetadata(String url) async {
    try {
      // 1. 直接リンク系 (.mp4 など) の簡易判定
      final uri = Uri.parse(url);
      final path = uri.path.toLowerCase();
      if (path.endsWith('.mp4') || path.endsWith('.m3u8') || path.endsWith('.mov')) {
        return {
          'id': url, // IDはURLそのものとする
          'url': url,
          'title': path.split('/').last, // ファイル名をタイトルに
          'thumbnailUrl': null, // サムネイルなし
          'duration': '--:--',
          'isDirectFile': true, // 識別フラグ
        };
      }

      // 2. HTMLページの解析 (OGP取得)
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;

      final document = parser.parse(response.body);

      // タイトル取得 (og:title > titleタグ)
      String title = document.querySelector('meta[property="og:title"]')?.attributes['content'] ??
          document.querySelector('title')?.text ??
          "Unknown Title";

      // サムネイル取得 (og:image)
      String? thumbnailUrl = document.querySelector('meta[property="og:image"]')?.attributes['content'];

      // 動画URL取得 (og:video 等)
      String? videoUrl = document.querySelector('meta[property="og:video:secure_url"]')?.attributes['content'] ??
          document.querySelector('meta[property="og:video"]')?.attributes['content'];

      // OGPで見つからない場合、videoタグのsrcを探す（簡易的）
      if (videoUrl == null) {
        final videoTag = document.querySelector('video');
        if (videoTag != null) {
          videoUrl = videoTag.attributes['src'];
          // sourceタグチェック
          if (videoUrl == null) {
            final sourceTag = videoTag.querySelector('source');
            videoUrl = sourceTag?.attributes['src'];
          }
        }
      }

      // 相対パスなら絶対パスに変換
      if (videoUrl != null && !videoUrl.startsWith('http')) {
        videoUrl = uri.resolve(videoUrl).toString();
      }

      print("[WebVideo] Parsed: $title / Video: $videoUrl");

      return {
        'id': url,
        'url': url,
        'title': title,
        'thumbnailUrl': thumbnailUrl,
        'duration': '--:--',
        'streamUrl': videoUrl, // 解析で見つかった場合ここにセット
        'isDirectFile': false,
      };

    } catch (e) {
      print("[WebVideo] Error: $e");
      return null;
    }
  }
}