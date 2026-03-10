import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/security_state.dart';

class SecurityService {
  static const _prefsKey = 'security_state_v1';

  final Sha256 _sha256 = Sha256();
  SecurityState? _state;
  SecretKey? _sessionKey;

  bool get needsSetup => _state == null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      _state = null;
      _sessionKey = null;
      return;
    }

    _state = SecurityState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    _sessionKey = null;
  }

  Future<void> setupPasscode(String passcode) async {
    final salt = _randomBytes(16);
    final keyBytes = await _deriveKeyBytes(
      passcode: passcode,
      salt: salt,
      iterations: 120000,
    );
    final verifier = await _sha256.hash(keyBytes);
    _state = SecurityState(
      saltBase64: base64Encode(salt),
      verifierBase64: base64Encode(verifier.bytes),
      iterations: 120000,
    );
    _sessionKey = SecretKey(keyBytes);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_state!.toJson()));
  }

  Future<bool> unlockWithPasscode(String passcode) async {
    final state = _state;
    if (state == null) {
      return false;
    }

    final salt = base64Decode(state.saltBase64);
    final keyBytes = await _deriveKeyBytes(
      passcode: passcode,
      salt: salt,
      iterations: state.iterations,
    );
    final verifier = await _sha256.hash(keyBytes);
    final matches = base64Encode(verifier.bytes) == state.verifierBase64;

    if (!matches) {
      _sessionKey = null;
      return false;
    }

    _sessionKey = SecretKey(keyBytes);
    return true;
  }

  SecretKey requireSessionKey() {
    final key = _sessionKey;
    if (key == null) {
      throw StateError('Vault is locked.');
    }
    return key;
  }

  void lock() {
    _sessionKey = null;
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  Future<Uint8List> _deriveKeyBytes({
    required String passcode,
    required List<int> salt,
    required int iterations,
  }) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final secretKey = await algorithm.deriveKeyFromPassword(
      password: passcode,
      nonce: salt,
    );
    return Uint8List.fromList(await secretKey.extractBytes());
  }
}
