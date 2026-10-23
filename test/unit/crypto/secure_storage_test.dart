import 'dart:convert';
// Part 2 tests — secure storage adapters.
//
// Mock covers behavior; platform adapters are tested with an injected
// mock delegate plus a stubbed platform channel, so no hardware or
// native handlers are needed in CI.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/core/crypto/storage/secure_storage.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_android.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_ios.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_windows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('chhaya/security');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('SecureStorageMock', () {
    test('round-trips values', () async {
      final mock = SecureStorageMock();
      await mock.write(key: 'k', value: 'v');
      expect(await mock.read(key: 'k'), 'v');
      expect(await mock.containsKey(key: 'k'), isTrue);
      await mock.delete(key: 'k');
      expect(await mock.read(key: 'k'), isNull);
      expect(await mock.containsKey(key: 'k'), isFalse);
    });

    test('deleteAll clears everything', () async {
      final mock = SecureStorageMock({'a': '1', 'b': '2'});
      await mock.deleteAll();
      expect(await mock.read(key: 'a'), isNull);
      expect(await mock.read(key: 'b'), isNull);
    });

    test('reports unknown level (never claims hardware)', () async {
      expect(
        await SecureStorageMock().securityLevel(),
        HardwareSecurityLevel.unknown,
      );
    });
  });

  group('AndroidSecureStorage', () {
    test('reads/writes through delegate without platform calls', () async {
      final android =
          AndroidSecureStorage(delegate: SecureStorageMock());
      await android.write(key: 'k', value: 'v');
      expect(await android.read(key: 'k'), 'v');
    });

    test('falls back to TEE when the probe channel is missing', () async {
      final android =
          AndroidSecureStorage(delegate: SecureStorageMock());
      expect(
        await android.securityLevel(),
        HardwareSecurityLevel.tee,
      );
    });

    test('reports StrongBox when the probe confirms it', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => true);
      final android = AndroidSecureStorage(
        delegate: SecureStorageMock(),
        channel: channel,
      );
      expect(
        await android.securityLevel(),
        HardwareSecurityLevel.strongBox,
      );
    });

    test('reports TEE when the probe denies StrongBox', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => false);
      final android = AndroidSecureStorage(
        delegate: SecureStorageMock(),
        channel: channel,
      );
      expect(
        await android.securityLevel(),
        HardwareSecurityLevel.tee,
      );
    });
  });

  group('Native getStorageLevel wiring', () {
    void stubLevel(String? level, {bool booleanProbe = false}) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getStorageLevel') {
          return level;
        }
        return booleanProbe;
      });
    }

    test('android prefers native strongbox level', () async {
      stubLevel('strongbox');
      final android = AndroidSecureStorage(
        delegate: SecureStorageMock(),
        channel: channel,
      );
      expect(
        await android.securityLevel(),
        HardwareSecurityLevel.strongBox,
      );
    });

    test('android accepts native tee level', () async {
      stubLevel('tee');
      final android = AndroidSecureStorage(
        delegate: SecureStorageMock(),
        channel: channel,
      );
      expect(await android.securityLevel(), HardwareSecurityLevel.tee);
    });

    test('unknown native level falls back to boolean probe', () async {
      stubLevel('bogus-future-level', booleanProbe: true);
      final android = AndroidSecureStorage(
        delegate: SecureStorageMock(),
        channel: channel,
      );
      expect(
        await android.securityLevel(),
        HardwareSecurityLevel.strongBox,
      );
    });

    test('ios prefers native secure-enclave level', () async {
      stubLevel('secure-enclave');
      final ios = IOSSecureStorage(
        delegate: SecureStorageMock(),
        channel: channel,
      );
      expect(
        await ios.securityLevel(),
        HardwareSecurityLevel.secureEnclave,
      );
    });
  });

  group('Android wrapping envelopes', () {
    test('wraps actual stored values and refuses missing unwrap support', () async {
      final backing=SecureStorageMock();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async {
        if(call.method=='wrapSecret') { return 'ciphertext'; }
        if(call.method=='unwrapSecret') { return base64Encode(utf8.encode('private')); }
        return 'tee';
      });
      final storage=AndroidSecureStorage(delegate:backing,channel:channel);
      await storage.write(key:'secret',value:'private');
      expect(await backing.read(key:'secret'),'chhaya.keystore.v1:ciphertext');
      expect(await storage.read(key:'secret'),'private');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
      await expectLater(storage.read(key:'secret'),throwsA(isA<MissingPluginException>()));
    });
  });

  group('IOSSecureStorage', () {
    test('reads/writes through delegate without platform calls', () async {
      final ios = IOSSecureStorage(delegate: SecureStorageMock());
      await ios.write(key: 'k', value: 'v');
      expect(await ios.read(key: 'k'), 'v');
    });

    test('falls back to Keychain when the probe channel is missing',
        () async {
      final ios = IOSSecureStorage(delegate: SecureStorageMock());
      expect(await ios.securityLevel(), HardwareSecurityLevel.tee);
    });

    test('reports Secure Enclave when the probe confirms it', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => true);
      final ios = IOSSecureStorage(
        delegate: SecureStorageMock(),
        channel: channel,
      );
      expect(
        await ios.securityLevel(),
        HardwareSecurityLevel.secureEnclave,
      );
    });
  });

  group('iOS enclave envelopes', () {
    test('wraps before Keychain write and unwraps on read', () async {
      final backing = SecureStorageMock();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'wrapSecret') {
          expect((call.arguments as Map)['value'], base64Encode(utf8.encode('secret')));
          return 'encrypted-envelope';
        }
        if (call.method == 'unwrapSecret') {
          expect((call.arguments as Map)['value'], 'encrypted-envelope');
          return base64Encode(utf8.encode('secret'));
        }
        return null;
      });
      final storage = IOSSecureStorage(delegate: backing, channel: channel);
      await storage.write(key: 'key', value: 'secret');
      expect(await backing.read(key: 'key'), 'chhaya.enclave.v1:encrypted-envelope');
      expect(await storage.read(key: 'key'), 'secret');
      await storage.delete(key: 'key');
      expect(await storage.containsKey(key: 'key'), isFalse);
    });

    test('preserves old entries and falls back on hosts without wrapping', () async {
      final backing = SecureStorageMock({'old': 'legacy'});
      final storage = IOSSecureStorage(delegate: backing, channel: channel);
      expect(await storage.read(key: 'old'), 'legacy');
      await storage.write(key: 'new', value: 'value');
      expect(await storage.read(key: 'new'), 'value');
    });

    test('authentication errors do not overwrite existing secrets', () async {
      final backing = SecureStorageMock({'key': 'existing'});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'secure_storage');
      });
      final storage = IOSSecureStorage(delegate: backing, channel: channel);
      await expectLater(storage.write(key: 'key', value: 'replacement'),
          throwsA(isA<PlatformException>()));
      expect(await backing.read(key: 'key'), 'existing');
    });

    test('encrypted values never downgrade when the native host is missing', () async {
      final storage = IOSSecureStorage(
          delegate: SecureStorageMock({'key': 'chhaya.enclave.v1:ciphertext'}),
          channel: channel);
      await expectLater(storage.read(key: 'key'), throwsA(isA<MissingPluginException>()));
    });

    test('accepts native underscore and Keychain level names', () async {
      var level = 'secure_enclave';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => level);
      final storage = IOSSecureStorage(delegate: SecureStorageMock(), channel: channel);
      expect(await storage.securityLevel(), HardwareSecurityLevel.secureEnclave);
      level = 'keychain';
      expect(await storage.securityLevel(), HardwareSecurityLevel.tee);
    });
  });

  group('WindowsSecureStorage', () {
    test('reads/writes through delegate without platform calls', () async {
      final windows = WindowsSecureStorage(delegate: SecureStorageMock());
      await windows.write(key: 'k', value: 'v');
      expect(await windows.read(key: 'k'), 'v');
    });

    test('reports software DPAPI scope', () async {
      expect(
        await WindowsSecureStorage(delegate: SecureStorageMock())
            .securityLevel(),
        HardwareSecurityLevel.software,
      );
    });
  });

  group('SecureStorages', () {
    test('platformDefault never returns null and never throws', () {
      expect(SecureStorages.platformDefault(), isA<SecureStorage>());
    });
  });
}
