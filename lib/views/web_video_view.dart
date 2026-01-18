import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../managers/site_manager.dart';
import '../models/site_model.dart';

class WebVideoView extends StatelessWidget {
  const WebVideoView({super.key});

  @override
  Widget build(BuildContext context) {
    final SiteManager siteManager = SiteManager();

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<SiteModel>>(
            stream: siteManager.sitesStream,
            initialData: siteManager.currentSites,
            builder: (context, snapshot) {
              final sites = snapshot.data ?? [];

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.3,
                ),
                itemCount: 1 + sites.length,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // YouTube (固定)
                    return _buildSiteCard(
                      context,
                      site: SiteModel(id: 'yt', name: "YouTube", url: "https://www.youtube.com"),
                      isEditable: false,
                      fixedIcon: Icons.play_circle_fill,
                      fixedColor: Colors.red,
                    );
                  } else {
                    final site = sites[index - 1];
                    return _buildSiteCard(
                      context,
                      site: site,
                      isEditable: true,
                    );
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSiteCard(
      BuildContext context, {
        required SiteModel site,
        required bool isEditable,
        IconData? fixedIcon,
        Color? fixedColor,
      }) {
    return InkWell(
      onTap: () => _openUrl(context, site.url),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          // 【修正】テーマのカード色を使用
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            // 【修正】ボーダー色を薄く、ダークモード対応
            color: Theme.of(context).dividerColor.withOpacity(0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // アイコン表示ロジック
                  if (fixedIcon != null)
                    Icon(fixedIcon, size: 48, color: fixedColor)
                  else if (site.iconUrl != null && site.iconUrl!.isNotEmpty)
                    Image.network(
                      site.iconUrl!,
                      width: 48,
                      height: 48,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.public, size: 48, color: Colors.blueGrey);
                      },
                    )
                  else
                    const Icon(Icons.public, size: 48, color: Colors.blueGrey),

                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      site.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // 【変更】編集ボタン
            if (isEditable)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.edit, size: 20, color: Colors.grey), // アイコンを編集マークに変更
                  tooltip: "編集",
                  onPressed: () => _showEditDialog(context, site),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 【追加】編集・削除ダイアログ
  void _showEditDialog(BuildContext context, SiteModel site) {
    final nameController = TextEditingController(text: site.name);
    final urlController = TextEditingController(text: site.url);
    final SiteManager siteManager = SiteManager();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("サイト編集"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "サイト名", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(labelText: "URL", border: OutlineInputBorder()),
                keyboardType: TextInputType.url,
                maxLines: 3,
                minLines: 1,
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween, // ボタンを左右に配置
        actions: [
          // 削除ボタン (赤色)
          TextButton(
            onPressed: () {
              siteManager.removeSite(site.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("削除しました")));
            },
            child: const Text("削除", style: TextStyle(color: Colors.red)),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("キャンセル"),
              ),
              const SizedBox(width: 8),
              // 更新ボタン
              ElevatedButton(
                onPressed: () {
                  final newName = nameController.text.trim();
                  final newUrl = urlController.text.trim();
                  if (newName.isNotEmpty && newUrl.isNotEmpty) {
                    siteManager.updateSite(site.id, newName, newUrl);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("更新しました")));
                  }
                },
                child: const Text("保存"), // 「追加」ではなく「保存」
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openUrl(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("URLを開けませんでした: $url")));
      }
    }
  }
}