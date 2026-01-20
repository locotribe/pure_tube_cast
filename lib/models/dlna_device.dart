class DlnaDevice {
  final String ip;
  final String name;
  final String originalName;
  final String controlUrl;
  final String serviceType;
  final int port;
  final bool isManual;
  final String? macAddress;

  DlnaDevice({
    required this.ip,
    required this.name,
    required this.originalName,
    required this.controlUrl,
    required this.serviceType,
    required this.port,
    this.isManual = false,
    this.macAddress,
  });

  DlnaDevice copyWith({
    String? name,
    String? originalName,
    String? controlUrl,
    String? serviceType,
    int? port,
    bool? isManual,
    String? macAddress,
  }) {
    return DlnaDevice(
      ip: ip,
      name: name ?? this.name,
      originalName: originalName ?? this.originalName,
      controlUrl: controlUrl ?? this.controlUrl,
      serviceType: serviceType ?? this.serviceType,
      port: port ?? this.port,
      isManual: isManual ?? this.isManual,
      macAddress: macAddress ?? this.macAddress,
    );
  }
}

class KodiPlaylistItem {
  final String label;
  final String file;
  KodiPlaylistItem({required this.label, required this.file});

  factory KodiPlaylistItem.fromJson(Map<String, dynamic> json) {
    String name = json['title'] ?? '';
    if (name.isEmpty) {
      name = json['label'] ?? '';
    }
    return KodiPlaylistItem(
      label: name,
      file: json['file'] ?? '',
    );
  }
}