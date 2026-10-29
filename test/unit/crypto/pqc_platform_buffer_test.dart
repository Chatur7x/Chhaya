import 'package:chhaya_pqc/chhaya_pqc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.chhaya/pqc');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    ChhayaPqc.resetForTesting();
  });

  test(
    'platform byte results support key splitting, wiping and caller mutation',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'capabilities') {
              return {'available': true, 'provider': 'buffer-test-only'};
            }
            final operation = (call.arguments as Map)['operation'];
            final length = switch (operation) {
              1 => 1568 + 3168,
              2 => 1600,
              3 => 32,
              4 => 2592 + 4896,
              5 => 4627,
              6 => 1,
              _ => throw StateError('Unexpected operation'),
            };
            return Uint8List.fromList(
              List.filled(length, 1),
            ).asUnmodifiableView();
          });
      final kem = await ChhayaPqc.generateKemKeyPair();
      final dsa = await ChhayaPqc.generateDsaKeyPair();
      try {
        final encapsulated = await ChhayaPqc.encapsulate(kem.publicKey);
        final shared = await ChhayaPqc.decapsulate(
          kem.privateKey,
          encapsulated.ciphertext,
        );
        shared[0] = 2;
        expect(shared.first, 2);
        final message = Uint8List.fromList([1, 2, 3]);
        final signature = await ChhayaPqc.sign(dsa.privateKey, message);
        signature[0] = 2;
        expect(
          await ChhayaPqc.verify(dsa.publicKey, message, signature),
          isTrue,
        );
      } finally {
        kem.destroy();
        dsa.destroy();
      }
      expect(kem.privateKey, everyElement(0));
      expect(dsa.privateKey, everyElement(0));
    },
  );
}
