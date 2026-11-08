// Hybrid PQXDH session establishment (V14 Part 5).
//
// Orchestrates one session establishment: X25519 (Part 1, audited)
// always runs; the PQ KEM runs when an approved provider exists.
// Output is a [HybridSecret] whose flags record exactly what
// contributed — callers (Part 4 TripleRatchet) feed it forward, and
// UI (Part 8) surfaces non-PQ sessions honestly.
import 'dart:typed_data';

import '../primitives/x25519.dart';
import 'hybrid_kex.dart';
import 'negotiation.dart';
import 'pqc_provider.dart';
import 'prekey_bundle.dart';
import 'transcript.dart';

/// Establishes hybrid session secrets.
class Pqxdh {
  Pqxdh._();

  /// Runs X25519 against [remotePublicKey] with our fresh keypair and
  /// combines with [pqKem] output. Without an available KEM the call
  /// fails closed unless [allowClassicalFallback] AND [userConsented]
  /// are both true.
  ///
  /// Returns the ML-KEM encapsulation ciphertext alongside the secret —
  /// callers must transmit it to the peer — and the ephemeral X25519
  /// public key. [encapsulationCiphertext] is null in consented
  /// classical-fallback mode.
  static Future<({HybridSecret secret, Uint8List ourPublicKey, Uint8List? encapsulationCiphertext})> establish({
    required Uint8List remotePublicKey,
    PqKem? pqKem,
    Uint8List? pqPublicKey,
    required Uint8List context,
    bool allowClassicalFallback = false,
    bool userConsented = false,
  }) async {
    final ours = await X25519Kex.generateKeyPair();
    late final Uint8List classical;
    try {
      classical = await X25519Kex.sharedSecret(
        ours.privateKey,
        remotePublicKey,
      );
    } finally {
      ours.privateKey.fillRange(0, ours.privateKey.length, 0);
    }
    try {
      if (pqKem != null && pqPublicKey != null && await pqKem.initialize()) {
        final enc = await pqKem.encapsulate(pqPublicKey);
        late final HybridSecret secret;
        try {
          secret = HybridKex.combine(
            classical: classical,
            pq: enc.sharedSecret,
            context: context,
          );
        } finally {
          enc.sharedSecret.fillRange(0, enc.sharedSecret.length, 0);
        }
        return (
          secret: secret,
          ourPublicKey: ours.publicKey,
          encapsulationCiphertext: enc.ciphertext,
        );
      }
      if (!allowClassicalFallback || !userConsented) {
        throw StateError(
          'No approved PQ KEM available and classical fallback was '
          'not consented. Refusing to establish.',
        );
      }
      final secret = HybridKex.classicalFallback(
        classical: classical,
        context: context,
        userConsented: true,
      );
      return (
        secret: secret,
        ourPublicKey: ours.publicKey,
        encapsulationCiphertext: null,
      );
    } finally {
      // Classical output is consumed into the combiner; wipe the copy.
      for (var i = 0; i < classical.length; i++) {
        classical[i] = 0;
      }
    }
  }

  // ---------------------------------------------------------------------
  // vNext hybrid establishment (spec §3.1–§3.5). Not wired into production
  // messaging; WS3 gates it behind chhaya_pq_hybrid_v1. Both roles derive
  // the identical SK from the exchanged flight; a mismatch means AEAD
  // fails and the session aborts (spec §3.3.2, §3.6).
  // ---------------------------------------------------------------------

  static void _checkStageForEstablish(Negotiation negotiation) {
    if (negotiation.stage != NegotiationStage.suiteSelected ||
        negotiation.selected == null) {
      throw StateError(
        'suite must be selected before establishment '
        '(stage: ${negotiation.stage})',
      );
    }
  }

  static Uint8List _buildTranscript({
    required int selectedSuiteByte,
    required int initiatorVersion,
    required int responderVersion,
    required String conversationId,
    required Uint8List initiatorX25519,
    required Uint8List responderX25519,
    required Uint8List initiatorEd25519,
    required Uint8List responderEd25519,
    required Uint8List ephemeralX25519,
    required String signedPreKeyId,
    required String pqSignedPreKeyId,
    required String? oneTimePreKeyId,
    required String? pqOneTimePreKeyId,
    required Uint8List mlKemCiphertext,
  }) =>
      buildEstablishmentTranscript(
        selectedSuiteByte: selectedSuiteByte,
        initiatorVersion: initiatorVersion,
        responderVersion: responderVersion,
        conversationId: conversationId,
        initiatorX25519: initiatorX25519,
        responderX25519: responderX25519,
        initiatorEd25519: initiatorEd25519,
        responderEd25519: responderEd25519,
        ephemeralX25519: ephemeralX25519,
        signedPreKeyId: signedPreKeyId,
        pqSignedPreKeyId: pqSignedPreKeyId,
        oneTimePreKeyId: oneTimePreKeyId,
        pqOneTimePreKeyId: pqOneTimePreKeyId,
        mlKemCiphertext: mlKemCiphertext,
      );

  /// Initiator half of the v2 establishment (spec §3.5 first flight).
  ///
  /// Encapsulates to the responder's PQ prekey (popped PQ one-time prekey
  /// when the bundle carried one, else the in-window last-resort PQSPK),
  /// derives the SK, and returns everything the initiator must send and
  /// later bind into AEAD additional data. Single attempt only — there is
  /// no retry loop and no fallback to weaker parameters (spec §3.6).
  ///
  /// Caller wipes [result.secret.secret] and retains [result.transcript]
  /// for AD. The responder rebuilds the identical T from public material
  /// plus its own prekey private keys only.
  static Future<({
    HybridSecret secret,
    Uint8List ephemeralPublicKey,
    Uint8List mlKemCiphertext,
    Uint8List transcript,
  })> establishHybridV2({
    required Negotiation negotiation,
    required Uint8List ourIdentityPrivateKey, // X25519, 32 bytes
    required Uint8List ourIdentityPublicKey,  // X25519, 32 bytes
    required Uint8List ourEd25519PublicKey,   // 32 bytes (for T)
    required PrekeyBundle responderBundle,    // already verified
    required String conversationId,
    required bool userConsented,
    PqKem? pqKem,
  }) async {
    _checkStageForEstablish(negotiation);
    final suite = negotiation.selected!;
    final ours = await X25519Kex.generateKeyPair();
    final dh1 = await X25519Kex.sharedSecret(
      ourIdentityPrivateKey,
      responderBundle.signedPreKey.publicKey,
    );
    final dh2 = await X25519Kex.sharedSecret(
      ours.privateKey,
      responderBundle.identityX25519,
    );
    final dh3 = await X25519Kex.sharedSecret(
      ours.privateKey,
      responderBundle.signedPreKey.publicKey,
    );
    final opk = responderBundle.oneTimePreKey;
    final dh4 = opk == null
        ? null
        : await X25519Kex.sharedSecret(ours.privateKey, opk.publicKey);
    try {
      Uint8List transcriptBase(Uint8List ct) => _buildTranscript(
            selectedSuiteByte: suite.byte,
            initiatorVersion: protocolVersionV2,
            responderVersion: protocolVersionV2,
            conversationId: conversationId,
            initiatorX25519: ourIdentityPublicKey,
            responderX25519: responderBundle.identityX25519,
            initiatorEd25519: ourEd25519PublicKey,
            responderEd25519: responderBundle.identityEd25519,
            ephemeralX25519: ours.publicKey,
            signedPreKeyId: responderBundle.signedPreKey.keyId,
            pqSignedPreKeyId: responderBundle.pqSignedPreKey.keyId,
            oneTimePreKeyId: opk?.keyId,
            pqOneTimePreKeyId: responderBundle.pqOneTimePreKey?.keyId,
            mlKemCiphertext: ct,
          );
      if (suite == Suite.classicalConsentV1) {
        // Consent path — domain-separated, flagged nonPQ (spec §3.4–§3.5).
        if (negotiation.pqAvailable) {
          negotiation.abort('classical suite selected with PQ provider present');
        }
        if (!userConsented) {
          negotiation.abort('classical fallback requires explicit consent');
        }
        final t = transcriptBase(Uint8List(0)); // no CT on the classical path
        final dhs = Uint8List.fromList([...dh1, ...dh2, ...dh3, if (dh4 != null) ...dh4]);
        try {
          final sk = deriveClassicalFallbackKey(
            classicalSharedSecret: dhs,
            transcript: t,
            suiteByte: suite.byte,
          );
          return (
            secret: HybridSecret(
              secret: sk,
              pqUsed: false,
              classicalUsed: true,
              consentedFallback: true,
            ),
            ephemeralPublicKey: ours.publicKey,
            mlKemCiphertext: Uint8List(0),
            transcript: t,
          );
        } finally {
          dhs.fillRange(0, dhs.length, 0);
        }
      }
      if (pqKem == null) {
        // Fail closed: never retry with classical inside PQ negotiation.
        negotiation.abort('PQ KEM unavailable during PQXDH establishment');
      }
      if (!await pqKem.initialize()) {
        negotiation.abort('PQ KEM provider failed self-check');
      }
      final target = responderBundle.pqOneTimePreKey?.publicKey ??
          responderBundle.pqSignedPreKey.publicKey;
      final Uint8List ct;
      final Uint8List ss;
      try {
        final enc = await pqKem.encapsulate(target);
        ct = enc.ciphertext;
        ss = enc.sharedSecret;
      } on Object {
        // Spec §3.6: provider failure ⇒ hard abort, never EC-only.
        negotiation.abort('ML-KEM encapsulation failure');
      }
      try {
        final t = transcriptBase(ct);
        final sk = deriveSessionKey(
          dh1: dh1,
          dh2: dh2,
          dh3: dh3,
          dh4: dh4,
          sharedSecret: ss,
          transcript: t,
          suiteString: suite.id,
        );
        return (
          secret: HybridSecret(
            secret: sk,
            pqUsed: true,
            classicalUsed: true,
            consentedFallback: false,
          ),
          ephemeralPublicKey: ours.publicKey,
          mlKemCiphertext: ct,
          transcript: t,
        );
      } finally {
        ss.fillRange(0, ss.length, 0);
      }
    } finally {
      ours.privateKey.fillRange(0, ours.privateKey.length, 0);
      dh1.fillRange(0, dh1.length, 0);
      dh2.fillRange(0, dh2.length, 0);
      dh3.fillRange(0, dh3.length, 0);
      dh4?.fillRange(0, dh4.length, 0);
    }
  }

  /// Responder half of the v2 establishment (spec §3.3.2 — the peer builds
  /// the identical T from public material plus its own prekey private keys).
  ///
  /// [oneTimePreKeyId]/[pqOneTimePreKeyId] are the ids the responder served
  /// in its bundle and the initiator bound into T (null when unused, e.g.
  /// the last-resort PQSPK path). Decapsulation failure is a hard abort
  /// (spec §3.6) — never a fall back to EC-only.
  static Future<({HybridSecret secret, Uint8List transcript})> acceptHybridV2({
    required Negotiation negotiation,
    required Uint8List ourIdentityPrivateKey,  // responder X25519
    required Uint8List ourIdentityPublicKey,   // responder X25519 public
    required Uint8List ourEd25519PublicKey,    // responder Ed25519 (for T)
    required Uint8List peerIdentityX25519,     // initiator X25519 public
    required Uint8List peerEd25519PublicKey,   // initiator Ed25519 (for T)
    required Uint8List ourSignedPreKeyPrivateKey,
    required String signedPreKeyId,
    required Uint8List ourPqSignedPreKeyPrivateKey,
    required String pqSignedPreKeyId,
    Uint8List? ourOneTimePreKeyPrivateKey,
    String? oneTimePreKeyId,
    Uint8List? ourPqOneTimePreKeyPrivateKey,
    String? pqOneTimePreKeyId,
    required Uint8List peerEphemeralPublicKey,
    required Uint8List mlKemCiphertext,
    required String conversationId,
    required bool userConsented,
    PqKem? pqKem,
  }) async {
    _checkStageForEstablish(negotiation);
    final suite = negotiation.selected!;
    if ((ourOneTimePreKeyPrivateKey == null) != (oneTimePreKeyId == null)) {
      throw ArgumentError('oneTimePreKeyId and key must be both set or both null');
    }
    if ((ourPqOneTimePreKeyPrivateKey == null) != (pqOneTimePreKeyId == null)) {
      throw ArgumentError(
        'pqOneTimePreKeyId and key must be both set or both null',
      );
    }
    final dh1 = await X25519Kex.sharedSecret(
      ourSignedPreKeyPrivateKey,
      peerIdentityX25519,
    );
    final dh2 = await X25519Kex.sharedSecret(
      ourIdentityPrivateKey,
      peerEphemeralPublicKey,
    );
    final dh3 = await X25519Kex.sharedSecret(
      ourSignedPreKeyPrivateKey,
      peerEphemeralPublicKey,
    );
    final dh4 = ourOneTimePreKeyPrivateKey == null
        ? null
        : await X25519Kex.sharedSecret(
            ourOneTimePreKeyPrivateKey,
            peerEphemeralPublicKey,
          );
    try {
      Uint8List transcriptBase(Uint8List ct) => _buildTranscript(
            selectedSuiteByte: suite.byte,
            initiatorVersion: protocolVersionV2,
            responderVersion: protocolVersionV2,
            conversationId: conversationId,
            initiatorX25519: peerIdentityX25519,
            responderX25519: ourIdentityPublicKey,
            initiatorEd25519: peerEd25519PublicKey,
            responderEd25519: ourEd25519PublicKey,
            ephemeralX25519: peerEphemeralPublicKey,
            signedPreKeyId: signedPreKeyId,
            pqSignedPreKeyId: pqSignedPreKeyId,
            oneTimePreKeyId: oneTimePreKeyId,
            pqOneTimePreKeyId: pqOneTimePreKeyId,
            mlKemCiphertext: ct,
          );
      if (suite == Suite.classicalConsentV1) {
        if (negotiation.pqAvailable) {
          negotiation.abort('classical suite selected with PQ provider present');
        }
        if (!userConsented) {
          negotiation.abort('classical fallback requires explicit consent');
        }
        final t = transcriptBase(Uint8List(0)); // no CT on the classical path
        final dhs = Uint8List.fromList([...dh1, ...dh2, ...dh3, if (dh4 != null) ...dh4]);
        try {
          final sk = deriveClassicalFallbackKey(
            classicalSharedSecret: dhs,
            transcript: t,
            suiteByte: suite.byte,
          );
          return (
            secret: HybridSecret(
              secret: sk,
              pqUsed: false,
              classicalUsed: true,
              consentedFallback: true,
            ),
            transcript: t,
          );
        } finally {
          dhs.fillRange(0, dhs.length, 0);
        }
      }
      if (pqKem == null) {
        negotiation.abort('PQ KEM unavailable during PQXDH acceptance');
      }
      final Uint8List ss;
      try {
        ss = pqOneTimePreKeyId != null
            ? await pqKem.decapsulate(
                ourPqOneTimePreKeyPrivateKey!,
                mlKemCiphertext,
              )
            : await pqKem.decapsulate(
                ourPqSignedPreKeyPrivateKey,
                mlKemCiphertext,
              );
      } on Object {
        // Spec §3.6: decapsulation failure ⇒ abort, wipe SK material.
        for (final dh in [dh1, dh2, dh3, if (dh4 != null) dh4]) {
          dh.fillRange(0, dh.length, 0);
        }
        negotiation.abort('ML-KEM decapsulation failure');
      }
      final t = transcriptBase(mlKemCiphertext);
      try {
        final sk = deriveSessionKey(
          dh1: dh1,
          dh2: dh2,
          dh3: dh3,
          dh4: dh4,
          sharedSecret: ss,
          transcript: t,
          suiteString: suite.id,
        );
        return (
          secret: HybridSecret(
            secret: sk,
            pqUsed: true,
            classicalUsed: true,
            consentedFallback: false,
          ),
          transcript: t,
        );
      } finally {
        ss.fillRange(0, ss.length, 0);
      }
    } finally {
      dh1.fillRange(0, dh1.length, 0);
      dh2.fillRange(0, dh2.length, 0);
      dh3.fillRange(0, dh3.length, 0);
      dh4?.fillRange(0, dh4.length, 0);
    }
  }
}
