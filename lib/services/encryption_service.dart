import 'dart:convert';

import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fast_rsa/fast_rsa.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';

class EncryptionService {
  final _aes = cryptography.AesGcm.with256bits();
  final _secureStorage = const FlutterSecureStorage();

  String? _publicKeySerialized;
  String? _privateKeySerialized;
  String? _currentUserId;

  static const _storagePrivateKey = 'rsa_private_key_v2';
  static const _storagePublicKey = 'rsa_public_key_v2';

  Future<void> init(ApiService api) async {
    final userId = api.userId;
    if (userId == null) {
      if (kDebugMode) print('⚠️ [Encryption] init called but userId is NULL. Skipping.');
      return;
    }

    if (_publicKeySerialized != null && _currentUserId == userId) {
      if (kDebugMode) print('🔐 [Encryption] Already initialized for user $userId');
      return;
    }

    _currentUserId = userId;

    final privKeyName = '${_storagePrivateKey}_$userId';
    final pubKeyName = '${_storagePublicKey}_$userId';

    // Читаем из secure storage
    final storedPriv = await _secureStorage.read(key: privKeyName);
    final storedPub = await _secureStorage.read(key: pubKeyName);

    if (kDebugMode) print('🔐 [Encryption] Initializing for user: $userId');
    if (kDebugMode) print('🔐 [Encryption] Looking for keys: $privKeyName, $pubKeyName');
    if (kDebugMode) print('🔐 [Encryption] Found private: ${storedPriv != null}, public: ${storedPub != null}');

    if (storedPriv != null && storedPub != null) {
      if (kDebugMode) print('🔐 [Encryption] Stored keys found. (v2)');
      _privateKeySerialized = storedPriv;
      _publicKeySerialized = storedPub;
      if (kDebugMode) print('✅ [Encryption] Keys loaded from secure storage.');
    } else {
      if (kDebugMode) print('🔐 [Encryption] No stored keys (v2) for this user. Generating fast_rsa 2048 pair...');
      
      final keyPair = await RSA.generate(2048);
      
      _publicKeySerialized = keyPair.publicKey;
      _privateKeySerialized = keyPair.privateKey;

      if (kDebugMode) print('🔐 [Encryption] Keys generated instantly. Writing to secure storage for $userId...');
      await _secureStorage.write(key: pubKeyName, value: _publicKeySerialized!);
      await _secureStorage.write(key: privKeyName, value: _privateKeySerialized!);
      if (kDebugMode) print('✅ [Encryption] Keys saved to secure storage.');
    }

    if (_publicKeySerialized != null) {
      try {
        if (kDebugMode) print('📡 [Encryption] Syncing public key with server...');
        await api.postPublicKey(_publicKeySerialized!);
      } catch (e) {
        if (kDebugMode) print('⚠️ [Encryption] Could not sync key with server: $e');
      }
    }
  }

  String? get publicKeySerialized => _publicKeySerialized;

  Future<String?> encryptForPeer(String plaintext, String peerPublicKey) async {
    try {
      if (peerPublicKey.isEmpty) return null;

      final secretKey = await _aes.newSecretKey();
      final secretKeyBytes = await secretKey.extractBytes();
      final nonce = _aes.newNonce();

      final secretBox = await _aes.encrypt(
        utf8.encode(plaintext),
        secretKey: secretKey,
        nonce: nonce,
      );

      final encryptedKey = await RSA.encryptPKCS1v15Bytes(Uint8List.fromList(secretKeyBytes), peerPublicKey);

      final payload = {
        'v': 2,
        'alg': 'AES-256-GCM',
        'key': base64Encode(encryptedKey),
        'nonce': base64Encode(secretBox.nonce),
        'ciphertext': base64Encode(secretBox.cipherText),
        'mac': base64Encode(secretBox.mac.bytes),
      };

      return jsonEncode(payload);
    } catch (e) {
      if (kDebugMode) print('⚠️ [Encryption] Error encrypting: $e');
      return null;
    }
  }

  Future<String?> decryptMessage(String payload) async {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;

      final keyB64 = decoded['key']?.toString();
      final nonceB64 = decoded['nonce']?.toString();
      final cipherB64 = decoded['ciphertext']?.toString();
      final macB64 = decoded['mac']?.toString();

      if (keyB64 == null || nonceB64 == null || cipherB64 == null || macB64 == null) return null;
      if (_privateKeySerialized == null) return null;

      final encryptedKey = base64Decode(keyB64);
      final aesKey = await RSA.decryptPKCS1v15Bytes(encryptedKey, _privateKeySerialized!);

      final secretBox = cryptography.SecretBox(
        base64Decode(cipherB64),
        nonce: base64Decode(nonceB64),
        mac: cryptography.Mac(base64Decode(macB64)),
      );

      final clearBytes = await _aes.decrypt(
        secretBox,
        secretKey: cryptography.SecretKey(aesKey),
      );

      return utf8.decode(clearBytes);
    } catch (e) {
      if (kDebugMode) print('⚠️ [Encryption] Error decrypting: $e');
      return null;
    }
  }

  /// Экспортирует ключи в JSON-строку для резервного копирования
  Future<String?> exportKeys() async {
    if (_privateKeySerialized == null || _publicKeySerialized == null) {
      return null;
    }
    
    final exportData = {
      'version': 2,
      'userId': _currentUserId,
      'publicKey': _publicKeySerialized,
      'privateKey': _privateKeySerialized,
      'exportedAt': DateTime.now().toIso8601String(),
    };
    
    return jsonEncode(exportData);
  }

  /// Импортирует ключи из JSON-строки
  Future<bool> importKeys(String jsonExport, ApiService api) async {
    try {
      final data = jsonDecode(jsonExport);
      if (data is! Map) return false;
      
      final version = data['version'];
      if (version != 2) {
        if (kDebugMode) print('⚠️ [Encryption] Unsupported key version: $version');
        return false;
      }
      
      final publicKey = data['publicKey']?.toString();
      final privateKey = data['privateKey']?.toString();
      final exportedUserId = data['userId']?.toString();
      
      if (publicKey == null || privateKey == null) {
        if (kDebugMode) print('⚠️ [Encryption] Missing keys in export');
        return false;
      }
      
      // Проверяем, что ключи соответствуют текущему пользователю
      final currentUserId = api.userId;
      if (exportedUserId != null && exportedUserId != currentUserId) {
        if (kDebugMode) print('⚠️ [Encryption] Key userId mismatch: $exportedUserId vs $currentUserId');
        return false;
      }
      
      // Сохраняем ключи
      _publicKeySerialized = publicKey;
      _privateKeySerialized = privateKey;
      _currentUserId = currentUserId;
      
      final privKeyName = '${_storagePrivateKey}_$currentUserId';
      final pubKeyName = '${_storagePublicKey}_$currentUserId';
      
      await _secureStorage.write(key: pubKeyName, value: publicKey);
      await _secureStorage.write(key: privKeyName, value: privateKey);
      
      if (kDebugMode) print('✅ [Encryption] Keys imported successfully');
      return true;
    } catch (e) {
      if (kDebugMode) print('⚠️ [Encryption] Error importing keys: $e');
      return false;
    }
  }
}