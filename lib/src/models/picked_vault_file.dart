import 'dart:typed_data';

class PickedVaultFile {
  const PickedVaultFile({
    required this.displayName,
    required this.bytes,
    this.sourcePath,
    this.sourceIdentifier,
  });

  final String displayName;
  final Uint8List bytes;
  final String? sourcePath;
  final String? sourceIdentifier;
}
