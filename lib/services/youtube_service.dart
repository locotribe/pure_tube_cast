import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  // --- Playlist Methods ---

  /// プレイリスト詳細（タイトルなど）を取得
  Future<Map<String, dynamic>?> getPlaylistDetails(String playlistId) async {
    try {
      final playlist = await _yt.playlists.get(playlistId);
      return {
        'title': playlist.title,
        'author': playlist.author,
        'thumbnail': playlist.thumbnails.highResUrl,
      };
    } catch (e) {
      print("[YoutubeService] Playlist Error: $e");
      return null;
    }
  }

  /// プレイリスト内の動画一覧を取得
  Future<List<Map<String, dynamic>>> getPlaylistVideos(String playlistId) async {
    final List<Map<String, dynamic>> videos = [];
    try {
      await for (final video in _yt.playlists.getVideos(playlistId).take(50)) {
        videos.add({
          'id': video.id.value,
          'title': video.title,
          'thumbnail': video.thumbnails.highResUrl,
          'duration': _formatDuration(video.duration),
        });
      }
    } catch (e) {
      print("[YoutubeService] Video List Error: $e");
    }
    return videos;
  }

  // --- Video Methods ---

  /// 【追加】単体動画のメタデータ取得 (VideoResolverで使用)
  Future<Map<String, dynamic>?> getVideoDetails(String url) async {
    try {
      final videoId = VideoId(url);
      final video = await _yt.videos.get(videoId);
      return {
        'id': video.id.value,
        'url': url,
        'title': video.title,
        'thumbnailUrl': video.thumbnails.highResUrl,
        'duration': _formatDuration(video.duration),
      };
    } catch (e) {
      print("[YoutubeService] Metadata Error: $e");
      return null;
    }
  }

  /// ストリームURLの解決
  Future<String?> getStreamUrl(String videoUrl) async {
    try {
      final videoId = VideoId(videoUrl);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final streamInfo = manifest.muxed.withHighestBitrate();
      return streamInfo.url.toString();
    } catch (e) {
      print("[YoutubeService] Stream Error: $e");
      return null;
    }
  }

  // --- Helper ---

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