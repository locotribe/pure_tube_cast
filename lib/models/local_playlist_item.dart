class LocalPlaylistItem {
  final String id;
  final String title;
  final String originalUrl;
  final String? thumbnailUrl;
  final String durationStr;
  final String? streamUrl;

  // 状態フラグ
  final bool isResolving; // 解析中
  final bool hasError;    // エラー
  final bool isQueued;    // 送信済み
  final bool isPlaying;   // 【追加】再生中

  LocalPlaylistItem({
    String? id,
    required this.title,
    required this.originalUrl,
    this.thumbnailUrl,
    required this.durationStr,
    this.streamUrl,
    this.isResolving = false,
    this.hasError = false,
    this.isQueued = false,
    this.isPlaying = false, // 【追加】初期値false
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  LocalPlaylistItem copyWith({
    String? title,
    String? originalUrl,
    String? thumbnailUrl,
    String? durationStr,
    String? streamUrl,
    bool? isResolving,
    bool? hasError,
    bool? isQueued,
    bool? isPlaying, // 【追加】
  }) {
    return LocalPlaylistItem(
      id: id,
      title: title ?? this.title,
      originalUrl: originalUrl ?? this.originalUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationStr: durationStr ?? this.durationStr,
      streamUrl: streamUrl ?? this.streamUrl,
      isResolving: isResolving ?? this.isResolving,
      hasError: hasError ?? this.hasError,
      isQueued: isQueued ?? this.isQueued,
      isPlaying: isPlaying ?? this.isPlaying, // 【追加】
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'originalUrl': originalUrl,
      'thumbnailUrl': thumbnailUrl,
      'durationStr': durationStr,
      'streamUrl': streamUrl,
      'isResolving': isResolving,
      'hasError': hasError,
      // isQueued, isPlaying は一時的な状態なので保存しない
    };
  }

  factory LocalPlaylistItem.fromJson(Map<String, dynamic> json) {
    return LocalPlaylistItem(
      id: json['id'],
      title: json['title'],
      originalUrl: json['originalUrl'],
      thumbnailUrl: json['thumbnailUrl'],
      durationStr: json['durationStr'] ?? "--:--",
      streamUrl: json['streamUrl'],
      isResolving: json['isResolving'] ?? false,
      hasError: json['hasError'] ?? false,
      isQueued: false,
      isPlaying: false,
    );
  }
}