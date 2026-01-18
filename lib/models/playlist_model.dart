import 'local_playlist_item.dart';

class PlaylistModel {
  final String id;
  String name;
  final List<LocalPlaylistItem> items;

  PlaylistModel({
    required this.id,
    required this.name,
    List<LocalPlaylistItem>? items,
  }) : items = items ?? [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'items': items.map((e) => e.toJson()).toList(),
    };
  }

  factory PlaylistModel.fromJson(Map<String, dynamic> json) {
    return PlaylistModel(
      id: json['id'],
      name: json['name'],
      items: (json['items'] as List?)
          ?.map((e) => LocalPlaylistItem.fromJson(e))
          .toList() ?? [],
    );
  }
}