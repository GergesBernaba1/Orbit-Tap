import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/device_contact.dart';
import '../models/hidden_folder_entry.dart';
import '../models/installed_app.dart';
import '../models/picked_vault_file.dart';
import '../models/vault_item.dart';
import 'security_service.dart';

class ImportVaultResult {
  const ImportVaultResult({
    required this.items,
    required this.importedCount,
    this.failedSourcePaths = const [],
  });

  final List<VaultItem> items;
  final int importedCount;
  final List<String> failedSourcePaths;
}

class VaultRepository {
  final Uuid _uuid = const Uuid();
  final AesGcm _aesGcm = AesGcm.with256bits();

  Future<List<VaultItem>> loadItems(SecurityService securityService) async {
    final indexFile = await _indexFile();
    if (!await indexFile.exists()) {
      return const [];
    }

    final encrypted = await indexFile.readAsBytes();
    final clearBytes = await _decryptBytes(
      encrypted,
      securityService.requireSessionKey(),
    );
    final decoded = jsonDecode(utf8.decode(clearBytes)) as List<dynamic>;

    return decoded
        .map((item) => VaultItem.fromJson(item as Map<String, dynamic>))
        .toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  Future<ImportVaultResult> importMedia({
    required SecurityService securityService,
    required List<PickedVaultFile> sourceFiles,
    required VaultItemType type,
    required List<VaultItem> currentItems,
  }) async {
    final secretKey = securityService.requireSessionKey();
    final filesDir = await _filesDir();
    final updated = List<VaultItem>.from(currentItems);
    var importedCount = 0;

    for (final sourceFile in sourceFiles) {
      final id = _uuid.v4();
      final originalName = sourceFile.displayName;
      final encryptedBytes = await _encryptBytes(sourceFile.bytes, secretKey);
      final payloadPath = path.join(filesDir.path, '$id.vlt');
      await File(payloadPath).writeAsBytes(encryptedBytes, flush: true);

      updated.add(
        VaultItem(
          id: id,
          type: type,
          title: path.basenameWithoutExtension(originalName),
          subtitle: originalName,
          createdAt: DateTime.now(),
          sizeBytes: sourceFile.bytes.length,
          payloadPath: payloadPath,
          metadata: <String, dynamic>{
            'originalName': originalName,
            'extension': path.extension(originalName),
          },
        ),
      );
      importedCount += 1;
    }

    await _saveIndex(updated, secretKey);

    updated.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return ImportVaultResult(
      items: updated,
      importedCount: importedCount,
    );
  }

  Future<ImportVaultResult> importFolder({
    required SecurityService securityService,
    required String sourceRootPath,
    required List<VaultItem> currentItems,
  }) async {
    final rootDirectory = Directory(sourceRootPath);
    if (!await rootDirectory.exists()) {
      throw StateError('Selected folder does not exist.');
    }

    final allEntities = await rootDirectory.list(recursive: true, followLinks: false).toList();
    final sourceFiles = allEntities.whereType<File>().toList();
    if (sourceFiles.isEmpty) {
      throw StateError('Selected folder is empty.');
    }

    final secretKey = securityService.requireSessionKey();
    final updated = List<VaultItem>.from(currentItems);
    final folderId = _uuid.v4();
    final folderName = path.basename(sourceRootPath);
    final folderPayloadRoot = Directory(path.join((await _foldersDir()).path, folderId));
    await folderPayloadRoot.create(recursive: true);

    final entries = <Map<String, dynamic>>[];
    var totalBytes = 0;

    for (final sourceFile in sourceFiles) {
      final relativePath = path.relative(sourceFile.path, from: sourceRootPath);
      final originalBytes = await sourceFile.readAsBytes();
      final encryptedBytes = await _encryptBytes(originalBytes, secretKey);
      final payloadPath = path.join(folderPayloadRoot.path, '$relativePath.vlt');
      final payloadFile = File(payloadPath);
      await payloadFile.parent.create(recursive: true);
      await payloadFile.writeAsBytes(encryptedBytes, flush: true);

      final entry = HiddenFolderEntry(
        relativePath: relativePath,
        payloadPath: payloadPath,
        sizeBytes: originalBytes.length,
        extension: path.extension(sourceFile.path),
      );
      entries.add(entry.toJson());
      totalBytes += originalBytes.length;
    }

    updated.add(
      VaultItem(
        id: folderId,
        type: VaultItemType.folder,
        title: folderName,
        subtitle: '${sourceFiles.length} files',
        createdAt: DateTime.now(),
        sizeBytes: totalBytes,
        metadata: <String, dynamic>{
          'originalFolderName': folderName,
          'payloadRootPath': folderPayloadRoot.path,
          'fileCount': sourceFiles.length,
          'entries': entries,
        },
      ),
    );

    await _saveIndex(updated, secretKey);

    final failedSourcePaths = await _deleteSourceFiles(
      sourceFiles.map((file) => file.path).toList(),
    );
    if (failedSourcePaths.isEmpty) {
      await _deleteEmptyDirectoriesUnder(rootDirectory);
      if (await rootDirectory.exists()) {
        try {
          await rootDirectory.delete();
        } catch (_) {
          // Best effort only.
        }
      }
    }

    updated.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return ImportVaultResult(
      items: updated,
      importedCount: sourceFiles.length,
      failedSourcePaths: failedSourcePaths,
    );
  }

  List<HiddenFolderEntry> folderEntries(VaultItem item) {
    if (item.type != VaultItemType.folder) {
      return const [];
    }

    final rawEntries = item.metadata['entries'] as List<dynamic>? ?? const [];
    final entries = rawEntries
        .map((entry) => HiddenFolderEntry.fromJson((entry as Map<dynamic, dynamic>).cast<String, dynamic>()))
        .toList();
    entries.sort((left, right) => left.relativePath.compareTo(right.relativePath));
    return entries;
  }

  Future<Uint8List> readFolderEntryBytes({
    required SecurityService securityService,
    required HiddenFolderEntry entry,
  }) async {
    final encrypted = await File(entry.payloadPath).readAsBytes();
    return _decryptBytes(encrypted, securityService.requireSessionKey());
  }

  Future<void> restoreFolder({
    required SecurityService securityService,
    required VaultItem item,
    required String destinationDirectoryPath,
  }) async {
    if (item.type != VaultItemType.folder) {
      throw StateError('Item is not a hidden folder.');
    }

    final folderName = (item.metadata['originalFolderName'] as String?) ?? item.title;
    final restoreRoot = Directory(path.join(destinationDirectoryPath, folderName));
    await restoreRoot.create(recursive: true);

    for (final entry in folderEntries(item)) {
      final clearBytes = await readFolderEntryBytes(
        securityService: securityService,
        entry: entry,
      );
      final outputFile = File(path.join(restoreRoot.path, entry.relativePath));
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(clearBytes, flush: true);
    }
  }

  Future<List<VaultItem>> addContact({
    required SecurityService securityService,
    required DeviceContact contact,
    required List<VaultItem> currentItems,
  }) async {
    final updated = List<VaultItem>.from(currentItems);

    updated.add(
      VaultItem(
        id: _uuid.v4(),
        type: VaultItemType.contact,
        title: contact.displayName,
        subtitle: contact.phones.isNotEmpty
            ? contact.phones.first
            : (contact.emails.isNotEmpty ? contact.emails.first : 'No details'),
        createdAt: DateTime.now(),
        metadata: contact.toJson(),
      ),
    );

    await _saveIndex(updated, securityService.requireSessionKey());
    return updated..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  Future<List<VaultItem>> addPrivateApp({
    required SecurityService securityService,
    required InstalledAppModel app,
    required List<VaultItem> currentItems,
  }) async {
    final updated = List<VaultItem>.from(currentItems);
    final exists = updated.any(
      (item) =>
          item.type == VaultItemType.app &&
          item.metadata['packageName'] == app.packageName,
    );

    if (!exists) {
      updated.add(
        VaultItem(
          id: _uuid.v4(),
          type: VaultItemType.app,
          title: app.appName,
          subtitle: app.packageName,
          createdAt: DateTime.now(),
          metadata: <String, dynamic>{
            'appName': app.appName,
            'packageName': app.packageName,
          },
        ),
      );
      await _saveIndex(updated, securityService.requireSessionKey());
    }

    return updated..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  Future<List<VaultItem>> deleteItem({
    required SecurityService securityService,
    required VaultItem target,
    required List<VaultItem> currentItems,
  }) async {
    final updated = currentItems.where((item) => item.id != target.id).toList();

    if (target.type == VaultItemType.folder) {
      final payloadRootPath = target.metadata['payloadRootPath'] as String?;
      if (payloadRootPath != null) {
        final folderRoot = Directory(payloadRootPath);
        if (await folderRoot.exists()) {
          await folderRoot.delete(recursive: true);
        }
      }
    } else {
      final payloadPath = target.payloadPath;
      if (payloadPath != null) {
        final file = File(payloadPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }

    await _saveIndex(updated, securityService.requireSessionKey());
    return updated..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  Future<Uint8List> readMediaBytes({
    required SecurityService securityService,
    required VaultItem item,
  }) async {
    final payloadPath = item.payloadPath;
    if (payloadPath == null) {
      throw StateError('Item does not contain media bytes.');
    }

    final encrypted = await File(payloadPath).readAsBytes();
    return _decryptBytes(encrypted, securityService.requireSessionKey());
  }

  Future<File> _indexFile() async {
    final root = await _vaultRoot();
    return File(path.join(root.path, 'index.vlt'));
  }

  Future<Directory> _filesDir() async {
    final root = await _vaultRoot();
    final filesDir = Directory(path.join(root.path, 'files'));
    if (!await filesDir.exists()) {
      await filesDir.create(recursive: true);
    }
    return filesDir;
  }

  Future<Directory> _foldersDir() async {
    final root = await _vaultRoot();
    final foldersDir = Directory(path.join(root.path, 'folders'));
    if (!await foldersDir.exists()) {
      await foldersDir.create(recursive: true);
    }
    return foldersDir;
  }

  Future<Directory> _vaultRoot() async {
    final baseDir = await getApplicationSupportDirectory();
    final root = Directory(path.join(baseDir.path, 'hidden_vault'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }

    final noMediaFile = File(path.join(root.path, '.nomedia'));
    if (!await noMediaFile.exists()) {
      await noMediaFile.writeAsString('');
    }

    return root;
  }

  Future<void> _saveIndex(List<VaultItem> items, SecretKey secretKey) async {
    final indexFile = await _indexFile();
    final clearBytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(items.map((item) => item.toJson()).toList()),
      ),
    );
    final encrypted = await _encryptBytes(clearBytes, secretKey);
    await indexFile.writeAsBytes(encrypted, flush: true);
  }

  Future<List<String>> _deleteSourceFiles(List<String> sourcePaths) async {
    final failedSourcePaths = <String>[];
    for (final sourcePath in sourcePaths) {
      final sourceFile = File(sourcePath);
      try {
        if (await sourceFile.exists()) {
          await sourceFile.delete();
        }
      } catch (_) {
        failedSourcePaths.add(sourcePath);
      }
    }
    return failedSourcePaths;
  }

  Future<void> _deleteEmptyDirectoriesUnder(Directory rootDirectory) async {
    final allDirectories = await rootDirectory
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is Directory)
        .cast<Directory>()
        .toList();

    allDirectories.sort(
      (left, right) => right.path.length.compareTo(left.path.length),
    );

    for (final directory in allDirectories) {
      try {
        final children = await directory.list(followLinks: false).toList();
        if (children.isEmpty) {
          await directory.delete();
        }
      } catch (_) {
        // Best effort only.
      }
    }
  }

  Future<Uint8List> _encryptBytes(List<int> clearBytes, SecretKey secretKey) async {
    final nonce = _randomBytes(12);
    final secretBox = await _aesGcm.encrypt(
      clearBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    return Uint8List.fromList(
      <int>[
        ...nonce,
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ],
    );
  }

  Future<Uint8List> _decryptBytes(List<int> encryptedBytes, SecretKey secretKey) async {
    if (encryptedBytes.length < 29) {
      throw StateError('Encrypted payload is invalid.');
    }

    final nonce = encryptedBytes.sublist(0, 12);
    final macBytes = encryptedBytes.sublist(encryptedBytes.length - 16);
    final cipherText = encryptedBytes.sublist(12, encryptedBytes.length - 16);

    final clearBytes = await _aesGcm.decrypt(
      SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(macBytes),
      ),
      secretKey: secretKey,
    );

    return Uint8List.fromList(clearBytes);
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
