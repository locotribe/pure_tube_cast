class LocalPlaylistItem {
  final String id;
  String title;
  final String originalUrl;
  String? streamUrl; // 追加
  String? thumbnailUrl;
  String durationStr;

  // 状態管理用フィールド (finalを外して書き換え可能にする)
  bool isPlaying;
  bool isQueued;
  bool isResolving;
  bool hasError; // 追加
  DateTime lastResolved; // 追加

  LocalPlaylistItem({
    required this.id,
    required this.title,
    required this.originalUrl,
    this.streamUrl,
    this.thumbnailUrl,
    this.durationStr = "",
    this.isPlaying = false,
    this.isQueued = false,
    this.isResolving = false,
    this.hasError = false,
    DateTime? lastResolved,
  }) : lastResolved = lastResolved ?? DateTime.fromMillisecondsSinceEpoch(0);

  // JSON変換
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'originalUrl': originalUrl,
    'streamUrl': streamUrl,
    'thumbnailUrl': thumbnailUrl,
    'durationStr': durationStr,
    // 状態系は保存しない（起動時にリセットされるため）
  };

  factory LocalPlaylistItem.fromJson(Map<String, dynamic> json) {
    return LocalPlaylistItem(
      id: json['id'] ?? '',
      title: json['title'] ?? 'No Title',
      originalUrl: json['originalUrl'] ?? '',
      streamUrl: json['streamUrl'], // キャッシュがあれば復元しても良い
      thumbnailUrl: json['thumbnailUrl'],
      durationStr: json['durationStr'] ?? '',
    );
  }
}