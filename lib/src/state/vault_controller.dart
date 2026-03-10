import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/device_contact.dart';
import '../models/installed_app.dart';
import '../models/vault_item.dart';
import '../services/contact_service.dart';
import '../services/private_apps_service.dart';
import '../services/security_service.dart';
import '../services/vault_repository.dart';

enum AppStage { loading, onboarding, decoy, ready }

class VaultController extends ChangeNotifier {
  VaultController({
    required SecurityService securityService,
    required VaultRepository vaultRepository,
    required ContactService contactService,
    required PrivateAppsService privateAppsService,
  })  : _securityService = securityService,
        _vaultRepository = vaultRepository,
        _contactService = contactService,
        _privateAppsService = privateAppsService;

  final SecurityService _securityService;
  final VaultRepository _vaultRepository;
  final ContactService _contactService;
  final PrivateAppsService _privateAppsService;

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
      );
      final selectedPaths = result?.paths.whereType<String>().toList() ?? const [];
      final existingPaths =
          selectedPaths.where((filePath) => File(filePath).existsSync()).toList();

      if (existingPaths.isEmpty) {
        return;
      }

      _items = await _vaultRepository.importMedia(
        securityService: _securityService,
        sourcePaths: existingPaths,
        type: type,
        currentItems: _items,
      );
      notifyListeners();
    });
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
