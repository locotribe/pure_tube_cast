class SiteModel {
  final String id;
  final String name;
  final String url;

  SiteModel({
    required this.id,
    required this.name,
    required this.url,
  });

  // 保存用：JSONに変換
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
    };
  }

  // 復元用：JSONから変換
  factory SiteModel.fromJson(Map<String, dynamic> json) {
    return SiteModel(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
    );
  }
}