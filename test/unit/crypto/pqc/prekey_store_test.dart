// Tests for the client-side prekey private-material store (WS5 slice 1).
//
// Everything here is hermetic: in-memory SecureStorage, a test-only ML-KEM
// provider with FIPS 203 ML-KEM-1024 key/ciphertext sizes (the native
// AWS-LC provider is arm64-only and not exercised). No server, no network.
import 'dart:convert';
import 'dart:typed_data';

import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/pqc/prekey_bundle.dart';
import 'package:chaaya/core/crypto/pqc/prekey_store.dart';
import 'package:chaaya/core/crypto/pqc/pqc_provider.dart';
import 'package:chaaya/core/crypto/primitives/ed25519.dart';
import 'package:chaaya/core/crypto/primitives/rng.dart';
import 'package:chaaya/core/crypto/primitives/sha.dart';
import 'package:chaaya/core/crypto/storage/secure_storage.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test-only KEM with ML-KEM-1024 sizes (ek 1568, dk 3168, ct 1568).
/// Not secure; never used outside this file.
class _TestMlKem1024 implements PqKem {
  @override
  String get name => 'ML-KEM-1024';
  @override
  bool get isAvailable => true;
  @override
  Future<bool> initialize() async => true;

  @override
  Future<({Uint8List publicKey, Uint8List privateKey})>
      generateKeyPair() async {
    return (
      publicKey: Csprng.instance.bytes(1568),
      privateKey: Csprng.instance.bytes(3168),
    );
  }

  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
      Uint8List publicKey) async {
    return (
      ciphertext: Csprng.instance.bytes(1568),
      sharedSecret: Csprng.instance.bytes(32),
    );
  }

  @override
  Future<Uint8List> decapsulate(
          Uint8List privateKey, Uint8List ciphertext) async =>
      Csprng.instance.bytes(32);
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < hex.length; i += 2) {
    out[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return out;
}

/// Builds the singular (GET /bundle) wire shape from the plural (upload)
/// shape so the client's own parse/verify path can be exercised without a
/// server.
Map<String, dynamic> _singularFromUpload(
  Map<String, dynamic> upload, {
  int oneTimeIndex = 0,
  int pqOneTimeIndex = 0,
  bool includePqOneTime = true,
}) {
  return {
    'v': upload['v'],
    'identity': upload['identity'],
    'signedPreKey': upload['signedPreKey'],
    'pqSignedPreKey': upload['pqSignedPreKey'],
    'oneTimePreKey':
        (upload['oneTimePreKeys'] as List)[oneTimeIndex],
    'pqOneTimePreKey': includePqOneTime
        ? (upload['pqOneTimePreKeys'] as List)[pqOneTimeIndex]
        : null,
    'lastResortUsed': !includePqOneTime,
    'reseedKemKey': upload['reseedKemKey'],
  };
}

Future<Uint8List> _identityEd25519PublicKey(SecureStorage storage) =>
    KeyManager(secureBackend: storage).getIdentityEd25519PublicKeyBytes();

/// Seeds a fresh V13 identity X25519 key pair into [storage], as a real
/// enrolled device would have.
Future<void> _seedIdentity(SecureStorage storage) async {
  final pair = await ChhayaCryptoEngine.generateKeyPair();
  await KeyManager(secureBackend: storage).storeKeyPair(pair);
}

void main() {
  group('generateFreshBundle + materialFor', () {
    test('all ids roundtrip; SPK-only read and full SPK+PQOPK read', () async {
      final storage = SecureStorageMock();
      await _seedIdentity(storage);
      final store = PrekeyStore(storage, kem: _TestMlKem1024());
      final gen = await store.generateFreshBundle();
      final bundle = gen.bundleJson;

      // SPK-only resolution: no one-time prekey requested; PQSPK falls back
      // to the current advertised pointer.
      final spkId = gen.signedPreKeyId;
      final spkOnly = await store.materialFor(spkId);
      expect(spkOnly, isNotNull);
      expect(spkOnly!.signedPreKeyId, spkId);
      expect(spkOnly.signedPreKeyPrivateKey.length, 32);
      expect(spkOnly.pqSignedPreKeyId, gen.pqSignedPreKeyId);
      expect(spkOnly.pqSignedPreKeyPrivateKey.length, 3168);
      expect(spkOnly.oneTimePreKeyId, isNull);
      expect(spkOnly.oneTimePreKeyPrivateKey, isNull);
      expect(spkOnly.pqOneTimePreKeyId, isNull);
      expect(spkOnly.pqOneTimePreKeyPrivateKey, isNull);

      // Explicit full read: every field populated, ids echoed.
      final opkId =
          (bundle['oneTimePreKeys'] as List).first['keyId'] as String;
      final pqopkId =
          (bundle['pqOneTimePreKeys'] as List).first['keyId'] as String;
      final full = await store.materialFor(
        spkId,
        pqSignedPreKeyId: gen.pqSignedPreKeyId,
        oneTimePreKeyId: opkId,
        pqOneTimePreKeyId: pqopkId,
      );
      expect(full, isNotNull);
      expect(full!.signedPreKeyId, spkId);
      expect(full.pqSignedPreKeyId, gen.pqSignedPreKeyId);
      expect(full.oneTimePreKeyId, opkId);
      expect(full.oneTimePreKeyPrivateKey, isNotNull);
      expect(full.pqOneTimePreKeyId, pqopkId);
      expect(full.pqOneTimePreKeyPrivateKey, isNotNull);

      // Validity windows: SPK 30 days, PQSPK 7 days.
      final spk = bundle['signedPreKey'] as Map<String, dynamic>;
      final pqspk = bundle['pqSignedPreKey'] as Map<String, dynamic>;
      const day = 24 * 60 * 60 * 1000;
      expect(
        (spk['notAfter'] as int) - (spk['notBefore'] as int),
        30 * day,
      );
      expect(
        (pqspk['notAfter'] as int) - (pqspk['notBefore'] as int),
        7 * day,
      );

      // Every signature verifies against the identity Ed25519 public key,
      // via the client's own parse/verify path.
      final parsed = parsePrekeyBundle(
        jsonDecode(jsonEncode(_singularFromUpload(bundle))),
      );
      await verifyPrekeyBundleSignatures(parsed, now: DateTime.now());
    });

    test('bundle JSON passes client parse/verify; stored ids match', () async {
      final storage = SecureStorageMock();
      await _seedIdentity(storage);
      final store = PrekeyStore(storage, kem: _TestMlKem1024());
      final gen = await store.generateFreshBundle();
      final bundle = gen.bundleJson;
      final edPub = await _identityEd25519PublicKey(storage);
      final hex64 = RegExp(r'^[0-9a-f]{64}$');
      final hex128 = RegExp(r'^[0-9a-f]{128}$');
      final hex3136 = RegExp(r'^[0-9a-f]{3136}$');
      final uuidRe = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      );

      // Shape + format of the upload payload.
      expect(bundle['v'], 1);
      expect(
        (bundle['identity'] as Map)['x25519'],
        matches(RegExp(r'^05[0-9a-f]{64}$')),
      );
      expect(
        (bundle['identity'] as Map)['ed25519'],
        matches(hex64),
      );
      for (final entry in [
        bundle['signedPreKey'],
        bundle['pqSignedPreKey'],
      ].cast<Map<String, dynamic>>()) {
        expect(entry['keyId'], matches(uuidRe));
        expect(entry['signature'], matches(hex128));
        expect(entry['notBefore'], isA<int>());
        expect(entry['notAfter'], isA<int>());
        expect(entry['notAfter'] as int, greaterThan(entry['notBefore'] as int));
      }
      expect(
        (bundle['signedPreKey'] as Map)['publicKey'],
        matches(hex64),
      );
      expect(
        (bundle['pqSignedPreKey'] as Map)['publicKey'],
        matches(hex3136),
      );
      expect(
        (bundle['reseedKemKey'] as Map)['publicKey'],
        matches(hex3136),
      );
      expect(
        (bundle['reseedKemKey'] as Map)['signature'],
        matches(hex128),
      );
      final oneTimePreKeys = bundle['oneTimePreKeys'] as List;
      final pqOneTimePreKeys = bundle['pqOneTimePreKeys'] as List;
      expect(oneTimePreKeys.length, 100);
      expect(pqOneTimePreKeys.length, 100);
      for (final opk in oneTimePreKeys.cast<Map<String, dynamic>>()) {
        expect(opk['keyId'], matches(uuidRe));
        expect(opk['publicKey'], matches(hex64));
        expect(opk['signature'], matches(hex128));
      }
      for (final pqopk in pqOneTimePreKeys.cast<Map<String, dynamic>>()) {
        expect(pqopk['keyId'], matches(uuidRe));
        expect(pqopk['publicKey'], matches(hex3136));
        expect(pqopk['signature'], matches(hex128));
      }

      // Identity matches what the key manager would advertise.
      final keyManager = KeyManager(secureBackend: storage);
      final pair = await keyManager.getKeyPair();
      expect(
        (bundle['identity'] as Map)['x25519'],
        '05${Sha.hexOf(pair!.publicKey)}',
      );
      expect(
        (bundle['identity'] as Map)['ed25519'],
        Sha.hexOf(edPub),
      );

      // Parse + verify (both singular shapes) — no throw.
      for (final includePqOneTime in [true, false]) {
        final singular = _singularFromUpload(
          bundle,
          includePqOneTime: includePqOneTime,
        );
        await verifyPrekeyBundleSignatures(
          parsePrekeyBundle(jsonDecode(jsonEncode(singular))),
          now: DateTime.now(),
        );
      }

      // All 100 OPK + 100 PQOPK signatures verify individually.
      Future<bool> checkOneTime(Map<String, dynamic> entry) =>
          Ed25519Sign.verify(
            oneTimePreKeySignaturePreimage(OneTimePreKey(
              keyId: entry['keyId'] as String,
              publicKey: _hexToBytes(entry['publicKey'] as String),
              signature: Uint8List(64),
            )),
            _hexToBytes(entry['signature'] as String),
            edPub,
          );
      for (final opk in oneTimePreKeys.cast<Map<String, dynamic>>()) {
        expect(await checkOneTime(opk), isTrue);
      }
      for (final pqopk in pqOneTimePreKeys.cast<Map<String, dynamic>>()) {
        expect(await checkOneTime(pqopk), isTrue);
      }

      // Every advertised id resolves to a stored private half — the id set
      // matches storage.
      final spkId = gen.signedPreKeyId;
      for (final opk in oneTimePreKeys.cast<Map<String, dynamic>>()) {
        final material = await store.materialFor(
          spkId,
          oneTimePreKeyId: opk['keyId'] as String,
        );
        expect(material, isNotNull);
        expect(material!.oneTimePreKeyId, opk['keyId']);
        expect(material.oneTimePreKeyPrivateKey!.length, 32);
      }
      for (final pqopk in pqOneTimePreKeys.cast<Map<String, dynamic>>()) {
        final material = await store.materialFor(
          spkId,
          pqOneTimePreKeyId: pqopk['keyId'] as String,
        );
        expect(material, isNotNull);
        expect(material!.pqOneTimePreKeyId, pqopk['keyId']);
        expect(material.pqOneTimePreKeyPrivateKey!.length, 3168);
      }
    });
  });

  group('failure modes', () {
    test('unknown ids resolve to null, never fabricated', () async {
      final storage = SecureStorageMock();
      await _seedIdentity(storage);
      final store = PrekeyStore(storage, kem: _TestMlKem1024());
      final gen = await store.generateFreshBundle();
      const unknown = '00000000-0000-4000-8000-000000000000';

      expect(await store.materialFor(unknown), isNull);
      expect(
        await store.materialFor(gen.signedPreKeyId, pqSignedPreKeyId: unknown),
        isNull,
      );
      expect(
        await store.materialFor(gen.signedPreKeyId, oneTimePreKeyId: unknown),
        isNull,
      );
      expect(
        await store.materialFor(gen.signedPreKeyId, pqOneTimePreKeyId: unknown),
        isNull,
      );
      // Consuming an unknown id is a harmless no-op.
      await store.consumeOneTimePreKey(unknown);
    });

    test('consumeOneTimePreKey deletes exactly one entry, idempotent',
        () async {
      // Synthetic same-id pair to pin the two-namespace delete semantics.
      final storage = SecureStorageMock();
      const id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
      await storage.write(key: 'prekey/opk/$id', value: base64Encode(List.filled(32, 1)));
      await storage.write(
        key: 'prekey/pqopk/$id',
        value: base64Encode(List.filled(3168, 2)),
      );
      await storage.write(key: 'prekey/opk_index', value: jsonEncode([id]));
      await storage.write(key: 'prekey/pqopk_index', value: jsonEncode([id]));

      final store = PrekeyStore(storage, kem: _TestMlKem1024());
      await store.consumeOneTimePreKey(id);
      expect(await storage.read(key: 'prekey/opk/$id'), isNull);
      expect(await storage.read(key: 'prekey/pqopk/$id'), isNull);
      expect(await store.knownOneTimePreKeyIds(), isEmpty);
      expect(jsonDecode((await storage.read(key: 'prekey/pqopk_index'))!),
          isEmpty);
      // Idempotent: second consume does not throw.
      await store.consumeOneTimePreKey(id);

      // Generated bundle: consume removes exactly the requested opk and
      // shrinks the diagnostics view by one.
      final genStorage = SecureStorageMock();
      await _seedIdentity(genStorage);
      final genStore = PrekeyStore(genStorage, kem: _TestMlKem1024());
      final gen = await genStore.generateFreshBundle();
      final opkId = (gen.bundleJson['oneTimePreKeys'] as List)
          .first['keyId'] as String;
      expect((await genStore.knownOneTimePreKeyIds()).length, 100);
      await genStore.consumeOneTimePreKey(opkId);
      expect((await genStore.knownOneTimePreKeyIds()).length, 99);
      expect(
        await genStore.materialFor(gen.signedPreKeyId, oneTimePreKeyId: opkId),
        isNull,
      );
      await genStore.consumeOneTimePreKey(opkId);
      expect((await genStore.knownOneTimePreKeyIds()).length, 99);
    });

    test('shredAll wipes every prekey/ entry', () async {
      final storage = SecureStorageMock();
      await _seedIdentity(storage);
      final store = PrekeyStore(storage, kem: _TestMlKem1024());
      final gen = await store.generateFreshBundle();
      final bundle = gen.bundleJson;
      final ids = <String>[
        gen.signedPreKeyId,
        gen.pqSignedPreKeyId,
        ...(bundle['oneTimePreKeys'] as List)
            .map((e) => e['keyId'] as String),
        ...(bundle['pqOneTimePreKeys'] as List)
            .map((e) => e['keyId'] as String),
      ];

      await store.shredAll();

      for (final id in ids) {
        expect(await storage.read(key: 'prekey/spk/$id'), isNull);
        expect(await storage.read(key: 'prekey/pqspk/$id'), isNull);
        expect(await storage.read(key: 'prekey/opk/$id'), isNull);
        expect(await storage.read(key: 'prekey/pqopk/$id'), isNull);
      }
      for (final key in const [
        'prekey/spk_id',
        'prekey/pqspk_id',
        'prekey/spk_window',
        'prekey/pqspk_window',
        'prekey/spk_index',
        'prekey/pqspk_index',
        'prekey/opk_index',
        'prekey/pqopk_index',
        'prekey/reseed',
      ]) {
        expect(await storage.read(key: key), isNull, reason: key);
      }
      expect(await store.knownOneTimePreKeyIds(), isEmpty);
    });
  });

  group('restart + serialization hygiene', () {
    test('material re-loads across store instances (restart)', () async {
      final storage = SecureStorageMock();
      await _seedIdentity(storage);
      final first = PrekeyStore(storage, kem: _TestMlKem1024());
      final gen = await first.generateFreshBundle();

      // Fresh store object over the same storage: simulates an app restart.
      final second = PrekeyStore(storage, kem: _TestMlKem1024());
      final spkId = gen.signedPreKeyId;
      final fromFirst = await first.materialFor(spkId);
      final fromSecond = await second.materialFor(
        spkId,
        pqSignedPreKeyId: gen.pqSignedPreKeyId,
      );
      expect(fromSecond, isNotNull);
      expect(
        fromSecond!.signedPreKeyPrivateKey,
        fromFirst!.signedPreKeyPrivateKey,
      );
      expect(
        fromSecond.pqSignedPreKeyPrivateKey,
        fromFirst.pqSignedPreKeyPrivateKey,
      );
      // Full explicit read still works after "restart".
      final opkId = (gen.bundleJson['oneTimePreKeys'] as List)
          .first['keyId'] as String;
      final material = await second.materialFor(
        spkId,
        oneTimePreKeyId: opkId,
      );
      expect(material, isNotNull);
      expect(material!.oneTimePreKeyId, opkId);
    });

    test('no private material appears in the serialized bundle JSON',
        () async {
      final storage = SecureStorageMock();
      await _seedIdentity(storage);
      final store = PrekeyStore(storage, kem: _TestMlKem1024());
      final gen = await store.generateFreshBundle();
      final bundleJson = gen.bundleJson;
      final jsonStr = jsonEncode(bundleJson);
      final spkId = gen.signedPreKeyId;

      // Collect every private half the store persisted.
      final spkMaterial = await store.materialFor(spkId);
      final privates = <Uint8List>[
        spkMaterial!.signedPreKeyPrivateKey,
        spkMaterial.pqSignedPreKeyPrivateKey,
        base64Decode((await storage.read(key: 'prekey/reseed'))!),
      ];
      for (final opk in bundleJson['oneTimePreKeys'] as List) {
        final m = await store.materialFor(
          spkId,
          oneTimePreKeyId: opk['keyId'] as String,
        );
        privates.add(m!.oneTimePreKeyPrivateKey!);
      }
      for (final pqopk in bundleJson['pqOneTimePreKeys'] as List) {
        final m = await store.materialFor(
          spkId,
          pqOneTimePreKeyId: pqopk['keyId'] as String,
        );
        privates.add(m!.pqOneTimePreKeyPrivateKey!);
      }

      for (final priv in privates) {
        expect(jsonStr.contains(base64Encode(priv)), isFalse);
        expect(jsonStr.contains(Sha.hexOf(priv)), isFalse);
      }

      // No key in the upload object graph is named like private material.
      void walk(Object? node) {
        if (node is Map) {
          for (final entry in node.entries) {
            expect(
              (entry.key as String).toLowerCase(),
              isNot(contains('private')),
            );
            walk(entry.value);
          }
        } else if (node is List) {
          for (final item in node) {
            walk(item);
          }
        }
      }

      walk(bundleJson);
    });
  });
}
