import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// メタデータ取得 (タイトルやサムネイル)
  Future<Map<String, dynamic>?> fetchMetadata(String url) async {
    try {
      // 1.13.0のようにライブラリを使って詳細を取得
      final videoId = VideoId(url);
      final video = await _yt.videos.get(videoId);

      return {
        'id': video.id.value,
        'url': url,
        'title': video.title,
        'thumbnailUrl': video.thumbnails.highResUrl,
        'duration': _formatDuration(video.duration),
        // ここではまだ streamUrl は取得しない（リスト追加を軽くするため）
        'streamUrl': null,
      };
    } catch (e) {
      print("[YoutubeService] Metadata Fetch Error: $e");
      return null;
    }
  }

  /// ★重要：ストリームURLの抽出 (Kodi標準再生用)
  /// これが成功すれば、アドオンなしで再生できます
  Future<String?> fetchStreamUrl(String url) async {
    try {
      final videoId = VideoId(url);

      // ストリームのマニフェストを取得
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);

      // 音声と映像が一緒になった(muxed)最高画質のファイルURLを取得
      final streamInfo = manifest.muxed.withHighestBitrate();

      return streamInfo.url.toString();
    } catch (e) {
      print("[YoutubeService] Stream Fetch Error: $e");
      return null;
    }
  }

  /// プレイリスト情報の取得
  Future<Map<String, dynamic>?> fetchPlaylistInfo(String url) async {
    try {
      final playlistId = PlaylistId(url);
      final playlist = await _yt.playlists.get(playlistId);

      // 動画一覧を取得 (最初の20件だけ取得するなど制限も可能)
      final videos = await _yt.playlists.getVideos(playlistId).toList();

      return {
        'title': playlist.title,
        'items': videos.map((v) => {
          'title': v.title,
          'url': v.url,
          'thumbnailUrl': v.thumbnails.highResUrl,
          'duration': _formatDuration(v.duration),
          'streamUrl': null,
        }).toList(),
      };
    } catch (e) {
      print("[YoutubeService] Playlist Fetch Error: $e");
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