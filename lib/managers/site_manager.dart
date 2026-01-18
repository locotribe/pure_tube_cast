import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/site_model.dart';

class SiteManager {
  static final SiteManager _instance = SiteManager._internal();
  factory SiteManager() => _instance;

  SiteManager._internal() {
    _loadFromStorage();
  }

  final List<SiteModel> _sites = [];
  final StreamController<List<SiteModel>> _streamController = StreamController.broadcast();

  Stream<List<SiteModel>> get sitesStream => _streamController.stream;
  List<SiteModel> get currentSites => _sites;

  // --- 操作ロジック ---

  void addSite(String name, String url, {String? iconUrl}) {
    // 【追加】重複チェック
    if (isRegistered(url)) return;

    final newSite = SiteModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      url: url,
      iconUrl: iconUrl,
    );
    _sites.add(newSite);
    _notifyAndSave();
  }

  // 【追加】登録済みチェック
  bool isRegistered(String url) {
    String normalize(String u) {
      var s = u.trim();
      if (s.endsWith('/')) s = s.substring(0, s.length - 1);
      return s;
    }

    final target = normalize(url);

    // YouTubeトップなどは登録不要
    if (target == 'https://www.youtube.com' || target == 'https://m.youtube.com') {
      return true;
    }

    return _sites.any((site) => normalize(site.url) == target);
  }

  void updateSite(String id, String newName, String newUrl, {String? newIconUrl}) {
    final index = _sites.indexWhere((s) => s.id == id);
    if (index != -1) {
      final oldIcon = _sites[index].iconUrl;
      _sites[index] = SiteModel(
        id: id,
        name: newName,
        url: newUrl,
        iconUrl: newIconUrl ?? oldIcon,
      );
      _notifyAndSave();
    }
  }

  void removeSite(String id) {
    _sites.removeWhere((site) => site.id == id);
    _notifyAndSave();
  }

  void _notifyAndSave() {
    _streamController.add(List.from(_sites));
    _saveToStorage();
  }

  // --- 永続化ロジック ---

  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonStr = jsonEncode(_sites.map((e) => e.toJson()).toList());
    await prefs.setString('saved_sites', jsonStr);
  }

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('saved_sites');
    if (jsonStr != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        _sites.clear();
        _sites.addAll(jsonList.map((e) => SiteModel.fromJson(e)).toList());
        _streamController.add(List.from(_sites));
      } catch (e) {
        print("[SiteManager] Load failed: $e");
      }
    }
  }
}