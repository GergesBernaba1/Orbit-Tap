import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/device_contact.dart';
import '../models/hidden_folder_entry.dart';
import '../models/installed_app.dart';
import '../models/picked_vault_file.dart';
import '../models/vault_item.dart';
import '../services/android_source_access_service.dart';
import '../services/contact_service.dart';
import '../services/media_export_service.dart';
import '../services/private_apps_service.dart';
import '../services/security_service.dart';
import '../services/shared_media_removal_service.dart';
import '../services/vault_repository.dart';

enum AppStage { loading, onboarding, decoy, ready }

class VaultController extends ChangeNotifier {
  VaultController({
    required SecurityService securityService,
    required VaultRepository vaultRepository,
    required ContactService contactService,
    required PrivateAppsService privateAppsService,
    required MediaExportService mediaExportService,
    required SharedMediaRemovalService sharedMediaRemovalService,
    required AndroidSourceAccessService androidSourceAccessService,
  })  : _securityService = securityService,
        _vaultRepository = vaultRepository,
        _contactService = contactService,
        _privateAppsService = privateAppsService,
        _mediaExportService = mediaExportService,
        _sharedMediaRemovalService = sharedMediaRemovalService,
        _androidSourceAccessService = androidSourceAccessService;

  final SecurityService _securityService;
  final VaultRepository _vaultRepository;
  final ContactService _contactService;
  final PrivateAppsService _privateAppsService;
  final MediaExportService _mediaExportService;
  final SharedMediaRemovalService _sharedMediaRemovalService;
  final AndroidSourceAccessService _androidSourceAccessService;

  AppStage _stage = AppStage.loading;
  bool _busy = false;
  String? _errorMessage;
  List<VaultItem> _items = const [];

  AppStage get stage => _stage;
  bool get busy => _busy;
  String? get errorMessage => _errorMessage;
  bool get appsFeatureSupported => _privateAppsService.isSupported;
  List<VaultItem> get items => List.unmodifiable(_items);

  List<VaultItem> itemsFor(VaultItemType type) =>
      _items.where((item) => item.type == type).toList();

  int countFor(VaultItemType type) => itemsFor(type).length;

  List<HiddenFolderEntry> folderEntries(VaultItem item) {
    return _vaultRepository.folderEntries(item);
  }

  Future<void> initialize() async {
    _setBusy(true);
    try {
      await _securityService.load();
      _stage = _securityService.needsSetup ? AppStage.onboarding : AppStage.decoy;
    } catch (error) {
      _errorMessage = 'Failed to initialize vault: $error';
      _stage = AppStage.onboarding;
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> setupPasscode(String passcode) async {
    return _runGuarded<bool>(() async {
      await _securityService.setupPasscode(passcode);
      await _reloadItems();
      _stage = AppStage.ready;
      notifyListeners();
      return true;
    }, fallback: false);
  }

  Future<bool> unlock(String passcode) async {
    return _runGuarded<bool>(() async {
      final unlocked = await _securityService.unlockWithPasscode(passcode);
      if (!unlocked) {
        _errorMessage = 'Wrong passcode.';
        notifyListeners();
        return false;
      }

      await _reloadItems();
      _stage = AppStage.ready;
      notifyListeners();
      return true;
    }, fallback: false);
  }

  Future<void> lock() async {
    _securityService.lock();
    _items = const [];
    _stage = AppStage.decoy;
    notifyListeners();
  }

  Future<bool> tryDecoyCode(String code) async {
    if (code.trim().isEmpty) {
      return false;
    }

    _setBusy(true);
    try {
      final unlocked = await _securityService.unlockWithPasscode(code.trim());
      if (!unlocked) {
        return false;
      }

      await _reloadItems();
      _stage = AppStage.ready;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> importImages() => _importMedia(
        VaultItemType.image,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'],
      );

  Future<void> importVideos() => _importMedia(
        VaultItemType.video,
        allowedExtensions: const ['mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v'],
      );

  Future<void> importFolder() async {
    await _runGuardedVoid(() async {
      final folderPath = await FilePicker.platform.getDirectoryPath();
      if (folderPath == null || folderPath.trim().isEmpty) {
        return;
      }

      final importResult = await _vaultRepository.importFolder(
        securityService: _securityService,
        sourceRootPath: folderPath,
        currentItems: _items,
      );
      _items = importResult.items;

      if (importResult.importedCount > 0 && importResult.failedSourcePaths.isNotEmpty) {
        _errorMessage =
            'Hidden folder with ${importResult.importedCount} file(s), but ${importResult.failedSourcePaths.length} original file(s) could not be removed from shared storage.';
      }

      notifyListeners();
    });
  }

  Future<List<DeviceContact>> loadDeviceContacts() async {
    final granted = await _contactService.requestPermission();
    if (!granted) {
      throw StateError('Contacts permission was denied.');
    }
    return _contactService.fetchContacts();
  }

  Future<void> addHiddenContact(DeviceContact contact) async {
    await _runGuardedVoid(() async {
      _items = await _vaultRepository.addContact(
        securityService: _securityService,
        contact: contact,
        currentItems: _items,
      );
      notifyListeners();
    });
  }

  Future<List<InstalledAppModel>> loadInstalledApps() {
    return _privateAppsService.fetchInstalledApps();
  }

  Future<void> addPrivateApp(InstalledAppModel app) async {
    await _runGuardedVoid(() async {
      _items = await _vaultRepository.addPrivateApp(
        securityService: _securityService,
        app: app,
        currentItems: _items,
      );
      notifyListeners();
    });
  }

  Future<void> deleteItem(VaultItem item) async {
    await _runGuardedVoid(() async {
      _items = await _vaultRepository.deleteItem(
        securityService: _securityService,
        target: item,
        currentItems: _items,
      );
      notifyListeners();
    });
  }

  Future<Uint8List> readMediaBytes(VaultItem item) {
    return _vaultRepository.readMediaBytes(
      securityService: _securityService,
      item: item,
    );
  }

  Future<Uint8List> readFolderEntryBytes(HiddenFolderEntry entry) {
    return _vaultRepository.readFolderEntryBytes(
      securityService: _securityService,
      entry: entry,
    );
  }

  Future<String> unhideMedia(VaultItem item) async {
    if (item.type != VaultItemType.image && item.type != VaultItemType.video) {
      return 'Only images and videos can be restored to the gallery.';
    }

    _setBusy(true);
    _errorMessage = null;
    try {
      final bytes = await _vaultRepository.readMediaBytes(
        securityService: _securityService,
        item: item,
      );
      final saved = await _mediaExportService.unhideToGallery(
        item: item,
        bytes: bytes,
      );
      if (!saved) {
        return 'Could not restore ${item.title} to the gallery.';
      }

      _items = await _vaultRepository.deleteItem(
        securityService: _securityService,
        target: item,
        currentItems: _items,
      );
      notifyListeners();
      return '${item.title} was restored to the gallery and removed from the vault.';
    } catch (error) {
      return error.toString().replaceFirst('Exception: ', '');
    } finally {
      _setBusy(false);
    }
  }

  Future<String> unhideFolder(VaultItem item) async {
    if (item.type != VaultItemType.folder) {
      return 'Only hidden folders can be restored here.';
    }

    _setBusy(true);
    _errorMessage = null;
    try {
      final destinationPath = await FilePicker.platform.getDirectoryPath();
      if (destinationPath == null || destinationPath.trim().isEmpty) {
        return 'Folder restore canceled.';
      }

      await _vaultRepository.restoreFolder(
        securityService: _securityService,
        item: item,
        destinationDirectoryPath: destinationPath,
      );
      _items = await _vaultRepository.deleteItem(
        securityService: _securityService,
        target: item,
        currentItems: _items,
      );
      notifyListeners();
      return '${item.title} was restored and removed from the vault.';
    } catch (error) {
      return error.toString().replaceFirst('Exception: ', '');
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> openPrivateApp(VaultItem item) async {
    final packageName = item.metadata['packageName'] as String?;
    if (packageName == null) {
      return false;
    }
    return _privateAppsService.openApp(packageName);
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _reloadItems() async {
    _items = await _vaultRepository.loadItems(_securityService);
  }

  Future<void> _importMedia(
    VaultItemType type, {
    required List<String> allowedExtensions,
  }) async {
    await _runGuardedVoid(() async {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        withData: true,
      );
      final selectedFiles = await _buildPickedVaultFiles(result?.files ?? const []);

      if (selectedFiles.isEmpty) {
        return;
      }

      final importResult = await _vaultRepository.importMedia(
        securityService: _securityService,
        sourceFiles: selectedFiles,
        type: type,
        currentItems: _items,
      );
      _items = importResult.items;

      final candidatesWithIdentifier = selectedFiles
          .where((file) => (file.sourceIdentifier ?? '').trim().isNotEmpty)
          .toList();
      final failedIdentifiers = await _androidSourceAccessService.deleteSourceIdentifiers(
        candidatesWithIdentifier
            .map((file) => file.sourceIdentifier!.trim())
            .toList(),
      );

      final unresolvedFiles = selectedFiles.where((file) {
        final identifier = file.sourceIdentifier?.trim();
        if (identifier == null || identifier.isEmpty) {
          return true;
        }
        return failedIdentifiers.contains(identifier);
      }).toList();

      final fallbackPaths = unresolvedFiles
          .map((file) => file.sourcePath)
          .whereType<String>()
          .where((path) => path.trim().isNotEmpty)
          .toList();

      final pathCandidatesWithoutDirectDelete = unresolvedFiles.length - fallbackPaths.length;
      var remainingFailures = pathCandidatesWithoutDirectDelete;
      if (fallbackPaths.isNotEmpty) {
        remainingFailures += await _sharedMediaRemovalService.removeFromSharedGallery(
          sourcePaths: fallbackPaths,
          type: type,
        );
      }

      if (importResult.importedCount > 0 && remainingFailures > 0) {
        _errorMessage =
            'Moved ${importResult.importedCount} file(s) into the encrypted vault, but ${remainingFailures} original file(s) may still be visible because Android did not grant full removal access.';
      }

      notifyListeners();
    });
  }

  Future<List<PickedVaultFile>> _buildPickedVaultFiles(List<PlatformFile> files) async {
    final selectedFiles = <PickedVaultFile>[];

    for (final file in files) {
      final bytes = file.bytes ?? await _readPlatformFileBytes(file);
      if (bytes == null || bytes.isEmpty) {
        continue;
      }

      final displayName = file.name.trim().isEmpty
          ? ((file.path != null && file.path!.trim().isNotEmpty)
              ? file.path!.split(Platform.pathSeparator).last
              : 'hidden_file')
          : file.name.trim();

      selectedFiles.add(
        PickedVaultFile(
          displayName: displayName,
          bytes: bytes,
          sourcePath: file.path,
          sourceIdentifier: file.identifier,
        ),
      );
    }

    return selectedFiles;
  }

  Future<Uint8List?> _readPlatformFileBytes(PlatformFile file) async {
    final filePath = file.path;
    if (filePath == null || filePath.trim().isEmpty) {
      return null;
    }

    final sourceFile = File(filePath);
    if (!await sourceFile.exists()) {
      return null;
    }

    return sourceFile.readAsBytes();
  }

  Future<T> _runGuarded<T>(
    Future<T> Function() action, {
    required T fallback,
  }) async {
    _setBusy(true);
    _errorMessage = null;
    try {
      return await action();
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return fallback;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _runGuardedVoid(Future<void> Function() action) async {
    _setBusy(true);
    _errorMessage = null;
    try {
      await action();
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }
}
