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

              // YouTubeを先頭に追加したリストを作る
              // ※ データ上の保存はしないが、表示上は「特別なサイト」として扱う

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, // 2列
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.3, // 横長カード
                ),
                // YouTube(1つ) + 登録サイト数
                itemCount: 1 + sites.length,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // 0番目は必ずYouTube
                    return _buildSiteCard(
                      context,
                      name: "YouTube",
                      url: "https://www.youtube.com",
                      icon: Icons.play_circle_fill,
                      color: Colors.red,
                      isDeletable: false,
                    );
                  } else {
                    final site = sites[index - 1];
                    return _buildSiteCard(
                      context,
                      name: site.name,
                      url: site.url,
                      icon: Icons.public,
                      color: Colors.blueGrey,
                      isDeletable: true,
                      onDelete: () => siteManager.removeSite(site.id),
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
        required String name,
        required String url,
        required IconData icon,
        required Color color,
        required bool isDeletable,
        VoidCallback? onDelete,
      }) {
    return InkWell(
      onTap: () => _openUrl(context, url),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
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
                  Icon(icon, size: 48, color: color),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isDeletable && onDelete != null)
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  onPressed: onDelete,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openUrl(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("URLを開けませんでした: $url")),
        );
      }
    }
  }
}