import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/device_contact.dart';
import '../models/installed_app.dart';
import '../models/vault_item.dart';
import 'security_service.dart';

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

  Future<List<VaultItem>> importMedia({
    required SecurityService securityService,
    required List<String> sourcePaths,
    required VaultItemType type,
    required List<VaultItem> currentItems,
  }) async {
    final secretKey = securityService.requireSessionKey();
    final filesDir = await _filesDir();
    final updated = List<VaultItem>.from(currentItems);

    for (final sourcePath in sourcePaths) {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        continue;
      }

      final id = _uuid.v4();
      final originalName = path.basename(sourcePath);
      final originalBytes = await sourceFile.readAsBytes();
      final encryptedBytes = await _encryptBytes(originalBytes, secretKey);
      final payloadPath = path.join(filesDir.path, '$id.vlt');
      await File(payloadPath).writeAsBytes(encryptedBytes, flush: true);

      updated.add(
        VaultItem(
          id: id,
          type: type,
          title: path.basenameWithoutExtension(originalName),
          subtitle: originalName,
          createdAt: DateTime.now(),
          sizeBytes: originalBytes.length,
          payloadPath: payloadPath,
          metadata: <String, dynamic>{
            'originalName': originalName,
            'extension': path.extension(originalName),
          },
        ),
      );
    }

    await _saveIndex(updated, secretKey);
    return updated..sort((left, right) => right.createdAt.compareTo(left.createdAt));
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
    final payloadPath = target.payloadPath;
    if (payloadPath != null) {
      final file = File(payloadPath);
      if (await file.exists()) {
        await file.delete();
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

  Future<Directory> _vaultRoot() async {
    final baseDir = await getApplicationSupportDirectory();
    final root = Directory(path.join(baseDir.path, 'hidden_vault'));
    if (!await root.exists()) {
      await root.create(recursive: true);
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
