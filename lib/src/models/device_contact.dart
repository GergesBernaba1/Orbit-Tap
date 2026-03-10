class DeviceContact {
  const DeviceContact({
    required this.id,
    required this.displayName,
    required this.phones,
    required this.emails,
  });

  final String id;
  final String displayName;
  final List<String> phones;
  final List<String> emails;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'phones': phones,
      'emails': emails,
    };
  }

  factory DeviceContact.fromJson(Map<String, dynamic> json) {
    return DeviceContact(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      phones: (json['phones'] as List<dynamic>).cast<String>(),
      emails: (json['emails'] as List<dynamic>).cast<String>(),
    );
  }
}
