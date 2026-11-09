import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/ratchet/session_store.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/message.dart';
import 'package:chaaya/services/messaging/message_payload.dart';
import 'package:chaaya/services/messaging/poll_payload.dart';
import 'package:chaaya/services/messaging/pq_hybrid_v1.dart';
import 'package:chaaya/services/messaging/ratchet_message_codec.dart';

import '../../support/fake_prekey_server.dart';

void main() {
  test('poll definitions and votes validate all choices and limits', () {
    final poll = PollPayload.create(
      question: 'Where should we meet?',
      labels: ['Cafe', 'Park'],
      allowMultiple: false,
    );
    final decoded = PollPayload.decodeDefinition(
      jsonDecode(poll.encode()) as Map<String, dynamic>,
    );
    expect(decoded.options.map((option) => option.label), ['Cafe', 'Park']);
    final vote = PollVote(pollId: poll.id, optionIds: [poll.options.first.id]);
    expect(
      PollPayload.decodeVote(
        jsonDecode(vote.encode()) as Map<String, dynamic>,
        definition: poll,
      ).optionIds,
      [poll.options.first.id],
    );
    expect(
      () => PollPayload.decodeVote({
        'kind': 'vote',
        'pollId': poll.id,
        'optionIds': [poll.options.first.id, poll.options.last.id],
      }, definition: poll),
      throwsFormatException,
    );
    expect(
      () => PollPayload.decodeVote({
        'kind': 'vote',
        'pollId': poll.id,
        'optionIds': ['bad'],
      }, definition: poll),
      throwsFormatException,
    );
    expect(
      () => PollPayload.create(
        question: 'Q',
        labels: ['Only one'],
        allowMultiple: false,
      ),
      throwsFormatException,
    );
  });

  test('poll close times reject later votes but preserve earlier history', () {
    final closesAt = DateTime.now().subtract(const Duration(minutes: 1));
    final poll = PollPayload.create(
      question: 'Vote',
      labels: ['Yes', 'No'],
      allowMultiple: false,
      endsAt: closesAt,
    );
    final vote = {
      'kind': 'vote',
      'pollId': poll.id,
      'optionIds': [poll.options.first.id],
    };
    expect(
      () => PollPayload.decodeVote(vote, definition: poll),
      throwsFormatException,
    );
    expect(
      PollPayload.decodeVote(
        vote,
        definition: poll,
        votedAt: closesAt.subtract(const Duration(minutes: 1)),
      ).pollId,
      poll.id,
    );
  });

  test(
    'poll and vote content stay inside an authenticated ratchet envelope',
    () async {
      final fakePrekeys = FakePrekeyServer()..wireInto();
      addTearDown(PqHybridV1.resetForTest);
      final a = await ChhayaCryptoEngine.generateKeyPair(),
          b = await ChhayaCryptoEngine.generateKeyPair();
      final aid = '05${a.publicKeyHex}', bid = '05${b.publicKeyHex}';
      final accountA = await fakePrekeys.enroll('alice', Uint8List.fromList(a.publicKey));
      final accountB = await fakePrekeys.enroll('bob', Uint8List.fromList(b.publicKey));
      final alice = RatchetMessageCodec(
        sessions: InMemorySessionStorage(),
        identity: a,
        ownId: aid,
        ed25519PublicKey: () async => accountA.identityEd25519Public,
      );
      final bob = RatchetMessageCodec(
        sessions: InMemorySessionStorage(),
        identity: b,
        ownId: bid,
        ed25519PublicKey: () async => accountB.identityEd25519Public,
      );
      final ap = Contact(
        id: 'alice',
        chhayaId: ChhayaId.fromPublicKey(aid),
        displayName: 'Alice',
        isVerified: true,
      );
      final bp = Contact(
        id: 'bob',
        chhayaId: ChhayaId.fromPublicKey(bid),
        displayName: 'Bob',
        isVerified: true,
      );
      final poll = PollPayload.create(
        question: 'Private question',
        labels: ['Private option', 'Other'],
        allowMultiple: true,
      );
      final source = Message(
        id: 'poll',
        conversationId: '423e4567-e89b-42d3-a456-426655440003',
        senderId: 'alice',
        content: poll.encode(),
        type: MessageType.poll,
        timestamp: DateTime.now(),
      );
      final wire = await alice.encrypt(
        bp,
        '423e4567-e89b-42d3-a456-426655440003',
        source.id,
        'alice',
        MessagePayload.encode(source),
      );
      expect(wire, isNot(contains('Private question')));
      final clear = await bob.decrypt(ap, '423e4567-e89b-42d3-a456-426655440003', source.id, 'alice', wire);
      expect(MessagePayload.decode(source, clear).content, poll.encode());
      final vote = Message(
        id: 'vote',
        conversationId: '423e4567-e89b-42d3-a456-426655440003',
        senderId: 'alice',
        content:
            PollVote(
              pollId: poll.id,
              optionIds: [poll.options.first.id],
            ).encode(),
        type: MessageType.poll,
        timestamp: DateTime.now(),
      );
      expect(
        MessagePayload.decode(vote, MessagePayload.encode(vote)).type,
        MessageType.poll,
      );
    },
  );
}
