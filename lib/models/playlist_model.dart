// lib/models/playlist_model.dart
import 'local_playlist_item.dart';

class PlaylistModel {
  final String id;
  String name;
  final List<LocalPlaylistItem> items;
  int lastPlayedIndex; // 【追加】最後に再生したインデックス
  String? remoteSourceId; // 【追加】YouTube等のソースID

  PlaylistModel({
    required this.id,
    required this.name,
    List<LocalPlaylistItem>? items,
    this.lastPlayedIndex = 0, // 【追加】初期値0
    this.remoteSourceId,
  }) : items = items ?? [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'items': items.map((e) => e.toJson()).toList(),
      'lastPlayedIndex': lastPlayedIndex, // 【追加】保存
      'remoteSourceId': remoteSourceId, // 【追加】
    };
  }

  factory PlaylistModel.fromJson(Map<String, dynamic> json) {
    return PlaylistModel(
      id: json['id'],
      name: json['name'],
      items: (json['items'] as List?)
          ?.map((e) => LocalPlaylistItem.fromJson(e))
          .toList() ?? [],
      lastPlayedIndex: json['lastPlayedIndex'] ?? 0, // 【追加】復元
      remoteSourceId: json['remoteSourceId'], // 【追加】
    );
  }
}