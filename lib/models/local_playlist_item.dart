class LocalPlaylistItem {
  final String id;
  final String title;
  final String originalUrl;
  final String? thumbnailUrl;
  final String durationStr;
  final String? streamUrl;

  // 状態フラグ
  final bool isResolving;
  final bool hasError;
  final bool isQueued;
  final bool isPlaying;

  // 【追加】重複防止用の静的カウンター
  static int _idCounter = 0;

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
    this.isPlaying = false,
    // 【修正】ミリ秒 + カウンター で完全にユニークなIDを作る
  }) : id = id ?? "${DateTime.now().millisecondsSinceEpoch}_${_idCounter++}";

  LocalPlaylistItem copyWith({
    String? title,
    String? originalUrl,
    String? thumbnailUrl,
    String? durationStr,
    String? streamUrl,
    bool? isResolving,
    bool? hasError,
    bool? isQueued,
    bool? isPlaying,
  }) {
    return LocalPlaylistItem(
      id: id, // IDはコピー元を維持
      title: title ?? this.title,
      originalUrl: originalUrl ?? this.originalUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationStr: durationStr ?? this.durationStr,
      streamUrl: streamUrl ?? this.streamUrl,
      isResolving: isResolving ?? this.isResolving,
      hasError: hasError ?? this.hasError,
      isQueued: isQueued ?? this.isQueued,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }

  // ... (toJson, fromJson は変更なし) ...
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