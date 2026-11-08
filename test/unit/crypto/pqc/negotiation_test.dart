// Negotiation state machine (spec §3.5, §3.6) and suite registry tests.
import 'dart:typed_data';

import 'package:chaaya/core/crypto/pqc/negotiation.dart';
import 'package:chaaya/core/crypto/pqc/transcript.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('suite registry (spec §3.0)', () {
    test('registered suites round-trip string <-> byte', () {
      expect(suiteFromString('chhaya-pqxdh-v1'), Suite.chhayaPqxdhV1);
      expect(
        suiteFromString('chhaya-classical-consent-v1'),
        Suite.classicalConsentV1,
      );
      expect(Suite.chhayaPqxdhV1.byte, suiteBytePqxdhV1);
      expect(Suite.classicalConsentV1.byte, suiteByteClassicalConsentV1);
      expect(suiteFromByte(0x01), Suite.chhayaPqxdhV1);
      expect(suiteFromByte(0x02), Suite.classicalConsentV1);
    });

    test('u8 edge cases fail closed', () {
      for (final b in [0x00, 0x03, 0x7f, 0x80, 0xff]) {
        expect(() => suiteFromByte(b), throwsArgumentError,
            reason: 'byte 0x${b.toRadixString(16)} must be rejected');
      }
      expect(() => suiteFromByte(-1), throwsArgumentError);
      expect(() => suiteFromByte(0x100), throwsArgumentError);
    });

    test('malformed suite strings fail closed', () {
      for (final s in [
        '',
        'chhaya-pqxdh-v1 ', // trailing space
        ' chhaya-pqxdh-v1',
        'CHHAYA-PQXDH-V1', // case is significant
        'chhaya-pqxdh-v2',
        'Chhaya-PQXDH-v1', // the transcript label is not a suite
        'chhaya-classical-consent-v2',
        'spqr',
        'chhaya-pqxdh-v1\u0000',
        'chhaya-pqxdh-v1\u0080',
        'x' * 1000,
      ]) {
        expect(() => suiteFromString(s), throwsArgumentError,
            reason: '"$s" must be rejected');
      }
    });

    test('client version range is exactly v2 (spec §3.0)', () {
      expect(clientMinProtocolVersion, 0x02);
      expect(clientMaxProtocolVersion, 0x02);
    });
  });

  group('highest-common selection (spec §3.5 rule 2)', () {
    test('selects the higher-priority common suite', () {
      final selected = highestCommonSuite(
        [Suite.classicalConsentV1, Suite.chhayaPqxdhV1],
        [Suite.classicalConsentV1, Suite.chhayaPqxdhV1],
      );
      expect(selected, Suite.chhayaPqxdhV1);
    });

    test('order of the offer list does not change the outcome', () {
      final a = highestCommonSuite(
        [Suite.chhayaPqxdhV1],
        [Suite.classicalConsentV1, Suite.chhayaPqxdhV1],
      );
      final b = highestCommonSuite(
        [Suite.chhayaPqxdhV1],
        [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
      );
      expect(a, b);
    });

    test('classical-only intersection selects classical', () {
      final selected = highestCommonSuite(
        [Suite.classicalConsentV1],
        [Suite.classicalConsentV1],
      );
      expect(selected, Suite.classicalConsentV1);
    });

    test('no common suite aborts', () {
      expect(
        () => highestCommonSuite(
          [Suite.chhayaPqxdhV1],
          [Suite.classicalConsentV1],
        ),
        throwsA(isA<NoCommonSuiteException>()),
      );
      expect(
        () => highestCommonSuite([], [Suite.chhayaPqxdhV1]),
        throwsA(isA<NoCommonSuiteException>()),
      );
    });
  });

  group('offer echo (spec §3.5 rule 3)', () {
    test('byte-for-byte echo verifies', () {
      expect(
        verifyOfferEcho(
          [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
          [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
        ),
        isTrue,
      );
    });

    test('reordered, truncated, duplicated, or mutated echo fails', () {
      expect(
        verifyOfferEcho(
          [Suite.chhayaPqxdhV1],
          [Suite.classicalConsentV1],
        ),
        isFalse,
      );
      expect(
        verifyOfferEcho(
          [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
          [Suite.classicalConsentV1, Suite.chhayaPqxdhV1],
        ),
        isFalse,
      );
      expect(
        verifyOfferEcho(
          [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
          [Suite.chhayaPqxdhV1],
        ),
        isFalse,
      );
      expect(
        verifyOfferEcho(
          [Suite.chhayaPqxdhV1],
          [Suite.chhayaPqxdhV1, Suite.chhayaPqxdhV1],
        ),
        isFalse,
      );
    });
  });

  group('negotiation state machine (spec §3.5, §3.6)', () {
    Negotiation fresh({bool pqAvailable = true}) => Negotiation(
          ownOffers: const [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
          pqAvailable: pqAvailable,
        );

    test('happy path: offer → echo → suiteSelected → established', () {
      final n = fresh();
      n.sendOffer();
      final suite = n.receiveBundleEcho(
        echoedOffers: const [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
        peerOffers: const [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
        userConsented: false,
      );
      expect(suite, Suite.chhayaPqxdhV1);
      expect(n.selected, Suite.chhayaPqxdhV1);
      n.markEstablished();
      expect(n.stage, NegotiationStage.established);
    });

    test('echo mismatch aborts', () {
      final n = fresh();
      n.sendOffer();
      expect(
        () => n.receiveBundleEcho(
          echoedOffers: const [Suite.classicalConsentV1],
          peerOffers: const [Suite.chhayaPqxdhV1],
          userConsented: false,
        ),
        throwsA(isA<NegotiationAborted>()),
      );
      expect(n.stage, NegotiationStage.aborted);
    });

    test('no common suite aborts', () {
      final n = Negotiation(
        ownOffers: const [Suite.chhayaPqxdhV1],
        pqAvailable: true,
      );
      n.sendOffer();
      expect(
        () => n.receiveBundleEcho(
          echoedOffers: const [Suite.chhayaPqxdhV1],
          peerOffers: const [Suite.classicalConsentV1],
          userConsented: false,
        ),
        throwsA(isA<NegotiationAborted>()),
      );
      expect(n.stage, NegotiationStage.aborted);
    });

    test(
      'classical selected but PQ provider present aborts even with consent',
      () {
        final n = Negotiation(
          ownOffers: const [Suite.classicalConsentV1],
          pqAvailable: true,
        );
        n.sendOffer();
        expect(
          () => n.receiveBundleEcho(
            echoedOffers: const [Suite.classicalConsentV1],
            peerOffers: const [Suite.classicalConsentV1],
            userConsented: true,
          ),
          throwsA(isA<NegotiationAborted>()),
        );
      },
    );

    test('classical selected without consent aborts (no silent fallback)', () {
      final n = Negotiation(
        ownOffers: const [Suite.classicalConsentV1],
        pqAvailable: false,
      );
      n.sendOffer();
      expect(
        () => n.receiveBundleEcho(
          echoedOffers: const [Suite.classicalConsentV1],
          peerOffers: const [Suite.classicalConsentV1],
          userConsented: false,
        ),
        throwsA(isA<NegotiationAborted>()),
      );
    });

    test(
      'classical selected with PQ unavailable and consent proceeds, flagged',
      () {
        final n = Negotiation(
          ownOffers: const [Suite.classicalConsentV1],
          pqAvailable: false,
        );
        n.sendOffer();
        final suite = n.receiveBundleEcho(
          echoedOffers: const [Suite.classicalConsentV1],
          peerOffers: const [Suite.classicalConsentV1],
          userConsented: true,
        );
        expect(suite, Suite.classicalConsentV1);
        n.markEstablished();
      },
    );

    test('illegal transitions fail closed', () {
      final n = fresh();
      expect(
        () => n.receiveBundleEcho(
          echoedOffers: const [Suite.chhayaPqxdhV1],
          peerOffers: const [Suite.chhayaPqxdhV1],
          userConsented: false,
        ),
        throwsStateError,
      );
      expect(() => n.markEstablished(), throwsStateError);
      expect(() => n.sendOffer(), returnsNormally);
      expect(() => n.sendOffer(), throwsStateError);
    });

    test('AEAD failure is a hard abort and wipes the SK buffer', () {
      final n = fresh();
      n.sendOffer();
      n.receiveBundleEcho(
        echoedOffers: const [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
        peerOffers: const [Suite.chhayaPqxdhV1],
        userConsented: false,
      );
      final sk = Uint8List.fromList(List.filled(32, 0x5a));
      expect(
        () => n.recordAeadFailure(sk: sk),
        throwsA(isA<NegotiationAborted>()),
      );
      expect(sk, everyElement(0), reason: 'SK material must be wiped');
      expect(n.stage, NegotiationStage.aborted);
    });

    test('aborted negotiation has no path to establishment', () {
      final n = fresh();
      n.sendOffer();
      try {
        n.receiveBundleEcho(
          echoedOffers: const [Suite.classicalConsentV1],
          peerOffers: const [Suite.chhayaPqxdhV1],
          userConsented: false,
        );
        fail('expected abort');
      } on NegotiationAborted {
        // expected
      }
      expect(() => n.markEstablished(), throwsStateError);
      expect(
        () => n.receiveBundleEcho(
          echoedOffers: const [Suite.chhayaPqxdhV1],
          peerOffers: const [Suite.chhayaPqxdhV1],
          userConsented: false,
        ),
        throwsStateError,
      );
    });

    test('retry with weaker suite after selection is forbidden', () {
      final n = Negotiation(
        ownOffers: const [Suite.chhayaPqxdhV1],
        pqAvailable: true,
      );
      n.sendOffer();
      n.receiveBundleEcho(
        echoedOffers: const [Suite.chhayaPqxdhV1],
        peerOffers: const [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
        userConsented: false,
      );
      expect(
        () => n.assertNoDowngradeRetry(Suite.classicalConsentV1),
        throwsA(isA<DowngradeRetryForbidden>()),
      );
      // Same suite is not weaker; the assertion itself passes.
      expect(
        () => n.assertNoDowngradeRetry(Suite.chhayaPqxdhV1),
        returnsNormally,
      );
    });
  });
}
