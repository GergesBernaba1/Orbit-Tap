import 'dart:io';
import 'dart:typed_data';

import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/vault_item.dart';

class MediaExportService {
  Future<bool> unhideToGallery({
    required VaultItem item,
    required Uint8List bytes,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final extension = (item.metadata['extension'] as String?)?.trim().toLowerCase();
    final fallbackExtension = item.type == VaultItemType.video ? '.mp4' : '.jpg';
    final fileExtension =
        extension != null && extension.isNotEmpty ? extension : fallbackExtension;
    final fileName = '${item.id}$fileExtension';
    final tempPath = path.join(tempDir.path, fileName);
    final tempFile = File(tempPath);

    await tempFile.writeAsBytes(bytes, flush: true);

    try {
      if (item.type == VaultItemType.video) {
        return await GallerySaver.saveVideo(tempFile.path) ?? false;
      }
      return await GallerySaver.saveImage(tempFile.path) ?? false;
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }
}
