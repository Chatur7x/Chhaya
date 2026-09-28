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
