// Version negotiation and suite registry for Chhaya vNext hybrid
// establishment (spec §3.0, §3.5, §3.6).
//
// Explicit offer lists with full echo; highest-common selection; AEAD
// failure is a hard abort; classical fallback only with explicit consent.
// WS2 implements the state machine only — nothing here is wired into
// production messaging; WS3/WS5 gate it behind chhaya_pq_hybrid_v1.
import 'dart:typed_data';

import '../../log.dart';
import 'transcript.dart';

/// Client protocol version range (spec §3.0; only v2 is speakable).
const int clientMinProtocolVersion = protocolVersionV2;
const int clientMaxProtocolVersion = protocolVersionV2;

/// Hard abort of a negotiation/establishment. Terminal; there is no
/// resume, no retry-with-weaker, no silent fallback (spec §3.6).
class NegotiationAborted implements Exception {
  final String reason;
  const NegotiationAborted(this.reason);
  @override
  String toString() => 'NegotiationAborted: $reason';
}

/// No common suite between the two offer lists (spec §3.5 rule 2).
class NoCommonSuiteException extends NegotiationAborted {
  const NoCommonSuiteException() : super('no common suite');
}

/// A retry attempted to weaken parameters (spec §2.4, §3.5 rule 4, §3.6).
class DowngradeRetryForbidden extends NegotiationAborted {
  const DowngradeRetryForbidden()
      : super('retry with weaker parameters is forbidden');
}

/// Registry entry for a registered suite. Adding a suite is a spec change.
class Suite {
  final String id; // API string form (spec §3.0)
  final int byte; // transcript byte (spec §3.3)
  final int priority; // higher wins in highest-common selection

  const Suite._(this.id, this.byte, this.priority);

  static const chhayaPqxdhV1 = Suite._(
    'chhaya-pqxdh-v1',
    suiteBytePqxdhV1,
    100,
  );
  static const classicalConsentV1 = Suite._(
    'chhaya-classical-consent-v1',
    suiteByteClassicalConsentV1,
    10,
  );

  /// Fixed registry order (spec §3.5 rule 2). Priority decreases here.
  static const List<Suite> registry = [chhayaPqxdhV1, classicalConsentV1];

  @override
  bool operator ==(Object other) =>
      other is Suite && other.id == id && other.byte == byte;
  @override
  int get hashCode => Object.hash(id, byte);
  @override
  String toString() => id;
}

/// Parses a suite by API string. Unknown/malformed input fails closed.
Suite suiteFromString(String s) {
  if (s.isEmpty) {
    throw ArgumentError.value(s, 'suite', 'Suite string must not be empty');
  }
  for (final suite in Suite.registry) {
    if (suite.id == s) return suite;
  }
  throw ArgumentError.value(s, 'suite', 'Unknown or unsupported suite string');
}

/// Parses a suite by transcript byte. Unknown bytes fail closed.
Suite suiteFromByte(int b) {
  if (b < 0 || b > 0xFF) {
    throw ArgumentError.value(b, 'byte', 'Suite byte must fit in one octet');
  }
  for (final suite in Suite.registry) {
    if (suite.byte == b) return suite;
  }
  throw ArgumentError.value(b, 'byte', 'Unknown or unsupported suite byte');
}

/// Highest-common selection from two offer lists (spec §3.5 rule 2).
/// Pure function; both sides compute the same result iff neither list was
/// tampered with. No common suite ⇒ [NoCommonSuiteException].
Suite highestCommonSuite(List<Suite> initiatorOffers, List<Suite> peerOffers) {
  final initiator = initiatorOffers.toSet();
  final common = peerOffers.toSet().where(initiator.contains);
  Suite? best;
  for (final suite in common) {
    if (best == null || suite.priority > best.priority) best = suite;
  }
  if (best == null) throw const NoCommonSuiteException();
  return best;
}

/// Full offer echo verification (spec §3.5 rule 3): the echo must be
/// byte-for-byte the offer list we sent.
bool verifyOfferEcho(List<Suite> sent, List<Suite> echoed) {
  if (sent.length != echoed.length) return false;
  for (var i = 0; i < sent.length; i++) {
    if (sent[i] != echoed[i]) return false;
  }
  return true;
}

/// Negotiation/establishment stages (spec §3.5 diagram).
enum NegotiationStage {
  idle,
  offerSent,
  bundleSent,
  suiteSelected,
  established,
  aborted,
}

/// Single-use negotiation state machine. Illegal transitions fail closed.
///
/// Enforces: no common suite ⇒ abort; echo mismatch ⇒ abort; classical
/// suite only with PQ unavailable AND explicit consent; AEAD failure ⇒
/// hard abort with SK wiped; terminal state has no path back to a weaker
/// attempt.
class Negotiation {
  Negotiation({required this.ownOffers, required this.pqAvailable}) {
    if (clientMinProtocolVersion < 0 ||
        clientMaxProtocolVersion > 0xFF ||
        clientMinProtocolVersion > clientMaxProtocolVersion) {
      throw StateError('client protocol version range is invalid');
    }
  }

  /// The offer list this endpoint sends (registry-validated suites).
  final List<Suite> ownOffers;

  /// Capability probe result: true when a PQ KEM provider is available on
  /// this build/platform. Windows is always false (spec §7.1).
  final bool pqAvailable;

  NegotiationStage _stage = NegotiationStage.idle;
  Suite? _selected;
  int _maxAttemptedPriority = 0;

  NegotiationStage get stage => _stage;
  Suite? get selected => _selected;

  /// First flight: validate our offer list and move to offerSent.
  void sendOffer() {
    if (_stage != NegotiationStage.idle) {
      throw StateError('offer already sent (stage: $_stage)');
    }
    if (ownOffers.isEmpty) {
      abort('own offer list is empty');
    }
    _stage = NegotiationStage.offerSent;
  }

  /// Peer's offer echo arrived with the bundle flight (spec §3.5 rule 3).
  /// Mismatch ⇒ abort. Highest-common selection happens here; classical
  /// requires [userConsented] and PQ being unavailable.
  Suite receiveBundleEcho({
    required List<Suite> echoedOffers,
    required List<Suite> peerOffers,
    required bool userConsented,
  }) {
    if (_stage != NegotiationStage.offerSent) {
      throw StateError('echo received out of order (stage: $_stage)');
    }
    if (!verifyOfferEcho(ownOffers, echoedOffers)) {
      abort('offer echo mismatch');
    }
    _stage = NegotiationStage.bundleSent;
    final Suite selected;
    try {
      selected = highestCommonSuite(ownOffers, peerOffers);
    } on NoCommonSuiteException {
      abort('no common suite');
    }
    if (selected == Suite.classicalConsentV1) {
      if (pqAvailable) {
        // PQ is available on this build — classical may never be selected,
        // even with consent (spec §3.5 rule 5: both (a) AND (b) required).
        abort('classical suite proposed but PQ provider is available');
      }
      if (!userConsented) {
        // No silent fallback (spec §3.5 rule 5, §3.6 consent declined).
        abort('classical fallback requires explicit user consent');
      }
      ChhayaLog.w(
        'Classical-only session selected with explicit user consent; '
        'session must be flagged nonPQ',
        name: 'Negotiation',
      );
    }
    _selected = selected;
    if (selected.priority > _maxAttemptedPriority) {
      _maxAttemptedPriority = selected.priority;
    }
    _stage = NegotiationStage.suiteSelected;
    return selected;
  }

  /// Establishment succeeded (AEAD verified under the derived keys).
  void markEstablished() {
    if (_stage != NegotiationStage.suiteSelected) {
      throw StateError('cannot mark established (stage: $_stage)');
    }
    _stage = NegotiationStage.established;
  }

  /// Responder half of suite selection (spec §3.5). The initiator's offer
  /// list arrived in the establishment flight; both sides compute the same
  /// highest-common suite from the two lists, so the presented suite is
  /// verified against the locally computed one. Ends at [stage]
  /// suiteSelected, ready for `Pqxdh.acceptHybridV2`.
  ///
  /// Throws [NoCommonSuiteException] (a [NegotiationAborted]) when the
  /// lists do not overlap; aborts on any presented-suite mismatch or
  /// classical/PQ rule violation (spec §3.5 rule 5).
  factory Negotiation.responder({
    required List<Suite> offered,
    required List<Suite> ownOffers,
    required bool pqAvailable,
    required bool userConsented,
    required Suite presented,
  }) {
    final n = Negotiation(ownOffers: ownOffers, pqAvailable: pqAvailable);
    if (offered.isEmpty) {
      n.abort('peer offer list is empty');
    }
    // No common suite propagates as NoCommonSuiteException (terminal).
    final selected = highestCommonSuite(offered, ownOffers);
    if (selected != presented) {
      n.abort('presented suite is not the highest-common selection');
    }
    if (selected == Suite.classicalConsentV1) {
      if (pqAvailable) {
        n.abort('classical suite selected with PQ provider present');
      }
      if (!userConsented) {
        n.abort('classical fallback requires explicit user consent');
      }
      ChhayaLog.w(
        'Classical-only session selected with explicit user consent; '
        'session must be flagged nonPQ',
        name: 'Negotiation',
      );
    }
    n._selected = selected;
    n._stage = NegotiationStage.suiteSelected;
    return n;
  }

  /// AEAD failure under the selected suite: hard abort (spec §3.6).
  /// Any SK material held by the caller is wiped here.
  void recordAeadFailure({Uint8List? sk}) {
    if (sk != null) {
      sk.fillRange(0, sk.length, 0);
    }
    abort('AEAD authentication failure');
  }

  /// Forbidden retry-with-weaker (spec §2.4, §3.6): any new establishment
  /// attempt in this session must not select a lower-priority suite than
  /// the strongest one already attempted.
  void assertNoDowngradeRetry(Suite attempted) {
    if (attempted.priority < _maxAttemptedPriority) {
      throw const DowngradeRetryForbidden();
    }
  }

  /// Terminal abort. Never returns; there is no path out of aborted.
  Never abort(String reason) {
    _stage = NegotiationStage.aborted;
    ChhayaLog.w('establishment aborted: $reason', name: 'Negotiation');
    throw NegotiationAborted(reason);
  }
}
