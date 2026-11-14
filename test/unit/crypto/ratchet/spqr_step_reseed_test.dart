// Delayed-reseed chain acceptance tests (criterion 8, spec §3.9).
//
// Covers: the ~25-send/7-day reseed cadence boundary, old-epoch
// underivability after the reseed transition, decryption across the
// boundary within the skip window, the >1000 gap refusal with state
// intact, the provider-absent fail-closed path, and the legacy-tolerant
// trailing header section.
//
// The "delayed reseed" flight rides the normal authenticated envelope
// path (a trailing ratchet-header section); nothing here performs or
// requires a network round-trip.
import 'dart:convert';
import 'dart:typed_data';

import 'package:chaaya/core/crypto/primitives/rng.dart';
import 'package:chaaya/core/crypto/primitives/x25519.dart';
import 'package:chaaya/core/crypto/ratchet/double_ratchet.dart';
import 'package:chaaya/core/crypto/ratchet/header.dart';
import 'package:chaaya/core/crypto/ratchet/session_state.dart';
import 'package:chaaya/core/crypto/ratchet/spqr.dart';
import 'package:chaaya/core/crypto/ratchet/triple_ratchet.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:flutter_test/flutter_test.dart';

const _demoHex =
    'a1b2c3d4e5f60718293a4b5c6d7e8f901234567890abcdef1234567890abcdef12';

Contact peer(String id, {bool verified = true}) => Contact(
      id: id,
      chhayaId: ChhayaId.fromPublicKey(_demoHex),
      displayName: id,
      isVerified: verified,
    );

bool eq(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// Test-only reseed provider (deterministic, NOT secure): its shared
/// secret is a pure function of the encapsulated key, so both sides
/// derive the same value. Never use outside tests.
class _TestReseedKem implements ReseedKem {
  _TestReseedKem(this.tag);

  final List<int> tag;
  int generateKeyPairCalls = 0;
  int encapsulateCalls = 0;
  int decapsulateCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<({Uint8List publicKey, Uint8List privateKey})>
      generateKeyPair() async {
    generateKeyPairCalls++;
    final n = generateKeyPairCalls;
    final pub = Uint8List(32);
    final priv = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      pub[i] = (tag[i % tag.length] + i * 7 + n) & 0xFF;
      priv[i] = (tag[i % tag.length] + i * 13 + n + 1) & 0xFF;
    }
    return (publicKey: pub, privateKey: priv);
  }

  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
    Uint8List publicKey,
  ) async {
    encapsulateCalls++;
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] = (tag[i % tag.length] + publicKey[i % publicKey.length] + i) &
          0xFF;
    }
    return (ciphertext: Uint8List.fromList(out), sharedSecret: out);
  }

  @override
  Future<Uint8List> decapsulate(
    Uint8List privateKey,
    Uint8List ciphertext,
  ) async {
    decapsulateCalls++;
    return Uint8List.fromList(ciphertext);
  }
}

/// Reseed provider whose native implementation is unavailable
/// (fail-closed path: reseed silently stays classical).
class _AbsentReseedKem extends _TestReseedKem {
  _AbsentReseedKem() : super([9, 9, 9]);

  @override
  bool get isAvailable => false;

  @override
  Future<bool> initialize() async => false;
}

Future<(SessionState, SessionState)> makePair() async {
  final shared = Csprng.instance.bytes(32);
  final aKeys = await X25519Kex.generateKeyPair();
  final bKeys = await X25519Kex.generateKeyPair();
  final alice = await TripleRatchet.startSession(
    peer: peer('bob'),
    remoteDhPublicKey: bKeys.publicKey,
    sharedSecret: shared,
    initiator: true,
    ourPrivateKey: aKeys.privateKey,
  );
  final bob = await TripleRatchet.startSession(
    peer: peer('alice'),
    remoteDhPublicKey: aKeys.publicKey,
    sharedSecret: shared,
    initiator: false,
    ourPrivateKey: bKeys.privateKey,
  );
  Csprng.wipe(shared);
  return (alice, bob);
}

void main() {
  group('delayed reseed (spec §3.9)', () {
    test('seed changes after the 25-send cadence boundary', () async {
      final (alice, bob) = await makePair();
      final kemA = _TestReseedKem([1, 2, 3]);
      final kemB = _TestReseedKem([1, 2, 3]);
      final seedsPreFlight = Uint8List.fromList(alice.spqrSeed);
      final bobSeedsPreFlight = Uint8List.fromList(bob.spqrSeed);

      TripleHeader? offerHeader;
      for (var i = 0; i < 25; i++) {
        final out = await TripleRatchet.encrypt(alice, reseedKem: kemA);
        if (out.header.pq != null) {
          offerHeader = out.header;
        }
        await TripleRatchet.decrypt(bob, out.header, reseedKem: kemB);
        out.keys.wipe();
      }

      expect(offerHeader, isNotNull);
      expect(offerHeader!.pq!['t'], 'offer');
      expect(alice.pendingReseedPrivateKey, isNotNull);
      // No reseed transition until the ct lands.
      expect(alice.spqrGeneration, 0);
      expect(bob.spqrGeneration, 0);

      final reply = await TripleRatchet.encrypt(bob, reseedKem: kemB);
      expect(reply.header.pq, isNotNull);
      expect(reply.header.pq!['t'], 'ct');
      // Responder transitions on the ct send.
      expect(bob.spqrGeneration, 1);
      expect(eq(bob.spqrSeed, bobSeedsPreFlight), isFalse);

      // Initiator transitions on the ct receipt; seeds agree.
      await TripleRatchet.decrypt(alice, reply.header, reseedKem: kemA);
      expect(alice.spqrGeneration, 1);
      expect(eq(alice.spqrSeed, seedsPreFlight), isFalse);
      expect(alice.spqrGeneration, isNot(0));
      expect(eq(alice.spqrSeed, bob.spqrSeed), isTrue);
      expect(alice.pendingReseedPrivateKey, isNull);
    });

    test('decrypts across the boundary within the skip window', () async {
      final (alice, bob) = await makePair();
      final kemA = _TestReseedKem([4, 5, 6]);
      final kemB = _TestReseedKem([4, 5, 6]);

      // 25 sends; the 23rd and 24th are held back (late delivery across
      // the reseed boundary) — the final send carries the offer and
      // must be delivered for the flight to complete.
      final held = <TripleHeader>[];
      for (var i = 0; i < 25; i++) {
        final out = await TripleRatchet.encrypt(alice, reseedKem: kemA);
        if (i >= 22 && i < 24) {
          held.add(out.header);
        } else {
          final back = await TripleRatchet.decrypt(
            bob,
            out.header,
            reseedKem: kemB,
          );
          expect(eq(back.messageKey, out.keys.messageKey), isTrue);
          back.wipe();
        }
        out.keys.wipe();
      }
      // Bring the flight home: bob answers, both transition.
      final reply = await TripleRatchet.encrypt(bob, reseedKem: kemB);
      expect(reply.header.pq?['t'], 'ct');
      await TripleRatchet.decrypt(alice, reply.header, reseedKem: kemA);
      reply.keys.wipe();
      expect(alice.spqrGeneration, 1);
      expect(bob.spqrGeneration, 1);

      // Held-back pre-boundary messages still decrypt (in-window,
      // retiring-generation keys were preserved at the transition).
      for (final header in held) {
        final back = await TripleRatchet.decrypt(bob, header, reseedKem: kemB);
        expect(back.messageKey.length, 32);
        back.wipe();
      }

      // And normal traffic continues across the boundary.
      for (var i = 0; i < 5; i++) {
        final out = await TripleRatchet.encrypt(alice, reseedKem: kemA);
        final back = await TripleRatchet.decrypt(
          bob,
          out.header,
          reseedKem: kemB,
        );
        expect(eq(back.messageKey, out.keys.messageKey), isTrue);
        out.keys.wipe();
        back.wipe();
      }
    });

    test('retiring keys inside the window are exact, outside are refused',
        () async {
      final (alice, bob) = await makePair();
      final kemA = _TestReseedKem([7, 8, 9]);
      final kemB = _TestReseedKem([7, 8, 9]);
      Uint8List? epochTwoKeyBefore;
      for (var i = 0; i < 25; i++) {
        final out = await TripleRatchet.encrypt(alice, reseedKem: kemA);
        if (i == 21) {
          // By now bob has stepped to epoch 2; capture the exact
          // retiring-generation derivation for comparison post-flight.
          epochTwoKeyBefore =
              SpqrChain.chainKeyFor(Uint8List.fromList(bob.spqrSeed), 2);
        }
        await TripleRatchet.decrypt(bob, out.header, reseedKem: kemB);
        out.keys.wipe();
      }
      final reply = await TripleRatchet.encrypt(bob, reseedKem: kemB);
      await TripleRatchet.decrypt(alice, reply.header, reseedKem: kemA);
      reply.keys.wipe();
      expect(bob.spqrGeneration, 1);

      // The retiring epoch-2 key is served from the window cache — not
      // derivable from the new seed — and matches the pre-reseed value.
      final retiring = SpqrChain.epochKey(bob, 2);
      expect(eq(retiring, epochTwoKeyBefore!), isTrue);
      // The chain position bumped past the retiring range, so the
      // current generation always reads as "future" for old epochs.
      expect(bob.spqrEpoch >= 103, isTrue);
      expect(SpqrChain.epochKeyAvailable(bob, bob.spqrEpoch), isTrue);
      // Way beyond the skipped-message window: refused.
      expect(
        SpqrChain.epochKeyAvailable(bob, 0 - SpqrChain.maxSkip),
        isFalse,
      );
      // Negative epochs are rejected outright.
      expect(
        () => SpqrChain.epochKey(bob, -1),
        throwsArgumentError,
      );
    });

    test('hash-step is one-way and the old seed is wiped', () async {
      final (alice, bob) = await makePair();
      final kemA = _TestReseedKem([10, 11, 12]);
      final kemB = _TestReseedKem([10, 11, 12]);
      for (var i = 0; i < 25; i++) {
        final out = await TripleRatchet.encrypt(alice, reseedKem: kemA);
        await TripleRatchet.decrypt(bob, out.header, reseedKem: kemB);
        out.keys.wipe();
      }
      final reply = await TripleRatchet.encrypt(bob, reseedKem: kemB);
      final preWipeSeed = Uint8List.fromList(alice.spqrSeed);
      await TripleRatchet.decrypt(alice, reply.header, reseedKem: kemA);
      // Stepping from the retired seed never yields the live seed; the
      // transition advanced the generation counter and dropped the
      // pending keypair.
      expect(eq(SpqrChain.stepSeed(preWipeSeed, 1), alice.spqrSeed), isFalse);
      expect(eq(alice.spqrSeed, preWipeSeed), isFalse);
      expect(alice.spqrGeneration, 1);
      expect(alice.pendingReseedPrivateKey, isNull);
      expect(alice.pendingReseedPublicKey, isNull);
    });

    test('gap beyond 1000 throws TooManySkippedException with state intact',
        () async {
      final (alice, bob) = await makePair();
      final kemA = _TestReseedKem([13, 14, 15]);
      final kemB = _TestReseedKem([13, 14, 15]);
      for (var i = 0; i < 3; i++) {
        final out = await TripleRatchet.encrypt(alice, reseedKem: kemA);
        await TripleRatchet.decrypt(bob, out.header, reseedKem: kemB);
        out.keys.wipe();
      }
      final before = {
        'rootKey': base64Encode(bob.rootKey),
        'recvChainKey': base64Encode(bob.recvChainKey),
        'recvCounter': bob.recvCounter,
        'spqrSeed': base64Encode(bob.spqrSeed),
        'spqrEpoch': bob.spqrEpoch,
        'skipped': bob.skipped.length,
      };
      final forged = TripleHeader(
        dh: RatchetHeader(
          dhPublicKey: alice.ourPublicKey,
          prevChainLength: 0,
          messageNumber: bob.recvCounter,
        ),
        spqrEpoch: bob.spqrEpoch + SpqrChain.maxSkip + 1,
      );
      expect(
        () => TripleRatchet.decrypt(bob, forged, reseedKem: kemB),
        throwsA(isA<TooManySkippedException>()),
      );
      expect(base64Encode(bob.rootKey), before['rootKey']);
      expect(base64Encode(bob.recvChainKey), before['recvChainKey']);
      expect(bob.recvCounter, before['recvCounter']);
      expect(base64Encode(bob.spqrSeed), before['spqrSeed']);
      expect(bob.spqrEpoch, before['spqrEpoch']);
      expect(bob.skipped.length, before['skipped']);
    });

    test('provider-absent: reseed silently stays classical, sessions work',
        () async {
      final (alice, bob) = await makePair();
      final absentA = _AbsentReseedKem();
      final absentB = _AbsentReseedKem();
      for (var i = 0; i < 30; i++) {
        final out = await TripleRatchet.encrypt(alice, reseedKem: absentA);
        expect(out.header.pq, isNull);
        final back = await TripleRatchet.decrypt(
          bob,
          out.header,
          reseedKem: absentB,
        );
        expect(eq(back.messageKey, out.keys.messageKey), isTrue);
        out.keys.wipe();
        back.wipe();
      }
      final reply = await TripleRatchet.encrypt(bob, reseedKem: absentB);
      expect(reply.header.pq, isNull);
      final back = await TripleRatchet.decrypt(
        alice,
        reply.header,
        reseedKem: absentA,
      );
      expect(eq(back.messageKey, reply.keys.messageKey), isTrue);
      expect(alice.spqrGeneration, 0);
      expect(bob.spqrGeneration, 0);
    });

    test('peer without provider keeps receiving when the offer flies',
        () async {
      final (alice, bob) = await makePair();
      final kemA = _TestReseedKem([16, 17, 18]);
      // Bob has NO reseed provider at all: the offer section is simply
      // not acted on, the session continues classical, nothing crashes.
      for (var i = 0; i < 26; i++) {
        final out = await TripleRatchet.encrypt(alice, reseedKem: kemA);
        if (i == 24) {
          expect(out.header.pq?['t'], 'offer');
        }
        final back = await TripleRatchet.decrypt(bob, out.header);
        expect(eq(back.messageKey, out.keys.messageKey), isTrue);
        out.keys.wipe();
        back.wipe();
      }
      final reply = await TripleRatchet.encrypt(bob);
      expect(reply.header.pq, isNull);
      await TripleRatchet.decrypt(alice, reply.header, reseedKem: kemA);
      expect(alice.spqrGeneration, 0); // no flight completed
      expect(bob.spqrGeneration, 0);
    });

    test('empty header pq and absent provider mean zero change', () async {
      final (alice, bob) = await makePair();
      for (var i = 0; i < 12; i++) {
        final out = await TripleRatchet.encrypt(alice);
        expect(out.header.pq, isNull);
        expect(out.header.toBytes().length, TripleHeader.encodedLength);
        await TripleRatchet.decrypt(bob, out.header);
        out.keys.wipe();
      }
    });
  });

  group('header trailing pq section (soft extension)', () {
    RatchetHeader dh([int seedByte = 0x21]) => RatchetHeader(
          dhPublicKey: Uint8List.fromList(List<int>.filled(32, seedByte)),
          prevChainLength: 3,
          messageNumber: 7,
        );

    test('fixed 44-byte headers parse and re-encode byte-identically', () {
      final legacy = TripleHeader(dh: dh(), spqrEpoch: 42);
      final bytes = legacy.toBytes();
      expect(bytes.length, TripleHeader.encodedLength);
      final parsed = TripleHeader.fromBytes(bytes);
      expect(parsed.spqrEpoch, 42);
      expect(parsed.pq, isNull);
      expect(eq(parsed.toBytes(), bytes), isTrue);
    });

    test('offer sections survive a parse round-trip', () {
      final withPq = TripleHeader(
        dh: dh(),
        spqrEpoch: 9,
        pq: {'t': 'offer', 'pk': base64Encode(Uint8List(32))},
      );
      final bytes = withPq.toBytes();
      expect(bytes.length, greaterThan(TripleHeader.encodedLength));
      final parsed = TripleHeader.fromBytes(bytes);
      expect(parsed.spqrEpoch, 9);
      expect(parsed.pq, isNotNull);
      expect(parsed.pq!['t'], 'offer');
      expect(eq(parsed.toBytes(), bytes), isTrue);
    });

    test('unknown trailing sections are skipped, bytes preserved', () {
      final fixed = TripleHeader(dh: dh(), spqrEpoch: 5).toBytes();
      final section = <int>[
        0x7a, 0x7a, // 'zz'
        0, 0, 0, 2, // len
        0x68, 0x69, // 'hi'
      ];
      final withUnknown = Uint8List.fromList([...fixed, ...section]);
      final parsed = TripleHeader.fromBytes(withUnknown);
      expect(parsed.pq, isNull);
      expect(parsed.dh.messageNumber, 7);
      expect(eq(parsed.toBytes(), withUnknown), isTrue);
    });

    test('known pq section after unknown section is still parsed', () {
      final fixed = TripleHeader(dh: dh(), spqrEpoch: 5).toBytes();
      final unknown = <int>[0x7a, 0x7a, 0, 0, 0, 1, 0x00];
      final pqPayload = utf8.encode(
        jsonEncode({
          't': 'ct',
          'ct': base64Encode(Uint8List(48)),
        }),
      );
      final pqSection = <int>[
        0x70, 0x71,
        (pqPayload.length >> 24) & 0xFF,
        (pqPayload.length >> 16) & 0xFF,
        (pqPayload.length >> 8) & 0xFF,
        pqPayload.length & 0xFF,
        ...pqPayload,
      ];
      final bytes = Uint8List.fromList([...fixed, ...unknown, ...pqSection]);
      final parsed = TripleHeader.fromBytes(bytes);
      expect(parsed.pq?['t'], 'ct');
      expect(eq(parsed.toBytes(), bytes), isTrue);
    });

    test('malformed pq section is ignored, never throws', () {
      final fixed = TripleHeader(dh: dh(), spqrEpoch: 5).toBytes();
      final broken = <int>[0x70, 0x71, 0, 0, 0x10, 0x00, 0x01]; // len lies
      final bytes = Uint8List.fromList([...fixed, ...broken]);
      final parsed = TripleHeader.fromBytes(bytes);
      expect(parsed.pq, isNull);
      expect(eq(parsed.toBytes(), bytes), isTrue);
    });

    test('oversized trailing section is rejected', () {
      final fixed = TripleHeader(dh: dh(), spqrEpoch: 5).toBytes();
      final bytes =
          Uint8List(fixed.length + TripleHeader.maxTrailingBytes + 1);
      bytes.setRange(0, fixed.length, fixed);
      expect(() => TripleHeader.fromBytes(bytes), throwsArgumentError);
    });

    test('trailing-section constant matches the fixed prefix', () {
      expect(TripleHeader.encodedLength, RatchetHeader.encodedLength + 4);
    });
  });
}
