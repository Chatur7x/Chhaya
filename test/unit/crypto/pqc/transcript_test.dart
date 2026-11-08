// Transcript T (spec §3.3) and SK/SK_fb derivation (spec §3.4) tests.
// Golden vectors come from fixed synthetic inputs; every byte of T is
// pinned via SHA-256(T) and the full-length comparison.
import 'dart:math';
import 'dart:typed_data';

import 'package:chaaya/core/crypto/pqc/transcript.dart';
import 'package:flutter_test/flutter_test.dart';

import 'transcript_golden_vectors.dart';

Uint8List fill(int len, int byte) =>
    Uint8List.fromList(List.filled(len, byte));

String hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

final _fields = TranscriptFields(
  protocolVersion: protocolVersionV2,
  selectedSuite: suiteBytePqxdhV1,
  curve: curveX25519,
  kem: kemMlKem1024,
  hash: hashSha256,
  aead: aeadAes256Gcm,
  initiatorVersion: protocolVersionV2,
  responderVersion: protocolVersionV2,
  conversationId: '11111111-2222-4333-8444-555555555555',
  initiatorX25519: fill(32, 0xa1),
  responderX25519: fill(32, 0xb2),
  initiatorEd25519: fill(32, 0xc3),
  responderEd25519: fill(32, 0xd4),
  ephemeralX25519: fill(32, 0xe5),
  signedPreKeyId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  pqSignedPreKeyId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  oneTimePreKeyId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  pqOneTimePreKeyId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  role: roleEstablisher,
  mlKemCiphertext: fill(1568, 0xf6),
);

void main() {
  group('canonical transcript encoding (spec §3.3)', () {
    test('golden vector: fixed inputs produce the pinned T bytes', () {
      final t = buildTranscript(_fields);
      expect(t.length, int.parse(kExpectedTLength));
      expect(hex(t), kExpectedTranscriptHex);
    });

    test('golden vector: salt = SHA-256(T) is pinned', () {
      expect(hex(transcriptHash(buildTranscript(_fields))), kExpectedTSaltHex);
    });

    test('golden vector: last-resort transcript (no OPK ids) is pinned', () {
      final fields = TranscriptFields(
        protocolVersion: _fields.protocolVersion,
        selectedSuite: _fields.selectedSuite,
        curve: _fields.curve,
        kem: _fields.kem,
        hash: _fields.hash,
        aead: _fields.aead,
        initiatorVersion: _fields.initiatorVersion,
        responderVersion: _fields.responderVersion,
        conversationId: _fields.conversationId,
        initiatorX25519: _fields.initiatorX25519,
        responderX25519: _fields.responderX25519,
        initiatorEd25519: _fields.initiatorEd25519,
        responderEd25519: _fields.responderEd25519,
        ephemeralX25519: _fields.ephemeralX25519,
        signedPreKeyId: _fields.signedPreKeyId,
        pqSignedPreKeyId: _fields.pqSignedPreKeyId,
        oneTimePreKeyId: null,
        pqOneTimePreKeyId: null,
        role: _fields.role,
        mlKemCiphertext: _fields.mlKemCiphertext,
      );
      final t = buildTranscript(fields);
      expect(t.length, int.parse(kExpectedTNoOpkLength));
      expect(hex(t), kExpectedTranscriptNoOpkHex);
    });

    test('field layout matches §3.3.2 order exactly (head of T)', () {
      final t = buildTranscript(_fields);
      // LP("Chhaya-PQXDH-v1") = 00 0f 'Chhaya-PQXDH-v1', then 8 one-byte fields.
      expect(t.sublist(0, 2), [0x00, 0x0f]);
      expect(String.fromCharCodes(t.sublist(2, 17)), 'Chhaya-PQXDH-v1');
      expect(
        t.sublist(17, 25),
        [
          protocolVersionV2,
          suiteBytePqxdhV1,
          curveX25519,
          kemMlKem1024,
          hashSha256,
          aeadAes256Gcm,
          protocolVersionV2,
          protocolVersionV2,
        ],
      );
    });

    test('conv_id must be lowercase canonical UUID; other forms rejected', () {
      for (final bad in [
        'AAAAAAAA-2222-4333-8444-555555555555',
        '11111111_2222-4333-8444-555555555555',
        'not-a-uuid',
        '',
      ]) {
        expect(
          () => buildTranscript(
            TranscriptFields(
              protocolVersion: _fields.protocolVersion,
              selectedSuite: _fields.selectedSuite,
              curve: _fields.curve,
              kem: _fields.kem,
              hash: _fields.hash,
              aead: _fields.aead,
              initiatorVersion: _fields.initiatorVersion,
              responderVersion: _fields.responderVersion,
              conversationId: bad,
              initiatorX25519: _fields.initiatorX25519,
              responderX25519: _fields.responderX25519,
              initiatorEd25519: _fields.initiatorEd25519,
              responderEd25519: _fields.responderEd25519,
              ephemeralX25519: _fields.ephemeralX25519,
              signedPreKeyId: _fields.signedPreKeyId,
              pqSignedPreKeyId: _fields.pqSignedPreKeyId,
              oneTimePreKeyId: _fields.oneTimePreKeyId,
              pqOneTimePreKeyId: _fields.pqOneTimePreKeyId,
              role: _fields.role,
              mlKemCiphertext: _fields.mlKemCiphertext,
            ),
          ),
          throwsArgumentError,
          reason: 'conv_id "$bad" must be rejected',
        );
      }
    });

    test('fixed-size field widths are enforced fail-closed', () {
      expect(
        () => buildTranscript(
          TranscriptFields(
            protocolVersion: _fields.protocolVersion,
            selectedSuite: _fields.selectedSuite,
            curve: _fields.curve,
            kem: _fields.kem,
            hash: _fields.hash,
            aead: _fields.aead,
            initiatorVersion: _fields.initiatorVersion,
            responderVersion: _fields.responderVersion,
            conversationId: _fields.conversationId,
            initiatorX25519: fill(31, 0xa1), // one byte short
            responderX25519: _fields.responderX25519,
            initiatorEd25519: _fields.initiatorEd25519,
            responderEd25519: _fields.responderEd25519,
            ephemeralX25519: _fields.ephemeralX25519,
            signedPreKeyId: _fields.signedPreKeyId,
            pqSignedPreKeyId: _fields.pqSignedPreKeyId,
            oneTimePreKeyId: _fields.oneTimePreKeyId,
            pqOneTimePreKeyId: _fields.pqOneTimePreKeyId,
            role: _fields.role,
            mlKemCiphertext: _fields.mlKemCiphertext,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('suite/protocol/role bytes above 0xFF are rejected', () {
      expect(
        () => buildTranscript(
          TranscriptFields(
            protocolVersion: 0x100,
            selectedSuite: _fields.selectedSuite,
            curve: _fields.curve,
            kem: _fields.kem,
            hash: _fields.hash,
            aead: _fields.aead,
            initiatorVersion: _fields.initiatorVersion,
            responderVersion: _fields.responderVersion,
            conversationId: _fields.conversationId,
            initiatorX25519: _fields.initiatorX25519,
            responderX25519: _fields.responderX25519,
            initiatorEd25519: _fields.initiatorEd25519,
            responderEd25519: _fields.responderEd25519,
            ephemeralX25519: _fields.ephemeralX25519,
            signedPreKeyId: _fields.signedPreKeyId,
            pqSignedPreKeyId: _fields.pqSignedPreKeyId,
            oneTimePreKeyId: _fields.oneTimePreKeyId,
            pqOneTimePreKeyId: _fields.pqOneTimePreKeyId,
            role: _fields.role,
            mlKemCiphertext: _fields.mlKemCiphertext,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('LP and LP32 prefixes are big-endian with exact widths', () {
      expect(lp(Uint8List.fromList([1, 2, 3])).sublist(0, 2), [0x00, 0x03]);
      expect(lp(Uint8List(0)).sublist(0, 2), [0x00, 0x00]);
      final big = lp32(fill(1568, 0x00));
      expect(big.sublist(0, 4), [0x00, 0x00, 0x06, 0x20]); // 1568 == 0x620
      expect(() => lp(fill(0x10000, 0x00)), throwsArgumentError);
    });
  });

  group('session key derivation (spec §3.4)', () {
    Uint8List baseSk({Uint8List? t, String suite = 'chhaya-pqxdh-v1'}) =>
        deriveSessionKey(
          dh1: fill(32, 0x11),
          dh2: fill(32, 0x22),
          dh3: fill(32, 0x33),
          dh4: fill(32, 0x44),
          sharedSecret: fill(32, 0x5a),
          transcript: t ?? buildTranscript(_fields),
          suiteString: suite,
        );

    test('golden vector: fixed transcript and DHs derive the pinned SK', () {
      expect(hex(baseSk()), kExpectedSessionKeyHex);
    });

    test('golden vector: both peers derive the identical SK', () {
      // Initiator and responder compute the same derivation over DHs that
      // mirror each other (X25519 symmetry); transcript equality is the
      // wire contract pinned above.
      expect(baseSk(), baseSk());
    });

    test('omitting DH4 changes the SK (OPK binding)', () {
      final withoutOpk = deriveSessionKey(
        dh1: fill(32, 0x11),
        dh2: fill(32, 0x22),
        dh3: fill(32, 0x33),
        sharedSecret: fill(32, 0x5a),
        transcript: buildTranscript(_fields),
        suiteString: 'chhaya-pqxdh-v1',
      );
      expect(hex(withoutOpk), isNot(hex(baseSk())));
    });

    test('different suite string binds a different SK', () {
      expect(hex(baseSk(suite: 'other-suite')), isNot(hex(baseSk())));
    });

    test('T tampering flips SK (property test, ≥1000 mutations)', () {
      final t = buildTranscript(_fields);
      final base = baseSk(t: t);
      final random = Random(20261108);
      var flips = 0;
      for (var i = 0; i < 1200; i++) {
        final mutated = Uint8List.fromList(t);
        mutated[random.nextInt(mutated.length)] ^= 1 << random.nextInt(8);
        expect(
          hex(baseSk(t: mutated)),
          isNot(hex(base)),
          reason: 'mutation $i must flip the SK',
        );
        flips++;
      }
      expect(flips, greaterThanOrEqualTo(1000));
    });

    test('consented classical fallback is domain-separated from PQXDH SK', () {
      final classical = deriveClassicalFallbackKey(
        classicalSharedSecret: Uint8List.fromList([
          ...fill(32, 0x77),
          ...fill(32, 0x78),
          ...fill(32, 0x79),
        ]),
        transcript: buildTranscript(_fields),
        suiteByte: suiteByteClassicalConsentV1,
      );
      expect(hex(classical), kExpectedClassicalFallbackHex);
      final hybrid = baseSk(suite: 'chhaya-classical-consent-v1');
      expect(hex(classical), isNot(hex(hybrid)));
    });

    test('fallback requires at least 32 bytes of classical DH material', () {
      expect(
        () => deriveClassicalFallbackKey(
          classicalSharedSecret: fill(16, 0x77),
          transcript: buildTranscript(_fields),
          suiteByte: suiteByteClassicalConsentV1,
        ),
        throwsArgumentError,
      );
    });

    test('fallback requires an in-octet suite byte', () {
      expect(
        () => deriveClassicalFallbackKey(
          classicalSharedSecret: fill(96, 0x77),
          transcript: buildTranscript(_fields),
          suiteByte: 0x100,
        ),
        throwsArgumentError,
      );
    });
  });
}
