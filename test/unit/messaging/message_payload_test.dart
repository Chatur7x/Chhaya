import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/ratchet/session_store.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/message.dart';
import 'package:chaaya/core/models/message_attachment.dart';
import 'package:chaaya/services/messaging/attachment_service.dart';
import 'package:chaaya/services/messaging/message_payload.dart';
import 'package:chaaya/services/messaging/ratchet_message_codec.dart';

void main() {
  Message message() => Message(id: 'attachment', conversationId: 'chat', senderId: 'alice',
    content: 'A private caption', type: MessageType.file, replyToId: 'original',
    timestamp: DateTime.now(), attachment: MessageAttachment.fromBytes(
      name: 'private-document.txt', mimeType: 'text/plain', bytes: Uint8List.fromList(utf8.encode('private file contents'))));

  test('two peers decrypt attachment bytes and reply metadata without exposing them to transport', () async {
    final a = await ChhayaCryptoEngine.generateKeyPair(), b = await ChhayaCryptoEngine.generateKeyPair();
    final aid = '05${a.publicKeyHex}', bid = '05${b.publicKeyHex}';
    final alice = RatchetMessageCodec(sessions: InMemorySessionStorage(), identity: a, ownId: aid);
    final bob = RatchetMessageCodec(sessions: InMemorySessionStorage(), identity: b, ownId: bid);
    final ap = Contact(id: 'alice', chhayaId: ChhayaId.fromPublicKey(aid), displayName: 'Alice', isVerified: true);
    final bp = Contact(id: 'bob', chhayaId: ChhayaId.fromPublicKey(bid), displayName: 'Bob', isVerified: true);
    final source = message();
    final wire = await alice.encrypt(bp, 'chat', source.id, 'alice', MessagePayload.encode(source));
    for (final secret in ['private-document', 'private file contents', 'original', 'private caption']) {
      expect(wire, isNot(contains(secret)));
    }
    final decoded = MessagePayload.decode(source, await bob.decrypt(ap, 'chat', source.id, 'alice', wire));
    expect(decoded.attachment!.bytes, source.attachment!.bytes);
    expect(decoded.replyToId, 'original');
    final stored = Message.fromJson(jsonDecode(jsonEncode(decoded.toJson())) as Map<String, dynamic>);
    expect(stored.attachment!.name, 'private-document.txt');
    expect(stored.attachment!.bytes, source.attachment!.bytes);
  });

  test('legacy text envelopes remain readable; malformed types and expiry are rejected', () {
    final source = message();
    expect(MessagePayload.decode(source, {'content': 'legacy text'}).type, MessageType.text);
    for (final payload in [
      {'content': '', 'type': 'text'},
      {'content': 'x', 'type': 'file'},
      {'content': 'x', 'type': 'text', 'ttlMs': -1},
      {'content': 'x', 'type': 'text', 'ttlMs': 604800001},
      {'content': 'x', 'type': 'unknown'},
      {'content': 'x', 'replyToId': 42},
    ]) {
      expect(() => MessagePayload.decode(source, payload), throwsFormatException);
    }
  });

  test('attachment bounds are enforced before buffering and after decoding', () async {
    final bytes = Uint8List(MessageAttachment.maxBytes);
    expect((await AttachmentService.readBounded(Stream.value(bytes))).length, bytes.length);
    await expectLater(AttachmentService.readBounded(Stream.fromIterable([bytes, [1]])), throwsStateError);
    await expectLater(AttachmentService.readBounded(const Stream.empty()), throwsStateError);
    expect(() => MessageAttachment.fromBytes(name: 'x', mimeType: 'text/plain', bytes: Uint8List(bytes.length + 1)), throwsArgumentError);
    expect(() => MessageAttachment.fromJson({'name': 'x', 'mimeType': 'text/plain', 'data': '!' }), throwsFormatException);
  });

  test('untrusted filenames cannot select an export path', () {
    final attachment = MessageAttachment.fromBytes(name: '../../secret\\report.txt',
      mimeType: 'text/plain', bytes: Uint8List.fromList([1]));
    expect(attachment.name, 'report.txt');
    expect(() => MessageAttachment.fromBytes(name: '..', mimeType: 'text/plain', bytes: Uint8List.fromList([1])), throwsFormatException);
  });
}
