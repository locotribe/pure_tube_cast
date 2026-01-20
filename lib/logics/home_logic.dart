import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import '../managers/playlist_manager.dart';
import '../managers/site_manager.dart';

// URLに基づいて実行すべきアクションの定義
enum UrlAction {
  importPlaylist, // プレイリスト取り込み
  addSite,        // サイト登録
  castVideo,      // 動画解析・キャスト
  unknown,        // 判定不能
}

class HomeLogic {
  final PlaylistManager _playlistManager = PlaylistManager();
  final SiteManager _siteManager = SiteManager();

  /// 共有されたURLに基づいて、実行すべきアクションを判定する
  UrlAction determineAction(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return UrlAction.unknown;

    // 1. YouTubeの判定
    if (uri.host.contains('youtube.com') || uri.host.contains('youtu.be')) {
      // A. プレイリスト一括取込判定
      // listパラメータがあり、かつ "RD" (Mix) で始まらないもの
      if (uri.queryParameters.containsKey('list')) {
        final listId = uri.queryParameters['list']!;
        if (!listId.startsWith('RD')) {
          return UrlAction.importPlaylist;
        }
        // RD(Mix)の場合は、単体動画として扱う
      }

      // B. チャンネル・トップ -> サイト登録
      // @channel, /channel/, またはパス無し
      if (uri.path.startsWith('/@') || uri.path.startsWith('/channel') || uri.path.isEmpty || uri.path == '/') {
        return UrlAction.addSite;
      }

      // C. 動画 (vパラメータ, youtu.be, shorts, またはMixリストの動画) -> 動画解析
      bool isVideo = false;
      if (uri.queryParameters.containsKey('v')) isVideo = true;
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) isVideo = true;
      if (uri.path.startsWith('/shorts/')) isVideo = true;

      if (isVideo) {
        return UrlAction.castVideo;
      }
    }

    // 2. 他サイトのトップページ判定 -> サイト登録
    if (uri.path.isEmpty || uri.path == '/') {
      return UrlAction.addSite;
    }

    // 3. 動画ファイル直リンク -> 動画解析
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.endsWith('.mp4') || lowerUrl.endsWith('.m3u8') || lowerUrl.endsWith('.mov')) {
      return UrlAction.castVideo;
    }

    // 4. 判定不能
    return UrlAction.unknown;
  }

  /// サイトが既に登録済みかチェックする
  bool isSiteRegistered(String url) {
    return _siteManager.isRegistered(url);
  }

  /// プレイリストをインポートする
  Future<String?> importPlaylist(String url) async {
    return await _playlistManager.importFromYoutubePlaylist(url);
  }

  /// サイトを追加する
  void addSite(String name, String url, {String? iconUrl}) {
    _siteManager.addSite(name, url, iconUrl: iconUrl);
  }

  /// URLからサイト情報（タイトル、アイコン）を取得する
  Future<Map<String, String?>> fetchSiteInfo(String url) async {
    String title = "";
    String? iconUrl;

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final document = parser.parse(response.body);
        title = document.querySelector('title')?.text ?? "";

        var iconLink = document.querySelector('link[rel="icon"]')?.attributes['href'];
        iconLink ??= document.querySelector('link[rel="shortcut icon"]')?.attributes['href'];
        iconLink ??= document.querySelector('link[rel="apple-touch-icon"]')?.attributes['href'];

        if (iconLink != null && iconLink.isNotEmpty) {
          iconUrl = Uri.parse(url).resolve(iconLink).toString();
        } else {
          iconUrl = Uri.parse(url).resolve('/favicon.ico').toString();
        }
      }
    } catch (e) {
      print("[HomeLogic] Fetch error: $e");
    }

    return {
      'title': title,
      'iconUrl': iconUrl,
    };
  }
}