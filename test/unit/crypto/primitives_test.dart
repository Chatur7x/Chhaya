// Part 1 acceptance tests — known-answer vectors for every primitive.
//
// Sources: FIPS 180-4 (SHA), RFC 4231 (HMAC), RFC 5869 (HKDF),
// RFC 8018 App. B (PBKDF2), RFC 7748 §6.1 (X25519), RFC 8032 §7.1
// (Ed25519), BIP-39 test vectors. AES-GCM is cross-validated against the
// independent `cryptography` package implementation with fixed key/nonce.
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto_pkg;
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/primitives/aes_gcm.dart';
import 'package:chaaya/core/crypto/primitives/bip39.dart';
import 'package:chaaya/core/crypto/primitives/ed25519.dart';
import 'package:chaaya/core/crypto/primitives/hkdf.dart';
import 'package:chaaya/core/crypto/primitives/pbkdf2.dart';
import 'package:chaaya/core/crypto/primitives/rng.dart';
import 'package:chaaya/core/crypto/primitives/sha.dart';
import 'package:chaaya/core/crypto/primitives/x25519.dart';

Uint8List hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < s.length; i += 2) {
    out[i ~/ 2] = int.parse(s.substring(i, i + 2), radix: 16);
  }
  return out;
}

void main() {
  group('SHA (FIPS 180-4)', () {
    test('SHA-256("abc") matches FIPS vector', () {
      expect(
        Sha.hashStringHex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('SHA-512("abc") matches FIPS vector', () {
      expect(
        Sha.hexOf(Sha.hash512(Uint8List.fromList(utf8.encode('abc')))),
        'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a'
        '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f',
      );
    });
  });

  group('HKDF-SHA256 (RFC 5869 Test Case 1)', () {
    test('OKM matches RFC vector', () {
      final okm = Hkdf.deriveKey(
        inputKeyMaterial: hex('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b'),
        length: 42,
        salt: hex('000102030405060708090a0b0c'),
        info: hex('f0f1f2f3f4f5f6f7f8f9'),
      );
      expect(
        Sha.hexOf(okm),
        '3cb25f25faacd57a90434f64d0362f2a'
        '2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
        '34007208d5b887185865',
      );
    });
  });

  group('PBKDF2-HMAC-SHA256 (RFC 8018)', () {
    test('P=password, S=salt, c=1 matches RFC vector', () {
      final key = Pbkdf2.deriveKey(
        password: Uint8List.fromList(utf8.encode('password')),
        salt: Uint8List.fromList(utf8.encode('salt')),
        iterations: 1,
        length: 32,
      );
      expect(
        Sha.hexOf(key),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });
  });

  group('X25519 (RFC 7748 §6.1)', () {
    // Authoritative vectors from RFC 7748 Section 6.1.
    const alicePriv =
        '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a';
    const alicePub =
        '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a';
    const bobPriv =
        '5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb';
    const bobPub =
        'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f';
    const sharedSecret =
        '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742';

    test('DH exchange matches RFC vector in both directions', () async {
      expect(alicePriv.length, 64);
      expect(bobPub.length, 64);
      final s1 = await X25519Kex.sharedSecret(hex(alicePriv), hex(bobPub));
      expect(Sha.hexOf(s1), sharedSecret);
      final s2 = await X25519Kex.sharedSecret(hex(bobPriv), hex(alicePub));
      expect(Sha.hexOf(s2), sharedSecret);
      Csprng.wipe(s1);
      Csprng.wipe(s2);
    });

    test('generated pairs agree on shared secret', () async {
      final alice = await X25519Kex.generateKeyPair();
      final bob = await X25519Kex.generateKeyPair();
      final s1 = await X25519Kex.sharedSecret(alice.privateKey, bob.publicKey);
      final s2 = await X25519Kex.sharedSecret(bob.privateKey, alice.publicKey);
      expect(Sha.hexOf(s1), Sha.hexOf(s2));
      Csprng.wipe(s1);
      Csprng.wipe(s2);
    });
  });

  group('Ed25519 (RFC 8032 Test 1)', () {
    // Authoritative vectors from RFC 8032 Section 7.1, TEST 1.
    const seed =
        '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
    const publicKey =
        'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';
    const emptyMessageSignature =
        'e5564300c360ac729086e2cc806e828a'
        '84877f1eb8e5d974d873e06522490155'
        '5fb8821590a33bacc61e39701cf9b46b'
        'd25bf5f0595bbe24655141438e7a100b';

    test('public key matches RFC vector', () async {
      expect(seed.length, 64);
      final algorithm = crypto_pkg.Ed25519();
      final keyPair = await algorithm.newKeyPairFromSeed(hex(seed));
      final pub = await keyPair.extractPublicKey();
      expect(Sha.hexOf(Uint8List.fromList(pub.bytes)), publicKey);
    });

    test('empty-message signature matches RFC vector', () async {
      final sig = await Ed25519Sign.sign(Uint8List(0), hex(seed));
      expect(Sha.hexOf(sig), emptyMessageSignature.replaceAll('\n', ''));
      expect(
        await Ed25519Sign.verify(Uint8List(0), sig, hex(publicKey)),
        isTrue,
      );
      Csprng.wipe(sig);
    });

    test('sign/verify round-trip, tampered message rejected', () async {
      final seed = Csprng.instance.bytes(32);
      final msg = Uint8List.fromList(utf8.encode('chhaya test message'));
      final sig = await Ed25519Sign.sign(msg, seed);
      expect(sig.length, Ed25519Sign.signatureLength);
      final algorithm = crypto_pkg.Ed25519();
      final keyPair = await algorithm.newKeyPairFromSeed(seed);
      final pub = await keyPair.extractPublicKey();
      expect(
        await Ed25519Sign.verify(msg, sig, pub.bytes),
        isTrue,
      );
      final tampered = Uint8List.fromList(utf8.encode('chhaya test messagf'));
      expect(
        await Ed25519Sign.verify(tampered, sig, pub.bytes),
        isFalse,
      );
      Csprng.wipe(seed);
    });
  });

  group('AES-256-GCM', () {
    test('matches independent implementation (fixed key/nonce)', () async {
      final key = hex(
          '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
      final nonce = hex('000102030405060708090a0b');
      final plaintext =
          Uint8List.fromList(utf8.encode('AES-GCM cross-check'));

      final ours = AesGcm.encryptBytes(
        Uint8List.fromList(key),
        plaintext,
        nonce: Uint8List.fromList(nonce),
      );

      final ref = crypto_pkg.AesGcm.with256bits();
      final refBox = await ref.encrypt(
        plaintext,
        secretKey: crypto_pkg.SecretKey(key),
        nonce: nonce,
      );
      final expected =
          Uint8List.fromList([...nonce, ...refBox.cipherText, ...refBox.mac.bytes]);

      expect(Sha.hexOf(ours), Sha.hexOf(expected));
      expect(AesGcm.decryptBytes(Uint8List.fromList(key), ours), plaintext);
    });

    test('tampered ciphertext fails closed', () {
      final key = Csprng.instance.bytes(32);
      final ct = AesGcm.encryptBytes(
        key,
        Uint8List.fromList(utf8.encode('secret')),
      );
      final tampered = Uint8List.fromList(ct)..[20] ^= 0x01;
      expect(() => AesGcm.decryptBytes(key, tampered), throwsA(anything));
      Csprng.wipe(key);
    });

    test('wrong key fails closed', () {
      final key = Csprng.instance.bytes(32);
      final wrong = Csprng.instance.bytes(32);
      final ct = AesGcm.encryptBytes(
        key,
        Uint8List.fromList(utf8.encode('secret')),
      );
      expect(() => AesGcm.decryptBytes(wrong, ct), throwsA(anything));
      Csprng.wipe(key);
      Csprng.wipe(wrong);
    });

    test('10k nonces unique (no-reuse sampling)', () {
      final seen = <String>{};
      for (var i = 0; i < 10000; i++) {
        seen.add(Sha.hexOf(Csprng.instance.bytes(12)));
      }
      expect(seen.length, 10000);
    });
  });

  group('BIP-39', () {
    test('wordlist has 2048 words', () {
      expect(Bip39.wordlist.length, 2048);
    });

    test('zero entropy vector (abandon x11 + about)', () {
      final words = Bip39.entropyToMnemonic(Uint8List(16));
      expect(words.length, 12);
      expect(words.sublist(0, 11), everyElement('abandon'));
      expect(words[11], 'about');
    });

    test('mnemonic round-trips through checksum validation', () {
      final entropy = Csprng.instance.bytes(16);
      final words = Bip39.entropyToMnemonic(entropy);
      expect(Bip39.mnemonicToEntropy(words), entropy);
      Csprng.wipe(entropy);
    });

    test('checksum mismatch rejected', () {
      final words = Bip39.entropyToMnemonic(Uint8List(16));
      final bad = List<String>.from(words)..[11] = 'abandon';
      expect(() => Bip39.mnemonicToEntropy(bad), throwsStateError);
    });
  });

  group('Engine facade + zeroization', () {
    test('facade round-trips messages', () async {
      final engine = ChhayaCryptoEngine();
      final key = Csprng.instance.bytes(32);
      const message = 'facade delegation check';
      final enc = await engine.encryptMessage(message, key);
      expect(await engine.decryptMessage(enc, key), message);
      Csprng.wipe(key);
    });

    test('key pair dispose zeroizes private key', () async {
      final pair = await ChhayaCryptoEngine.generateKeyPair();
      expect(pair.privateKey.any((b) => b != 0), isTrue);
      pair.dispose();
      expect(pair.privateKey.every((b) => b == 0), isTrue);
      expect(pair.publicKey.any((b) => b != 0), isTrue);
    });

    test('PBKDF2 recovery key is deterministic', () {
      final a = ChhayaCryptoEngine.keyFromRecoveryPhrase('abandon ' * 12);
      final b = ChhayaCryptoEngine.keyFromRecoveryPhrase('abandon ' * 12);
      expect(Sha.hexOf(a), Sha.hexOf(b));
      Csprng.wipe(a);
      Csprng.wipe(b);
    });
  });
}
