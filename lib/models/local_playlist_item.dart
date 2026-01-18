import 'dart:math';

// 再生リストのアイテム情報
class LocalPlaylistItem {
  final String id;
  final String title;
  final String originalUrl;
  final String? streamUrl;
  final String? thumbnailUrl;
  final String durationStr;

  bool isResolving;
  bool hasError;

  LocalPlaylistItem({
    String? id,
    required this.title,
    required this.originalUrl,
    this.streamUrl,
    this.thumbnailUrl,
    this.durationStr = "--:--",
    this.isResolving = false,
    this.hasError = false,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString() + Random().nextInt(1000).toString();

  LocalPlaylistItem copyWith({
    String? streamUrl,
    bool? isResolving,
    bool? hasError,
  }) {
    return LocalPlaylistItem(
      id: id,
      title: title,
      originalUrl: originalUrl,
      thumbnailUrl: thumbnailUrl,
      durationStr: durationStr,
      streamUrl: streamUrl ?? this.streamUrl,
      isResolving: isResolving ?? this.isResolving,
      hasError: hasError ?? this.hasError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'originalUrl': originalUrl,
      'streamUrl': streamUrl,
      'thumbnailUrl': thumbnailUrl,
      'durationStr': durationStr,
      'isResolving': false,
      'hasError': hasError,
    };
  }

  factory LocalPlaylistItem.fromJson(Map<String, dynamic> json) {
    return LocalPlaylistItem(
      id: json['id'],
      title: json['title'],
      originalUrl: json['originalUrl'],
      streamUrl: json['streamUrl'],
      thumbnailUrl: json['thumbnailUrl'],
      durationStr: json['durationStr'] ?? "--:--",
      isResolving: false,
      hasError: json['hasError'] ?? false,
    );
  }
}