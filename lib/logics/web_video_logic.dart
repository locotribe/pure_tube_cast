import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../managers/site_manager.dart';
import '../models/site_model.dart';

class WebVideoLogic {
  final SiteManager _siteManager = SiteManager();

  // --- Streams ---
  Stream<List<SiteModel>> get sitesStream => _siteManager.sitesStream;

  // --- Current Data ---
  List<SiteModel> get currentSites => _siteManager.currentSites;

  // --- Actions ---

  /// サイト情報を更新
  void updateSite(String id, String newName, String newUrl) {
    _siteManager.updateSite(id, newName, newUrl);
  }

  /// サイトを削除
  void removeSite(String id) {
    _siteManager.removeSite(id);
  }

  /// URLを外部ブラウザで開く
  /// 成功した場合は true、失敗した場合は false を返す
  Future<bool> launchSiteUrl(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      debugPrint("[WebVideoLogic] Launch Error: $e");
    }
    return false;
  }
}