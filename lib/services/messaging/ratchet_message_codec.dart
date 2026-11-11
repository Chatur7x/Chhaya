// Authenticated messaging envelopes: legacy v1 (classical, receive-only
// migration window) and v2 (hybrid PQXDH, spec §3). Callers serialize
// operations per account. In v2, AEAD additional data is
// `msgAad ‖ header ‖ T` (spec §3.4, SD-4) and the transcript T persists
// with the session; any mismatch hard-aborts, never weakens.
//
// Restore behaviour (spec §2.1, §3.7): after `replaceAccountSnapshot`, the
// first post-restore contact runs a fresh v2 establishment (never a
// deterministic re-derivation) and sends `chhaya-resync-v1` before any user
// content. Offline peers receive it via the existing store-and-forward
// path. The deterministic identity-ECDH establishment path is removed.
//
// The resync handshake for the *responder* side (adopt/mark/ack) executes
// in messaging_service.dart, which owns the transport and the own-server-id
// for the ack envelope.
import 'dart:convert';
import 'dart:typed_data';

import '../../core/crypto/chhaya_crypto_engine.dart';
import '../../core/crypto/primitives/aes_gcm.dart';
import '../../core/crypto/primitives/rng.dart';
import '../../core/crypto/ratchet/session_store.dart';
import '../../core/crypto/ratchet/session_state.dart';
import '../../core/crypto/ratchet/triple_ratchet.dart';
import '../../core/crypto/pqc/ml_kem.dart';
import '../../core/crypto/pqc/negotiation.dart';
import '../../core/crypto/pqc/pqc_provider.dart';
import '../../core/crypto/pqc/pqxdh.dart';
import '../../core/crypto/pqc/prekey_bundle.dart';
import '../../core/database/local_database.dart';
import '../../core/models/contact.dart';
import '../../core/log.dart';
import 'pq_hybrid_v1.dart';

/// JSON payload types of the resync handshake (spec §3.7). Both ride the
/// normal encrypted ratchet envelope; the server sees opaque content.
const String resyncPayloadType = 'chhaya-resync-v1';
const String resyncAckPayloadType = 'chhaya-resync-ack-v1';

final RegExp _uuidRe = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i + 1 < hex.length; i += 2) {
    out[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return out;
}

String _bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List peerPublicKeyBytes(String chhayaId) {
  if (!RegExp(r'^05[0-9a-f]{64}$').hasMatch(chhayaId)) {
    throw StateError('Invalid contact identity');
  }
  return _hexToBytes(chhayaId.substring(2));
}

bool _bytesEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Authenticated message envelopes. Callers serialize operations per
/// account. Ratchet state is committed only after successful authentication.
class RatchetMessageCodec {
  final SessionStorage sessions;
  final ChhayaKeyPair identity;
  final String ownId;

  /// Production: messaging_service builds this from the authenticated
  /// ApiService (`PrekeyBundleClient`); tests inject a fake prekey server.
  final Future<PrekeyBundle> Function(String userId)? bundleFetcher;

  /// Optional so in-memory unit tests can still exercise the v2 crypto
  /// round trip. Resync bookkeeping lives in this database (spec §3.7–§3.8).
  final LocalDatabase? database;

  /// Ed25519 identity public-key seam. Production wires this to
  /// `KeyManager.getIdentityEd25519PublicKeyBytes()`; the transcript binds
  /// these 32 bytes (spec §3.3).
  final Future<Uint8List> Function()? ed25519PublicKey;

  RatchetMessageCodec({
    required this.sessions,
    required this.identity,
    required this.ownId,
    this.bundleFetcher,
    this.database,
    this.ed25519PublicKey,
  });

  String _key(String conversation, Contact peer) =>
      '$conversation:${peer.chhayaId.publicKey}';

  static String legacyKey(String key) => '$key#legacy';

  Uint8List _aad(String conversation, String messageId, String sender) =>
      Uint8List.fromList(
        utf8.encode(
          jsonEncode(['chhaya-message-v1', conversation, messageId, sender]),
        ),
      );

  Uint8List _aadV2(
    String conversation,
    String messageId,
    String sender,
    Uint8List transcript,
    Uint8List header,
  ) =>
      Uint8List.fromList([
        ..._aad(conversation, messageId, sender),
        ...header,
        ...transcript,
      ]);

  // ---- capability probe + offer lists (spec §3.5 rules 2/5) ----
  Future<bool> _pqAvailable() async {
    if (PqHybridV1.testKem != null) return true;
    try {
      final kem = MlKem1024(); // arm64 only; stub throws elsewhere → false
      return kem.isAvailable && await kem.initialize();
    } catch (_) {
      return false;
    }
  }

  Future<PqKem?> _kem() async {
    if (PqHybridV1.testKem != null) return PqHybridV1.testKem;
    return await _pqAvailable() ? MlKem1024() : null;
  }

  List<Suite> ownOffers(bool pqAvailable, bool userConsented) {
    if (pqAvailable) return const [Suite.chhayaPqxdhV1];
    if (userConsented) return const [Suite.classicalConsentV1];
    return const []; // fail closed: no silent classical without consent
  }

  Future<List<Suite>> _ownOffers() async =>
      ownOffers(await _pqAvailable(), await PqHybridV1.userConsented());

  /// Wire form of our own offers (suite ids in registry order), used for
  /// the echo in the responder's first outbound v2 envelope (spec §3.5 rule 3).
  Future<List<String>> ownOfferEcho() async =>
      [for (final suite in await _ownOffers()) suite.id];

  Future<Future<PrekeyBundle> Function(String)> _fetcher() async {
    if (bundleFetcher != null) return bundleFetcher!;
    final test = PqHybridV1.testBundleFetcher;
    if (test != null) return test;
    throw StateError('No prekey bundle source configured');
  }

  Future<Uint8List> _ownEd25519() async {
    final fn = ed25519PublicKey;
    if (fn == null) {
      throw StateError('Ed25519 identity public-key seam not configured');
    }
    final key = await fn();
    if (key.length != 32) {
      throw StateError('Ed25519 public key must be 32 bytes');
    }
    return key;
  }

  // ---- session_generation consistency (spec §3.8) ----
  /// Bookkeeping failures are non-fatal (e.g. in-memory test databases):
  /// the cryptographic session never depends on the kv store. Errors are
  /// logged, never swallowed silently for evidence threads.
  Future<T?> _soft<T>(Future<T?> Function(LocalDatabase db) fn) async {
    final db = database;
    if (db == null) return null;
    try {
      return await fn(db);
    } catch (error) {
      ChhayaLog.w('session bookkeeping skipped: $error',
          name: 'RatchetMessageCodec');
      return null;
    }
  }

  /// For an establishing/forced-resync path: rollback ⇒ wipe stale blob and
  /// mark the conversation pending; establishment proceeds fresh.
  Future<void> _forceResyncIfRollback(String conversation, String key) async {
    final state = await _soft((db) => db.sessionGenerationState(conversation));
    if (state != 'rollback') return;
    ChhayaLog.w(
      'session_generation rollback detected; forcing resync',
      name: 'RatchetMessageCodec',
    );
    try {
      await sessions.deleteSession(key);
    } catch (_) {
      // Best effort; establishment proceeds regardless.
    }
    await _soft((db) =>
        db.markResyncPending(conversation, reason: 'rollback'));
  }

  /// For the decrypt path: rollback ⇒ never decrypt under stale state.
  Future<void> _refuseStaleGeneration(String conversation, String key) async {
    final state = await _soft((db) => db.sessionGenerationState(conversation));
    if (state != 'rollback') return;
    ChhayaLog.w(
      'session_generation rollback detected; refusing to decrypt',
      name: 'RatchetMessageCodec',
    );
    await _soft((db) =>
        db.markResyncPending(conversation, reason: 'rollback'));
    try {
      await sessions.deleteSession(key);
    } catch (_) {
      // Best effort; the refusal itself is what enforces fail-closed.
    }
    throw StateError('session_generation rollback; resync forced');
  }

  Future<int> generationMax(String conversation) async =>
      (await _soft((db) async {
        final pair = await db.readSessionGenerationPair(conversation);
        final dbValue = pair.db ?? 0;
        final ksValue = pair.keystore ?? 0;
        return dbValue > ksValue ? dbValue : ksValue;
      })) ??
      0;

  /// Writes max(db, keystore) + 1 to both stores, keystore first (spec §3.8).
  /// Adopting the higher value is the only non-decreasing choice.
  Future<void> incrementGeneration(String conversation) async {
    final next = (await generationMax(conversation)) + 1;
    await _soft((db) => db.writeSessionGeneration(conversation, next));
  }

  /// `peer_v2/<conversation>`: set when any AEAD-valid v2 envelope arrived
  /// from the peer. The only evidence a legacy (v1) peer supports v2, so a
  /// legacy session migrates only after it has been proven (criterion 10).
  static String peerV2Key(String conversation) => 'peer_v2/$conversation';

  Future<bool> _peerV2Known(String conversation) async =>
      (await _soft((db) => db.readPlainKv(peerV2Key(conversation)))) == '1';

  Future<void> _markPeerV2Known(String conversation) async {
    await _soft((db) => db.writePlainKv(peerV2Key(conversation), '1'));
  }

  /// v1 sessions are kept as a `#legacy` copy for receive-only decrypt
  /// after migration to v2 (spec §3.11). Sends never use it once v2 exists.
  Future<void> _retainLegacySession(String key) async {
    await _soft((db) async {
      final raw = await db.loadSessionBlob(key);
      if (raw != null) {
        await db.saveSessionBlob(legacyKey(key), raw);
      }
    });
  }

  Future<SessionState?> _loadLegacySession(String key) async =>
      _soft((db) async {
        final raw = await db.loadSessionBlob(legacyKey(key));
        if (raw == null) return null;
        try {
          return SessionState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        } catch (_) {
          return null;
        }
      });

  /// Initiator-side ack rule (spec §3.7): any AEAD-valid v2 inbound under a
  /// conversation with a pending resync is the ack.
  Future<void> _ackIfPending(String conversation) async {
    final pending = await _soft((db) => db.readResyncPending(conversation));
    if (pending == null) return;
    await _soft((db) =>
        db.adoptRestoreGeneration(conversation, pending.restoreGeneration));
    await _soft((db) =>
        db.deletePlainKv(LocalDatabase.resyncPendingKey(conversation)));
    await incrementGeneration(conversation);
    await _soft((db) =>
        db.writePlainKv(LocalDatabase.resyncResumeKey(conversation), '1'));
    ChhayaLog.i(
      'resync acknowledged; pending queue resumable',
      name: 'RatchetMessageCodec',
    );
  }

  // ---- v2 establishment (initiator) ----
  Future<({SessionState state, Map<String, dynamic> flight})> _establishV2(
    Contact peer,
    String conversation,
  ) async {
    final key = _key(conversation, peer);
    await _forceResyncIfRollback(conversation, key);
    final pqAvailable = await _pqAvailable();
    final consented = await PqHybridV1.userConsented();
    final myOffers = ownOffers(pqAvailable, consented);
    if (myOffers.isEmpty) {
      throw const NegotiationAborted('This device cannot offer any suite');
    }
    final fetch = await _fetcher();
    final bundle = await fetch(peer.id);
    final peerPub = peerPublicKeyBytes(peer.chhayaId.publicKey);
    if (!_bytesEq(bundle.identityX25519, peerPub)) {
      throw StateError(
        "Contact's prekey bundle does not match their verified identity",
      );
    }
    final ourEd = await _ownEd25519();
    final negotiation = Negotiation(ownOffers: myOffers, pqAvailable: pqAvailable);
    negotiation.sendOffer();
    // Registry-fixed lists: both peers compute the same selection; the
    // responder echo is verified on its first v2 envelope (spec §3.5 rule 3).
    final selected = negotiation.receiveBundleEcho(
      echoedOffers: myOffers,
      peerOffers: myOffers,
      userConsented: consented,
    );
    final kem = await _kem();
    if (selected == Suite.chhayaPqxdhV1 && kem == null) {
      throw const NegotiationAborted('PQ KEM unavailable during establishment');
    }
    final out = await Pqxdh.establishHybridV2(
      negotiation: negotiation,
      ourIdentityPrivateKey: identity.privateKey,
      ourIdentityPublicKey: identity.publicKey,
      ourEd25519PublicKey: ourEd,
      responderBundle: bundle,
      conversationId: conversation,
      userConsented: consented,
      pqKem: kem,
    );
    final transcript = out.transcript;
    final secret = out.secret;
    final eka = out.ephemeralPublicKey;
    final ct = out.mlKemCiphertext;
    try {
      final established = await TripleRatchet.startSession(
        peer: peer.copyWith(id: key),
        remoteDhPublicKey: bundle.signedPreKey.publicKey,
        sharedSecret: secret.secret,
        // The DR salt must agree on both sides: DH1 = DH(IKA, SPKB).
        ourPrivateKey: identity.privateKey,
        initiator: ownId.compareTo(peer.chhayaId.publicKey) < 0,
      );
      final pending = await _soft((db) => db.readResyncPending(conversation));
      final flight = <String, dynamic>{
        'offers': [for (final suite in myOffers) suite.id],
        'suite': selected.id,
        'ephemeralPublicKey': _bytesToHex(eka),
        'ciphertext': base64Encode(ct),
        'signedPreKeyId': bundle.signedPreKey.keyId,
        'pqSignedPreKeyId': bundle.pqSignedPreKey.keyId,
        if (bundle.oneTimePreKey != null)
          'oneTimePreKeyId': bundle.oneTimePreKey!.keyId,
        if (bundle.pqOneTimePreKey != null)
          'pqOneTimePreKeyId': bundle.pqOneTimePreKey!.keyId,
        'identityX25519': _bytesToHex(identity.publicKey),
        'identityEd25519': _bytesToHex(ourEd),
      };
      if (pending != null) {
        flight['restoreGeneration'] = pending.restoreGeneration;
        flight['reason'] = pending.reason;
      }
      final state = established.copyWith(
        sessionVersion: 2,
        transcript: transcript,
        nonPQ: selected == Suite.classicalConsentV1,
        consented: selected == Suite.classicalConsentV1 && consented,
        establishFlight: flight,
      );
      negotiation.markEstablished();
      return (state: state, flight: flight);
    } finally {
      Csprng.wipe(secret.secret);
    }
  }

  // ---- v2 acceptance (responder for one bootstrap flight) ----
  /// Builds the responder-side session from the flight, or throws. Never
  /// persists; caller persists through the normal decrypt commit (or the
  /// establishment is discarded in the crossed-restore tie-break).
  Future<SessionState> _acceptV2(
    Contact peer,
    String conversation,
    Map<String, dynamic> flight,
  ) async {
    final key = _key(conversation, peer);
    final pending = await _soft((db) => db.readResyncPending(conversation));
    final theirsRaw = flight['restoreGeneration'];
    final theirsGen = theirsRaw is String && _uuidRe.hasMatch(theirsRaw) ? theirsRaw : null;
    if (pending != null &&
        theirsGen != null &&
        pending.restoreGeneration.compareTo(theirsGen) > 0) {
      // Crossed simultaneous restore, higher local generation wins:
      // discard the incoming bootstrap without persisting it (spec §3.7).
      await _soft((db) =>
          db.writePlainKv(LocalDatabase.peerRestoredKey(conversation), '1'));
      throw const FormatException('crossed restore: local generation wins');
    }
    final offered = _parseOffers(flight['offers']);
    final presented = suiteFromString(_requireString(flight, 'suite'));
    final pqAvailable = await _pqAvailable();
    final consented = await PqHybridV1.userConsented();
    final ownOfferList = ownOffers(pqAvailable, consented);
    final negotiation = Negotiation.responder(
      offered: offered,
      ownOffers: ownOfferList,
      pqAvailable: pqAvailable,
      userConsented: consented,
      presented: presented,
    );
    final peerPub = peerPublicKeyBytes(peer.chhayaId.publicKey);
    final flightPeer = _hexToBytes(_requireString(flight, 'identityX25519'));
    if (!_bytesEq(flightPeer, peerPub)) {
      throw StateError('Bootstrap identity does not match the verified contact');
    }
    final material = PqHybridV1.testPrekeyProvider?.call(identity.publicKey);
    if (material == null) {
      // Production has no client-side prekey private-key store yet
      // (WS5+ follow-up): fail closed rather than guess.
      throw StateError('No responder prekey material available');
    }
    if (_requireString(flight, 'signedPreKeyId') != material.signedPreKeyId ||
        _requireString(flight, 'pqSignedPreKeyId') != material.pqSignedPreKeyId) {
      throw StateError('Bootstrap references unknown prekey ids');
    }
    final classical = presented == Suite.classicalConsentV1;
    final kem = await _kem();
    if (!classical && kem == null) {
      throw const NegotiationAborted('PQ KEM unavailable during acceptance');
    }
    if (classical && kem != null) {
      throw StateError('classical suite with PQ provider available');
    }
    final ourEd = await _ownEd25519();
    final accept = await Pqxdh.acceptHybridV2(
      negotiation: negotiation,
      ourIdentityPrivateKey: identity.privateKey,
      ourIdentityPublicKey: identity.publicKey,
      ourEd25519PublicKey: ourEd,
      peerIdentityX25519: flightPeer,
      peerEd25519PublicKey: _hexToBytes(_requireString(flight, 'identityEd25519')),
      ourSignedPreKeyPrivateKey: material.signedPreKeyPrivateKey,
      signedPreKeyId: material.signedPreKeyId,
      ourPqSignedPreKeyPrivateKey: material.pqSignedPreKeyPrivateKey,
      pqSignedPreKeyId: material.pqSignedPreKeyId,
      ourOneTimePreKeyPrivateKey: material.oneTimePreKeyPrivateKey,
      oneTimePreKeyId: flight['oneTimePreKeyId'] as String?,
      ourPqOneTimePreKeyPrivateKey: material.pqOneTimePreKeyPrivateKey,
      pqOneTimePreKeyId: flight['pqOneTimePreKeyId'] as String?,
      peerEphemeralPublicKey: _hexToBytes(_requireString(flight, 'ephemeralPublicKey')),
      mlKemCiphertext: base64Decode(_requireString(flight, 'ciphertext')),
      conversationId: conversation,
      userConsented: consented,
      pqKem: kem,
    );
    try {
      final established = await TripleRatchet.startSession(
        peer: peer.copyWith(id: key),
        // The responder's initial DR keypair is the SPK, so its DR salt
        // equals DH1 = DH(SPK, IKA) — identical to the initiator's salt.
        remoteDhPublicKey: _hexToBytes(_requireString(flight, 'identityX25519')),
        ourPrivateKey: material.signedPreKeyPrivateKey,
        sharedSecret: accept.secret.secret,
        // Roles assigned by lexicographic chhayaId comparison on BOTH
        // sides (spec §3.1.7) — never tied to who wrote the flight, so
        // both parties always agree on chain responsibilities.
        initiator: ownId.compareTo(peer.chhayaId.publicKey) < 0,
      );
      final state = established.copyWith(
        sessionVersion: 2,
        transcript: accept.transcript,
        nonPQ: classical,
        consented: classical && consented,
        establishFlight: Map<String, dynamic>.from(flight),
      );
      negotiation.markEstablished();
      if (theirsGen != null) {
        await _soft((db) => db.adoptRestoreGeneration(conversation, theirsGen));
        await _soft((db) => db
            .writePlainKv(LocalDatabase.peerRestoredKey(conversation), '1'));
      }
      return state;
    } finally {
      Csprng.wipe(accept.secret.secret);
    }
  }

  // ---- mid-session adoption (spec §3.7) ----
  /// Adopts the peer's fresh establishment when its `restore_generation`
  /// is strictly newer than the recorded one — that peer re-established
  /// because it restored, and its fresh PQXDH supersedes our stale
  /// session. Replayed or stale flights do not match and are ignored.
  /// [flight] must come from an AEAD-valid envelope's establishment; the
  /// body still has to verify before anything is committed.
  Future<SessionState?> _adoptFlightIfNewer(
    Contact peer,
    String conversation,
    Map<String, dynamic> flight,
  ) async {
    final theirsRaw = flight['restoreGeneration'];
    if (theirsRaw is! String || !_uuidRe.hasMatch(theirsRaw)) {
      return null; // fresh/migration flight: keep current session
    }
    final recorded = await _soft(
      (db) => db.readPlainKv(LocalDatabase.restoreGenerationKey(conversation)),
    );
    if (recorded != null && theirsRaw.compareTo(recorded) <= 0) {
      return null; // replayed or stale flight
    }
    return _acceptV2(peer, conversation, flight);
  }

  List<Suite> _parseOffers(Object? raw) {
    if (raw is! List || raw.isEmpty) {
      throw const NegotiationAborted('peer offer list is empty');
    }
    final out = <Suite>[];
    for (final item in raw) {
      if (item is! String) {
        throw const NegotiationAborted('malformed suite in peer offer list');
      }
      try {
        out.add(suiteFromString(item));
      } on ArgumentError {
        throw const NegotiationAborted('unknown suite in peer offer list');
      }
    }
    return out;
  }

  String _requireString(Map<String, dynamic> map, String field) {
    final value = map[field];
    if (value is! String || value.isEmpty) {
      throw FormatException('establishment flight missing $field');
    }
    return value;
  }

  // ---- shared send/prepare core ----
  // Returns the session to encrypt under, establishing one when absent
  // (flag on). Rollback forces a fresh re-establishment (spec §3.8).
  Future<SessionState> _prepareSession(
    Contact peer,
    String conversation,
  ) async {
    final key = _key(conversation, peer);
    final flagOn = await PqHybridV1.enabled();
    var state = await sessions.loadSession(key);
    if (state != null && state.sessionVersion == 1 && flagOn) {
      final pending = await _soft((db) => db.readResyncPending(conversation));
      if (pending == null && await _peerV2Known(conversation)) {
        // Lazy v2 migration, only after the peer proved v2 support
        // (criterion 10); the legacy blob is retained for receive-only.
        await _retainLegacySession(key);
        state = null;
      }
    }
    // flag-on legacy session without proof of peer v2 support stays v1.
    if (state != null && state.sessionVersion == 2) {
      // Rollback forces resync (spec §3.8): wipe, mark, re-establish.
      if (await _soft((db) => db.sessionGenerationState(conversation)) ==
          'rollback') {
        await _forceResyncIfRollback(conversation, key);
        state = null;
      }
    }
    if (state == null) {
      if (!flagOn) {
        throw StateError('No messaging session for this conversation');
      }
      final established = await _establishV2(peer, conversation);
      return established.state;
    }
    return state;
  }

  /// v2 envelopes carry the establishment flight until our first AEAD-valid
  /// inbound from this peer (spec §3.7: no user-visible send until ack).
  Future<Map<String, dynamic>?> _flightForEnvelope(
    Contact peer,
    String conversation,
    SessionState state,
  ) async {
    if (state.sessionVersion != 2) return null;
    if (state.establishFlight == null) return null;
    if (await _peerV2Known(conversation)) return null;
    return state.establishFlight;
  }

  String _envelope({
    required int version,
    Map<String, dynamic>? flight,
    List<String>? echo,
    required Uint8List header,
    required Uint8List body,
  }) =>
      jsonEncode({
        'v': version,
        if (flight != null) 'establish': flight,
        if (echo != null) 'echo': echo,
        'header': base64Encode(header),
        'body': base64Encode(body),
      });

  Future<String> encrypt(
    Contact peer,
    String conversation,
    String messageId,
    String sender,
    Map<String, dynamic> payload, {
    Future<void> Function(SessionState state, String envelope)? commit,
    List<String>? echo,
  }) async {
    if (!peer.isVerified) {
      throw StateError('Verify this contact using their QR code first');
    }
    final state = await _prepareSession(peer, conversation);
    final flight = await _flightForEnvelope(peer, conversation, state);
    final step = await TripleRatchet.encrypt(state);
    try {
      final header = step.header.toBytes();
      final aad = state.sessionVersion == 2
          ? _aadV2(conversation, messageId, sender, state.transcript!, header)
          : Uint8List.fromList([..._aad(conversation, messageId, sender), ...header]);
      final bytes = AesGcm.encryptBytes(
        step.keys.messageKey,
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        nonce: step.keys.nonce,
        aad: aad,
      );
      final envelope = _envelope(
        version: state.sessionVersion,
        flight: flight,
        echo: echo,
        header: header,
        body: bytes,
      );
      if (commit != null) {
        await commit(state, envelope);
      } else {
        await sessions.saveSession(state);
      }
      return envelope;
    } finally {
      step.keys.wipe();
      state.wipe();
    }
  }

  /// Produces a ratchet envelope without persisting the advanced state. Group
  /// sends use this to prepare every recipient wrapper before one DB commit.
  Future<({SessionState state, String envelope})> prepareEncrypt(
    Contact peer,
    String conversation,
    String messageId,
    String sender,
    Map<String, dynamic> payload,
  ) async {
    if (!peer.isVerified) {
      throw StateError('Verify this contact using their QR code first');
    }
    final state = await _prepareSession(peer, conversation);
    final flight = await _flightForEnvelope(peer, conversation, state);
    try {
      final step = await TripleRatchet.encrypt(state);
      try {
        final header = step.header.toBytes();
        final aad = state.sessionVersion == 2
            ? _aadV2(conversation, messageId, sender, state.transcript!, header)
            : Uint8List.fromList([..._aad(conversation, messageId, sender), ...header]);
        final bytes = AesGcm.encryptBytes(
          step.keys.messageKey,
          Uint8List.fromList(utf8.encode(jsonEncode(payload))),
          nonce: step.keys.nonce,
          aad: aad,
        );
        return (
          state: state,
          envelope: _envelope(
            version: state.sessionVersion,
            flight: flight,
            header: header,
            body: bytes,
          ),
        );
      } finally {
        step.keys.wipe();
      }
    } catch (_) {
      state.wipe();
      rethrow;
    }
  }

  // ---- decryption ----
  Future<Map<String, dynamic>> decrypt(
    Contact peer,
    String conversation,
    String messageId,
    String sender,
    String envelope, {
    Future<void> Function(SessionState state, Map<String, dynamic> payload)? commit,
  }) async {
    final wire = jsonDecode(envelope) as Map<String, dynamic>;
    final v = wire['v'];
    if (v != 1 && v != 2) {
      throw const FormatException('Unsupported message protocol');
    }
    if (v == 2 && !(await PqHybridV1.enabled())) {
      throw const FormatException('v2 envelope on a flag-off client');
    }
    final header = base64Decode(wire['header'] as String);
    final key = _key(conversation, peer);
    var state = await sessions.loadSession(key);
    var legacyRetained = false;
    if (v == 1) {
      if (state == null) {
        // Legacy receive-only window: fall back to the retained copy.
        state = await _loadLegacySession(key);
        legacyRetained = state != null;
        if (state == null) {
          throw StateError('No messaging session for this conversation');
        }
      } else if (state.sessionVersion == 2) {
        final legacy = await _loadLegacySession(key);
        if (legacy == null) {
          throw const FormatException('legacy message for a migrated conversation');
        }
        state = legacy;
        legacyRetained = true;
      }
    } else {
      final establishment = wire['establish'];
      var adopted = false;
      if (establishment is Map) {
        final newState = await _adoptFlightIfNewer(
          peer,
          conversation,
          Map<String, dynamic>.from(establishment),
        );
        if (newState != null) {
          state = newState;
          adopted = true;
        }
      }
      if (!adopted) {
        await _refuseStaleGeneration(conversation, key);
      }
      if (state == null || state.sessionVersion != 2) {
        final establishment = wire['establish'];
        if (establishment is! Map) {
          throw const FormatException('v2 envelope without an establishment flight');
        }
        state = await _acceptV2(peer, conversation, Map<String, dynamic>.from(establishment));
      }
    }
    final activeState = state; // promoted non-null by the branches above
    final keys = await TripleRatchet.decrypt(activeState, TripleHeader.fromBytes(header));
    try {
      final aad = v == 2
          ? _aadV2(conversation, messageId, sender, activeState.transcript!, header)
          : Uint8List.fromList([..._aad(conversation, messageId, sender), ...header]);
      final Uint8List plain;
      try {
        plain = AesGcm.decryptBytes(
          keys.messageKey,
          base64Decode(wire['body'] as String),
          aad: aad,
        );
      } catch (_) {
        // An unauthenticated packet is not proof the session is broken:
        // keep the session so later valid messages under it still flow.
        // (The strictest reading of spec §3.6 — wipe on any tag failure —
        // is recorded in the WS3 report as deviating from the pinned
        // codec tests; it needs a spec decision, not an ad-hoc choice.)
        ChhayaLog.w(
          'AEAD authentication failure; message rejected',
          name: 'RatchetMessageCodec',
        );
        rethrow;
      }
      final result = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      if (commit != null) {
        if (legacyRetained) {
          // Callers persist the state under `ratchet_session/${state.peerId}`;
          // hand them a twin keyed to the legacy slot so the primary v2
          // session is never overwritten with advanced legacy state. The JSON
          // round-trip deep-copies every key byte.
          final twin = SessionState.fromJson({
            ...jsonDecode(jsonEncode(activeState.toJson()))
                as Map<String, dynamic>,
            'peerId': legacyKey(key),
          });
          await commit(twin, result);
        } else {
          await commit(activeState, result);
        }
      } else if (legacyRetained) {
        await _soft(
          (db) => db.saveSessionBlob(legacyKey(key), jsonEncode(activeState.toJson())),
        );
      } else {
        await sessions.saveSession(activeState);
      }
      if (v == 2) {
        await _afterV2Decrypt(peer, conversation, wire, result);
      }
      return result;
    } finally {
      keys.wipe();
      state.wipe();
    }
  }

  Future<void> _afterV2Decrypt(
    Contact peer,
    String conversation,
    Map<String, dynamic> wire,
    Map<String, dynamic> payload,
  ) async {
    await _markPeerV2Known(conversation);
    // Echo verification (spec §3.5 rule 3): only over AEAD-valid input.
    if (wire['echo'] != null) {
      final ownOfferList = await _ownOffers();
      if (!verifyOfferEcho(ownOfferList, _parseOffers(wire['echo']))) {
        ChhayaLog.w(
          'offer echo mismatch; aborting session',
          name: 'RatchetMessageCodec',
        );
        try {
          await sessions.deleteSession(_key(conversation, peer));
        } catch (_) {
          // Best effort; keys are wiped in memory regardless.
        }
        throw const FormatException('offer echo mismatch');
      }
    }
    await _ackIfPending(conversation);
  }
}
