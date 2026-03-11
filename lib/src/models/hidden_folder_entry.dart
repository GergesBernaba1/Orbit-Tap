import 'package:path/path.dart' as path;

class HiddenFolderEntry {
  const HiddenFolderEntry({
    required this.relativePath,
    required this.payloadPath,
    required this.sizeBytes,
    required this.extension,
  });

  final String relativePath;
  final String payloadPath;
  final int sizeBytes;
  final String extension;

  String get name => path.basename(relativePath);
  String get directory => path.dirname(relativePath) == '.' ? '' : path.dirname(relativePath);

  bool get isImage => const {
        '.jpg',
        '.jpeg',
        '.png',
        '.gif',
        '.webp',
        '.bmp',
        '.heic',
      }.contains(extension.toLowerCase());

  bool get isText => const {
        '.txt',
        '.md',
        '.json',
        '.csv',
        '.log',
        '.xml',
        '.yaml',
        '.yml',
      }.contains(extension.toLowerCase());

  bool get isPdf => extension.toLowerCase() == '.pdf';

  bool get isVideo => const {
        '.mp4',
        '.mov',
        '.mkv',
        '.avi',
        '.webm',
        '.m4v',
      }.contains(extension.toLowerCase());

  Map<String, dynamic> toJson() {
    return {
      'relativePath': relativePath,
      'payloadPath': payloadPath,
      'sizeBytes': sizeBytes,
      'extension': extension,
    };
  }

  factory HiddenFolderEntry.fromJson(Map<String, dynamic> json) {
    return HiddenFolderEntry(
      relativePath: json['relativePath'] as String,
      payloadPath: json['payloadPath'] as String,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      extension: (json['extension'] as String?) ?? path.extension(json['relativePath'] as String),
    );
  }
}
