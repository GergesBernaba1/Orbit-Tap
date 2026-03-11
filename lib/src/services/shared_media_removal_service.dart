import 'dart:math';

import 'package:path/path.dart' as path;
import 'package:photo_manager/photo_manager.dart';

import '../models/vault_item.dart';

class SharedMediaRemovalService {
  Future<int> removeFromSharedGallery({
    required List<String> sourcePaths,
    required VaultItemType type,
  }) async {
    if (sourcePaths.isEmpty) {
      return 0;
    }

    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      return sourcePaths.length;
    }

    final requestType = type == VaultItemType.video ? RequestType.video : RequestType.image;
    final targets = sourcePaths.map(_GalleryTarget.fromSourcePath).toList();
    final matchedById = <String, _GalleryTarget>{};

    final totalCount = await PhotoManager.getAssetCount(type: requestType);
    const pageSize = 200;
    final maxToScan = min(totalCount, 2000);

    for (var start = 0; start < maxToScan && matchedById.length < targets.length; start += pageSize) {
      final end = min(start + pageSize, maxToScan);
      final assets = await PhotoManager.getAssetListRange(
        start: start,
        end: end,
        type: requestType,
      );

      for (final asset in assets) {
        final title = asset.title ?? '';
        final relativePath = _normalizeRelativePath(asset.relativePath ?? '');

        for (final target in targets) {
          if (matchedById.containsValue(target)) {
            continue;
          }
          if (target.matches(title: title, relativePath: relativePath)) {
            matchedById[asset.id] = target;
            break;
          }
        }
      }
    }

    if (matchedById.isEmpty) {
      return sourcePaths.length;
    }

    final deletedIds = await PhotoManager.editor.deleteWithIds(
      matchedById.keys.toList(),
    );

    return sourcePaths.length - deletedIds.length;
  }

  String _normalizeRelativePath(String value) {
    return value.replaceAll('\\', '/').replaceAll(RegExp('/+'), '/').toLowerCase();
  }
}

class _GalleryTarget {
  const _GalleryTarget({
    required this.fileName,
    required this.relativeDirectory,
  });

  factory _GalleryTarget.fromSourcePath(String sourcePath) {
    final fileName = path.basename(sourcePath).toLowerCase();
    var relativeDirectory = path.dirname(sourcePath).replaceAll('\\', '/').toLowerCase();
    final storageAnchor = '/storage/emulated/0/';
    if (relativeDirectory.contains(storageAnchor)) {
      relativeDirectory = relativeDirectory.split(storageAnchor).last;
    }
    return _GalleryTarget(
      fileName: fileName,
      relativeDirectory: relativeDirectory,
    );
  }

  final String fileName;
  final String relativeDirectory;

  bool matches({
    required String title,
    required String relativePath,
  }) {
    final normalizedTitle = title.toLowerCase();
    if (normalizedTitle != fileName) {
      return false;
    }

    if (relativeDirectory.isEmpty) {
      return true;
    }

    return relativePath.endsWith(relativeDirectory) ||
        relativeDirectory.endsWith(relativePath.replaceAll(RegExp('/+$'), ''));
  }
}
