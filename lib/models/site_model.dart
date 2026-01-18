class SiteModel {
  final String id;
  final String name;
  final String url;
  final String? iconUrl; // 【追加】アイコン画像のURL

  SiteModel({
    required this.id,
    required this.name,
    required this.url,
    this.iconUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'iconUrl': iconUrl, // 【追加】
    };
  }

  factory SiteModel.fromJson(Map<String, dynamic> json) {
    return SiteModel(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      iconUrl: json['iconUrl'] as String?, // 【追加】
    );
  }
}