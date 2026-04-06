import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pointycastle/export.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';

// Moved outside the class so it can be run in a separate Isolate
Map<String, String> _generateAndSerializeRsaKeyPair(dynamic _) {
  final keyParams = RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64);
  final secureRandom = FortunaRandom();
  final seed = Uint8List(32);
  final rand = Random.secure();
  for (var i = 0; i < seed.length; i++) {
    seed[i] = rand.nextInt(256);
  }
  secureRandom.seed(KeyParameter(seed));
  final params = ParametersWithRandom(keyParams, secureRandom);

  final generator = RSAKeyGenerator()..init(params);
  final pair = generator.generateKeyPair();
  
  final pub = pair.publicKey as RSAPublicKey;
  final priv = pair.privateKey as RSAPrivateKey;
  
  Uint8List b(BigInt number) {
    var hex = number.toRadixString(16);
    if (hex.length % 2 == 1) hex = '0$hex';
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    return result;
  }

  return {
    'pub': jsonEncode({
      'v': 1,
      'n': base64Encode(b(pub.modulus!)),
      'e': base64Encode(b(pub.exponent!)),
    }),
    'priv': jsonEncode({
      'v': 1,
      'n': base64Encode(b(priv.modulus!)),
      'd': base64Encode(b(priv.privateExponent!)),
      'p': base64Encode(b(priv.p!)),
      'q': base64Encode(b(priv.q!)),
    })
  };
}

class EncryptionService {
  final _aes = cryptography.AesGcm.with256bits();

  RSAPublicKey? _publicKey;
  RSAPrivateKey? _privateKey;
  String? _publicKeySerialized;
  String? _currentUserId;

  static const _storagePrivateKey = 'rsa_private_key_v1';
  static const _storagePublicKey = 'rsa_public_key_v1';

  Future<void> init(ApiService api) async {
    final userId = api.userId;
    if (userId == null) {
      print('⚠️ [Encryption] init called but userId is NULL. Skipping.');
      return;
    }

    // If already initialized for this user, don't do it again
    if (_publicKey != null && _currentUserId == userId) {
      print('🔐 [Encryption] Already initialized for user $userId');
      return;
    }

    _currentUserId = userId;
    final prefs = await SharedPreferences.getInstance();

    // User-specific keys
    final privKeyName = '${_storagePrivateKey}_$userId';
    final pubKeyName = '${_storagePublicKey}_$userId';

    final storedPriv = prefs.getString(privKeyName);
    final storedPub = prefs.getString(pubKeyName);

    print('🔐 [Encryption] Initializing for user: $userId');

    if (storedPriv != null && storedPub != null) {
      print('🔐 [Encryption] Stored keys found. Deserializing...');
      _privateKey = _deserializePrivateKey(storedPriv);
      _publicKey = _deserializePublicKey(storedPub);
      _publicKeySerialized = storedPub;

      if (_privateKey == null || _publicKey == null) {
        print('❌ [Encryption] Deserialization failed! Keys corrupted?');
        // Optionally: generate new keys if corrupted, but warn user
      } else {
        print('✅ [Encryption] Keys loaded and verified.');
      }
    } else {
      print('🔐 [Encryption] No stored keys for this user. Generating new pair...');
      
      // UI stay responsive
      final keys = await compute(_generateAndSerializeRsaKeyPair, null);
      
      final pubSerialized = keys['pub']!;
      final privSerialized = keys['priv']!;
      
      _publicKey = _deserializePublicKey(pubSerialized);
      _privateKey = _deserializePrivateKey(privSerialized);
      _publicKeySerialized = pubSerialized;

      print('🔐 [Encryption] Keys generated. Writing to SharedPreferences for $userId...');
      await prefs.setString(pubKeyName, pubSerialized);
      await prefs.setString(privKeyName, privSerialized);
    }

    // Sync with server if we have a public key
    if (_publicKeySerialized != null) {
      try {
        print('📡 [Encryption] Syncing public key with server...');
        await api.postPublicKey(_publicKeySerialized!);
      } catch (e) {
        print('⚠️ [Encryption] Could not sync key with server: $e');
      }
    }
  }

  String? get publicKeySerialized => _publicKeySerialized;

  Future<String?> encryptForPeer(String plaintext, String peerPublicKey) async {
    try {
      final peerKey = _deserializePublicKey(peerPublicKey);
      if (peerKey == null) return null;

      final secretKey = await _aes.newSecretKey();
      final secretKeyBytes = await secretKey.extractBytes();
      final nonce = _aes.newNonce();

      final secretBox = await _aes.encrypt(
        utf8.encode(plaintext),
        secretKey: secretKey,
        nonce: nonce,
      );

      final encryptedKey = _rsaEncrypt(Uint8List.fromList(secretKeyBytes), peerKey);

      final payload = {
        'v': 1,
        'alg': 'AES-256-GCM',
        'key': base64Encode(encryptedKey),
        'nonce': base64Encode(secretBox.nonce),
        'ciphertext': base64Encode(secretBox.cipherText),
        'mac': base64Encode(secretBox.mac.bytes),
      };

      return jsonEncode(payload);
    } catch (_) {
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
      if (_privateKey == null) return null;

      final encryptedKey = base64Decode(keyB64);
      final aesKey = _rsaDecrypt(encryptedKey, _privateKey!);

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
    } catch (_) {
      return null;
    }
  }

  Uint8List _rsaEncrypt(Uint8List data, RSAPublicKey publicKey) {
    final engine = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
    return engine.process(data);
  }

  Uint8List _rsaDecrypt(Uint8List data, RSAPrivateKey privateKey) {
    final engine = PKCS1Encoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return engine.process(data);
  }

  RSAPublicKey? _deserializePublicKey(String raw) {
    try {
      var decoded = jsonDecode(raw);
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is Map) {
        final n = decoded['n']?.toString();
        final e = decoded['e']?.toString();
        if (n == null || e == null) return null;
        return RSAPublicKey(_bytesToBigInt(base64Decode(n)), _bytesToBigInt(base64Decode(e)));
      }
    } catch (_) {}
    return null;
  }

  RSAPrivateKey? _deserializePrivateKey(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final n = decoded['n']?.toString();
        final d = decoded['d']?.toString();
        final p = decoded['p']?.toString();
        final q = decoded['q']?.toString();
        if (n == null || d == null || p == null || q == null) return null;
        return RSAPrivateKey(
          _bytesToBigInt(base64Decode(n)),
          _bytesToBigInt(base64Decode(d)),
          _bytesToBigInt(base64Decode(p)),
          _bytesToBigInt(base64Decode(q)),
        );
      }
    } catch (_) {}
    return null;
  }

  BigInt _bytesToBigInt(Uint8List bytes) {
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (hex.isEmpty) return BigInt.zero;
    return BigInt.parse(hex, radix: 16);
  }
}
