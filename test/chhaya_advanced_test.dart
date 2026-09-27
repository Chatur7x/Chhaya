import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/models/message.dart';
import 'package:chaaya/services/network/onion_router_service.dart';

void main() {
  group('Advanced Cryptography (Double Ratchet) Tests', () {
    test('Double Ratchet executes DH and Chain ratchet steps correctly', () async {
      final aliceKeyPair = await ChhayaCryptoEngine.generateKeyPair();
      final bobKeyPair = await ChhayaCryptoEngine.generateKeyPair();

      final sharedSecret = await ChhayaCryptoEngine.deriveSharedSecret(
        aliceKeyPair.privateKey,
        bobKeyPair.publicKey,
      );

      final aliceDhrsKeyPair = await ChhayaCryptoEngine.generateKeyPair();

      final aliceSession = DoubleRatchetSession(
        peerId: 'bob_id',
        rootKey: sharedSecret,
        dhrsKeyPair: aliceDhrsKeyPair,
      );

      final bobDhrsKeyPair = await ChhayaCryptoEngine.generateKeyPair();

      final bobSession = DoubleRatchetSession(
        peerId: 'alice_id',
        rootKey: sharedSecret,
        dhrsKeyPair: bobDhrsKeyPair,
        dhriPublicKey: aliceSession.dhrsKeyPair.publicKey,
      );

      final bobSharedSecret = await ChhayaCryptoEngine.deriveSharedSecret(
        bobSession.dhrsKeyPair.privateKey,
        aliceSession.dhrsKeyPair.publicKey,
      );
      bobSession.sendingChainKey = bobSharedSecret;

      aliceSession.receivingChainKey = bobSharedSecret;

      final bobRatchet = bobSession.ratchetSendChain();

      final aliceRatchet = aliceSession.ratchetReceiveChain();

      expect(bobRatchet.messageKey, equals(aliceRatchet.messageKey));

      expect(bobSession.sendingChainKey, isNot(equals(bobSharedSecret)));
    });

    test('Double Ratchet generates unique keys per message (forward secrecy)', () async {
      final sharedSecret = await ChhayaCryptoEngine.deriveSharedSecret(
        (await ChhayaCryptoEngine.generateKeyPair()).privateKey,
        (await ChhayaCryptoEngine.generateKeyPair()).publicKey,
      );

      final session = DoubleRatchetSession(
        peerId: 'peer1',
        rootKey: sharedSecret,
        dhrsKeyPair: await ChhayaCryptoEngine.generateKeyPair(),
        sendingChainKey: sharedSecret,
      );

      final key1 = session.ratchetSendChain().messageKey;
      final key2 = session.ratchetSendChain().messageKey;
      final key3 = session.ratchetSendChain().messageKey;

      expect(key1, isNot(equals(key2)));
      expect(key2, isNot(equals(key3)));
      expect(key1, isNot(equals(key3)));
    });
  });

  group('Onion Traffic Padding Tests', () {
    late OnionRouterService router;

    setUp(() {
      router = OnionRouterService();
    });

    test('wrapMessage outputs packets padded to exactly 512 bytes', () {
      final msgShort = Message(
        id: '1',
        conversationId: 'c1',
        senderId: 'alice',
        content: 'Hi',
        timestamp: DateTime.now(),
      );

      final msgLong = Message(
        id: '2',
        conversationId: 'c1',
        senderId: 'alice',
        content: 'This is a much longer message, but it should still produce the exact same size packet!',
        timestamp: DateTime.now(),
      );

      final path = router.getOptimalPath();

      final packetShort = router.wrapMessage(msgShort, path);
      final packetLong = router.wrapMessage(msgLong, path);

      expect(packetShort.payload.length, equals(512));
      expect(packetLong.payload.length, equals(512));
    });

    test('extractContent correctly recovers original message from padded payload', () {
      final originalContent = 'Hello from the onion network!';
      final msg = Message(
        id: '3',
        conversationId: 'c1',
        senderId: 'alice',
        content: originalContent,
        timestamp: DateTime.now(),
      );

      final packet = router.wrapMessage(msg, []);
      final extracted = OnionRouterService.extractContent(packet.payload);
      expect(extracted, equals(originalContent));
    });
  });
}