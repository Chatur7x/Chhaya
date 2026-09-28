// Part 2 tests — key manager with mock secure storage.
//
// Covers V13 API compatibility, derivation paths, rotation, background
// zeroization, per-user database keys, and the no-secrets-in-logs rule.
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/primitives/rng.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';

KeyManager makeManager([Map<String, String>? seed]) {
  return KeyManager(secureBackend: SecureStorageMock(seed));
}

Uint8List hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < s.length; i += 2) {
    out[i ~/ 2] = int.parse(s.substring(i, i + 2), radix: 16);
  }
  return out;
}

void main() {
  group('V13 API compatibility', () {
    test('key pair round-trips', () async {
      final manager = makeManager();
      final pair = await ChhayaCryptoEngine.generateKeyPair();
      await manager.storeKeyPair(pair);
      final loaded = await manager.getKeyPair();
      expect(loaded, isNotNull);
      expect(loaded!.publicKeyHex, pair.publicKeyHex);
      expect(loaded.privateKeyHex, pair.privateKeyHex);
      expect(await manager.hasKeys(), isTrue);
      pair.dispose();
    });

    test('recovery phrase round-trips', () async {
      final manager = makeManager();
      const phrase = ['abandon', 'ability', 'able'];
      await manager.storeRecoveryPhrase(phrase);
      expect(await manager.getRecoveryPhrase(), phrase);
    });

    test('chhaya id round-trips', () async {
      final manager = makeManager();
      await manager.storeChhayaId('id-123');
      expect(await manager.getChhayaId(), 'id-123');
    });

    test('clearAllKeys removes everything', () async {
      final manager = makeManager();
      final pair = await ChhayaCryptoEngine.generateKeyPair();
      await manager.storeKeyPair(pair);
      await manager.storeRecoveryPhrase(['word']);
      await manager.storeChhayaId('id');
      await manager.clearAllKeys();
      expect(await manager.hasKeys(), isFalse);
      expect(await manager.getRecoveryPhrase(), isNull);
      expect(await manager.getChhayaId(), isNull);
      pair.dispose();
    });
  });

  group('Derivation paths', () {
    test('same path derives same key', () async {
      final manager = makeManager();
      final a = await manager.derivePathKey('session/alice/phone');
      final b = await manager.derivePathKey('session/alice/phone');
      expect(a, b);
      Csprng.wipe(a);
      Csprng.wipe(b);
    });

    test('distinct paths derive distinct keys', () async {
      final manager = makeManager();
      final a = await manager.derivePathKey('session/alice/phone');
      final b = await manager.derivePathKey('session/bob/phone');
      final c = await manager.derivePathKey('vault/master');
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
      Csprng.wipe(a);
      Csprng.wipe(b);
      Csprng.wipe(c);
    });

    test('malformed paths are rejected', () async {
      final manager = makeManager();
      expect(() => manager.derivePathKey(''), throwsArgumentError);
      expect(() => manager.derivePathKey('../escape'), throwsArgumentError);
      expect(() => manager.derivePathKey('a b'), throwsArgumentError);
    });

    test('database keys are stable per user and distinct across users',
        () async {
      final manager = makeManager();
      final u1a = await manager.getDatabaseKey(userId: 'user-1');
      final u1b = await manager.getDatabaseKey(userId: 'user-1');
      final u2 = await manager.getDatabaseKey(userId: 'user-2');
      expect(u1a, u1b);
      expect(u1a, isNot(equals(u2)));
      Csprng.wipe(u1a);
      Csprng.wipe(u1b);
      Csprng.wipe(u2);
    });
  });

  group('Session cache + zeroization', () {
    test('cached keys return copies and wipe on demand', () {
      final manager = makeManager();
      final key = Csprng.instance.bytes(32);
      manager.cacheSessionKey('alice', 'phone', key);
      expect(manager.debugCachedSessionKeyCount, 1);
      final copy = manager.getCachedSessionKey('alice', 'phone');
      expect(copy, isNotNull);
      expect(copy, key);
      expect(identical(copy, key), isFalse);
      manager.zeroizeCache();
      expect(manager.debugCachedSessionKeyCount, 0);
      expect(manager.getCachedSessionKey('alice', 'phone'), isNull);
      Csprng.wipe(key);
    });

    test('background lifecycle event wipes the cache', () {
      final manager = makeManager();
      manager.cacheSessionKey('alice', 'phone', Csprng.instance.bytes(32));
      expect(manager.debugCachedSessionKeyCount, 1);
      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(manager.debugCachedSessionKeyCount, 0);
    });

    test('rotateSessionKey drops contact keys and bumps epoch', () async {
      final manager = makeManager();
      manager.cacheSessionKey('alice', 'phone', Csprng.instance.bytes(32));
      manager.cacheSessionKey('alice', 'laptop', Csprng.instance.bytes(32));
      manager.cacheSessionKey('bob', 'phone', Csprng.instance.bytes(32));
      expect(await manager.rotateSessionKey('alice'), 1);
      expect(manager.getCachedSessionKey('alice', 'phone'), isNull);
      expect(manager.getCachedSessionKey('alice', 'laptop'), isNull);
      expect(
        manager.getCachedSessionKey('bob', 'phone'),
        isNotNull,
      );
      expect(await manager.rotateSessionKey('alice'), 2);
      expect(manager.rotationEpoch('alice'), 2);
      manager.zeroizeCache();
    });
  });

  group('Identity rotation', () {
    test('announcement verifies against the old key', () async {
      final manager = makeManager();
      expect(await manager.identityEpoch(), 0);

      // Capture the pre-rotation seed to derive the old public key.
      final oldSeed =
          await manager.derivePathKey(KeyManager.pathIdentityEd25519);
      final oldPair =
          await Ed25519().newKeyPairFromSeed(oldSeed);
      final oldPub = await oldPair.extractPublicKey();
      Csprng.wipe(oldSeed);

      final announcement = await manager.rotateIdentity();
      expect(await manager.identityEpoch(), 1);
      expect(
        await announcement.verifySignature(
          Uint8List.fromList(oldPub.bytes),
        ),
        isTrue,
      );

      // Second rotation chains: new old-key equals previous new-key.
      final second = await manager.rotateIdentity();
      expect(second.oldPublicKeyHex, announcement.newPublicKeyHex);
      expect(
        await second.verifySignature(
          hex(announcement.newPublicKeyHex),
        ),
        isTrue,
      );
      expect(await manager.identityEpoch(), 2);
    });
  });

  group('Diagnostics', () {
    test('debugDescribe names keys but never leaks material', () async {
      final manager = makeManager();
      final pair = await ChhayaCryptoEngine.generateKeyPair();
      await manager.storeKeyPair(pair);
      final description = await manager.debugDescribe();
      expect(description, contains('chhaya_private_key'));
      expect(
        description.contains(base64Encode(pair.privateKey).substring(0, 12)),
        isFalse,
      );
      expect(
        description.contains(pair.privateKeyHex.substring(0, 12)),
        isFalse,
      );
      pair.dispose();
    });
  });
}
