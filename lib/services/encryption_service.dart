import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

import 'api_service.dart';

class EncryptionService {
  final _storage = const FlutterSecureStorage();
  final _aes = cryptography.AesGcm.with256bits();

  RSAPublicKey? _publicKey;
  RSAPrivateKey? _privateKey;
  String? _publicKeySerialized;

  static const _storagePrivateKey = 'rsa_private_key_v1';
  static const _storagePublicKey = 'rsa_public_key_v1';

  Future<void> init(ApiService api) async {
    final storedPriv = await _storage.read(key: _storagePrivateKey);
    final storedPub = await _storage.read(key: _storagePublicKey);

    if (storedPriv != null && storedPub != null) {
      _privateKey = _deserializePrivateKey(storedPriv);
      _publicKey = _deserializePublicKey(storedPub);
      _publicKeySerialized = storedPub;
    } else {
      final pair = _generateRsaKeyPair();
      _privateKey = pair.privateKey as RSAPrivateKey;
      _publicKey = pair.publicKey as RSAPublicKey;

      final pubSerialized = _serializePublicKey(_publicKey!);
      final privSerialized = _serializePrivateKey(_privateKey!);

      await _storage.write(key: _storagePublicKey, value: pubSerialized);
      await _storage.write(key: _storagePrivateKey, value: privSerialized);

      _publicKeySerialized = pubSerialized;
    }

    if (_publicKeySerialized != null) {
      try {
        await api.postPublicKey(_publicKeySerialized!);
      } catch (_) {
        // ignore sync failures; app can retry on next init
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

  // --- RSA helpers ---

  AsymmetricKeyPair<PublicKey, PrivateKey> _generateRsaKeyPair() {
    final keyParams = RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64);
    final secureRandom = _secureRandom();
    final params = ParametersWithRandom(keyParams, secureRandom);

    final generator = RSAKeyGenerator()..init(params);
    return generator.generateKeyPair();
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

  SecureRandom _secureRandom() {
    final rng = FortunaRandom();
    final seed = Uint8List(32);
    final rand = Random.secure();
    for (var i = 0; i < seed.length; i++) {
      seed[i] = rand.nextInt(256);
    }
    rng.seed(KeyParameter(seed));
    return rng;
  }

  String _serializePublicKey(RSAPublicKey key) {
    final map = {
      'v': 1,
      'n': base64Encode(_bigIntToBytes(key.modulus!)),
      'e': base64Encode(_bigIntToBytes(key.exponent!)),
    };
    return jsonEncode(map);
  }

  String _serializePrivateKey(RSAPrivateKey key) {
    final map = {
      'v': 1,
      'n': base64Encode(_bigIntToBytes(key.modulus!)),
      'd': base64Encode(_bigIntToBytes(key.privateExponent!)),
      'p': base64Encode(_bigIntToBytes(key.p!)),
      'q': base64Encode(_bigIntToBytes(key.q!)),
    };
    return jsonEncode(map);
  }

  RSAPublicKey? _deserializePublicKey(String raw) {
    try {
      var decoded = jsonDecode(raw);
      if (decoded is String) {
        decoded = jsonDecode(decoded);
      }
      if (decoded is Map) {
        final n = decoded['n']?.toString();
        final e = decoded['e']?.toString();
        if (n == null || e == null) return null;
        return RSAPublicKey(_bytesToBigInt(base64Decode(n)), _bytesToBigInt(base64Decode(e)));
      }
    } catch (_) {
      return null;
    }
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
    } catch (_) {
      return null;
    }
    return null;
  }

  Uint8List _bigIntToBytes(BigInt number) {
    var hex = number.toRadixString(16);
    if (hex.length % 2 == 1) {
      hex = '0$hex';
    }
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      final byteHex = hex.substring(i * 2, i * 2 + 2);
      result[i] = int.parse(byteHex, radix: 16);
    }
    return result;
  }

  BigInt _bytesToBigInt(Uint8List bytes) {
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (hex.isEmpty) return BigInt.zero;
    return BigInt.parse(hex, radix: 16);
  }
}
