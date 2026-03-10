enum VaultItemType { image, video, contact, app }

class VaultItem {
  const VaultItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    required this.metadata,
    this.sizeBytes,
    this.payloadPath,
  });

  final String id;
  final VaultItemType type;
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final int? sizeBytes;
  final String? payloadPath;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'subtitle': subtitle,
      'createdAt': createdAt.toIso8601String(),
      'sizeBytes': sizeBytes,
      'payloadPath': payloadPath,
      'metadata': metadata,
    };
  }

  factory VaultItem.fromJson(Map<String, dynamic> json) {
    return VaultItem(
      id: json['id'] as String,
      type: VaultItemType.values.byName(json['type'] as String),
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      sizeBytes: json['sizeBytes'] as int?,
      payloadPath: json['payloadPath'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }
}
