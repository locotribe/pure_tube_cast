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

  // 【変更】iconUrl引数を追加
  void addSite(String name, String url, {String? iconUrl}) {
    final newSite = SiteModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      url: url,
      iconUrl: iconUrl,
    );
    _sites.add(newSite);
    _notifyAndSave();
  }

  // 【追加】サイト情報の更新（編集用）
  void updateSite(String id, String newName, String newUrl, {String? newIconUrl}) {
    final index = _sites.indexWhere((s) => s.id == id);
    if (index != -1) {
      // 既存のアイコンURLを維持するか、新しいもので上書きするか
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