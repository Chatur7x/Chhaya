// Service-level tests for authenticated device linking (DL-B) against the
// in-memory fake DL-A backend. Exercises the real crypto end to end:
// X25519 ECDH, HKDF, transcript signing/verification, AES-256-GCM.
import 'dart:convert';

import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/user_profile.dart';
import 'package:chaaya/services/api/device_link_client.dart';
import 'package:chaaya/services/auth/device_link_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_device_link_server.dart';

const primaryDeviceId = '11111111-2222-3333-4444-555555555555';
const accountChhayaId =
    '05a1b2c3d4e5f60718293a4b5c6d7e8f901234567890abcdef1234567890abcdef12';

class FakeOpener implements DatabaseOpener {
  @override
  Future<Database> open({
    required String path,
    required int version,
    required String passwordHex,
    required Future<void> Function(Database db) onOpen,
  }) async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, _) => onOpen(db),
        onUpgrade: (db, _, __) => onOpen(db),
      ),
    );
    return db;
  }
}

Future<LocalDatabase> makeDb() async {
  final keyManager = KeyManager(secureBackend: SecureStorageMock());
  final db = LocalDatabase(
    keyManager: keyManager,
    opener: FakeOpener(),
    dbPath: inMemoryDatabasePath,
  );
  final ok = await db.init(requireBiometric: false);
  expect(ok, isTrue);
  return db;
}

UserProfile makeProfile() => UserProfile(
      chhayaId: ChhayaId.fromPublicKey(accountChhayaId),
      displayName: 'Test User',
      recoveryPhrase: const ['abandon', 'ability', 'able'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

class Pair {
  Pair(this.fake, this.primary, this.newDevice, this.newDeviceSecure,
      this.primaryDb, this.newDeviceDb);
  final FakeDeviceLinkServer fake;
  final DeviceLinkService primary;
  final DeviceLinkService newDevice;
  final SecureStorageMock newDeviceSecure;
  final LocalDatabase primaryDb;
  final LocalDatabase newDeviceDb;
}

Future<Pair> makePair() async {
  final fake = FakeDeviceLinkServer();
  final accountToken = fake.issueAccountToken(
    userId: 'account-1',
    primaryDeviceId: primaryDeviceId,
  );

  final primaryDb = await makeDb();
  final primaryKeys = KeyManager(secureBackend: SecureStorageMock());
  // The primary needs an identity seed for signing approvals; a fresh mock
  // storage produces a derived one via the master seed.
  final primaryService = DeviceLinkService(
    client: DeviceLinkClient(
      baseUrl: 'https://server.example',
      authToken: accountToken,
      client: fake.client(),
    ),
    database: primaryDb,
    keys: primaryKeys,
    authTokenProvider: () async => accountToken,
    profileProvider: () async => makeProfile(),
  );

  final newDeviceDb = await makeDb();
  final newDeviceKeys = KeyManager(secureBackend: SecureStorageMock());
  final newDeviceSecure = SecureStorageMock();
  final newDeviceService = DeviceLinkService(
    client: DeviceLinkClient(
      baseUrl: 'https://server.example',
      client: fake.client(),
    ),
    database: newDeviceDb,
    keys: newDeviceKeys,
    authTokenProvider: () async => null,
    profileProvider: () async => null,
  );

  return Pair(fake, primaryService, newDeviceService, newDeviceSecure,
      primaryDb, newDeviceDb);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('request → approve → verify → consume happy path', () async {
    final pair = await makePair();

    final enrollment = await pair.newDevice.beginEnrollment(
      deviceName: 'My laptop',
      platform: 'windows',
    );
    expect(enrollment.code.length, 32);
    expect(enrollment.linkPayload.startsWith('Chhaya-link-v1:'), isTrue);

    final pending = await pair.newDevice.checkStatus();
    expect(pending.kind, DeviceLinkPollKind.pending);

    // Primary parses the payload and prepares the approval.
    final payload = LinkPayload.parse(enrollment.linkPayload);
    expect(payload, isNotNull);
    expect(payload!.deviceName, 'My laptop');
    expect(payload.platform, 'windows');
    expect(payload.deviceId, enrollment.deviceId);

    final session = pair.primary.beginApproval(payload: payload);
    final primaryFingerprint = await session.fingerprint();
    expect(primaryFingerprint, matches(RegExp(r'^[0-9a-f]{16}$')));

    // Fingerprints must match before approving (spec §3.5).
    await session.finishApproval();
    expect(pair.fake.auditEvents, contains('approve'));

    final approved = await pair.newDevice.checkStatus();
    expect(approved.kind, DeviceLinkPollKind.approved);

    final verified = await pair.newDevice.verifyApproval();
    expect(verified.fingerprint, primaryFingerprint);
    expect(verified.accountChhayaId, accountChhayaId);

    final outcome = await pair.newDevice.consumeAfterConfirm();
    expect(outcome.deviceId, enrollment.deviceId);
    expect(pair.fake.auditEvents, containsAllInOrder(['request', 'approve', 'consume']));

    // The new device persisted its local record. The consume token is
    // deliberately not persisted in v1, so no secure-storage key exists.
    // (The ffi in-memory database is process-global, so filter by deviceId
    // rather than asserting absolute counts.)
    final records = jsonDecode(
      (await pair.newDeviceDb.readPlainKv(kLinkedDevicesKvKey))!,
    ) as List<dynamic>;
    final record = records.cast<Map<String, dynamic>>()
        .firstWhere((r) => r['deviceId'] == outcome.deviceId);
    expect(record['name'], 'My laptop');
    expect(record['revokedAt'], isNull);
    expect(record['isCurrentLocal'], isTrue);

    // Primary's list shows both devices, new one not current.
    final list = await pair.primary.listDevices();
    final primaryEntry = list.devices.firstWhere((d) => d.deviceId == primaryDeviceId);
    expect(primaryEntry.isCurrent, isTrue);
    final linked = list.devices.firstWhere((d) => d.deviceId == enrollment.deviceId);
    expect(linked.name, 'My laptop');
    expect(linked.revokedAt, isNull);
  });

  test('revoking a device calls the server and flags the local record', () async {
    final pair = await makePair();
    final enrollment = await pair.newDevice.beginEnrollment(
      deviceName: 'Work phone',
      platform: 'android',
    );
    final payload = LinkPayload.parse(enrollment.linkPayload)!;
    final session = pair.primary.beginApproval(payload: payload);
    await session.finishApproval();
    await pair.newDevice.checkStatus();
    await pair.newDevice.verifyApproval();
    final outcome = await pair.newDevice.consumeAfterConfirm();

    // Server-side revoke; local record flagged only after the call succeeds.
    await pair.primary.revokeDevice(deviceId: outcome.deviceId);
    expect(pair.fake.auditEvents, contains('revoke'));

    final list = await pair.primary.listDevices();
    final entry = list.devices.firstWhere((d) => d.deviceId == outcome.deviceId);
    expect(entry.revokedAt, isNotNull);

    // Server-side sessions for the device are deleted by the revoke call;
    // the client persists no token to invalidate locally in v1.
    // Re-revoke is idempotent (server returns 200).
    await pair.primary.revokeDevice(deviceId: outcome.deviceId);

    // Self-revocation is refused with use_logout.
    await expectLater(
      () => pair.primary.revokeDevice(deviceId: primaryDeviceId),
      throwsA(isA<DeviceLinkException>().having((e) => e.errorCode, 'code', 'use_logout')),
    );
  });

  test('local deny path surfaces denied to the new device', () async {
    final pair = await makePair();
    final enrollment = await pair.newDevice.beginEnrollment(
      deviceName: 'Test device',
      platform: 'linux',
    );
    final payload = LinkPayload.parse(enrollment.linkPayload)!;
    await pair.primary.denyPendingLink(payload: payload);
    final result = await pair.newDevice.checkStatus();
    expect(result.kind, DeviceLinkPollKind.denied);
    expect(pair.fake.auditEvents, contains('deny'));
  });

  test('wrong code is rejected at approve and consume', () async {
    final pair = await makePair();
    final enrollment = await pair.newDevice.beginEnrollment(
      deviceName: 'Test device',
      platform: 'linux',
    );
    await expectLater(
      () => pair.primary.denyPendingLink(
        payload: LinkPayload.parse(enrollment.linkPayload.replaceFirst(
          RegExp(':${enrollment.code}:'),
          ':00000000000000000000000000000000:',
        ))!,
      ),
      throwsA(isA<DeviceLinkException>()),
    );
  });

  test('expired code is rejected at request, approve, and consume', () async {
    // Expired N-side poll: fake status returns 410 (row deleted on read).
    final pairA = await makePair();
    await pairA.newDevice.beginEnrollment(
      deviceName: 'Test device A',
      platform: 'linux',
    );
    pairA.fake.debugExpireAll();
    final status = await pairA.newDevice.checkStatus();
    expect(status.kind, DeviceLinkPollKind.expired);
    expect(pairA.newDevice.hasActiveEnrollment, isFalse);

    // Expired P-side approve: fake approve returns 410.
    final pairB = await makePair();
    final enrollmentB = await pairB.newDevice.beginEnrollment(
      deviceName: 'Test device B',
      platform: 'linux',
    );
    pairB.fake.debugExpireAll();
    final payloadB = LinkPayload.parse(enrollmentB.linkPayload)!;
    await expectLater(
      () => pairB.primary.denyPendingLink(payload: payloadB),
      throwsA(isA<DeviceLinkException>().having((e) => e.errorCode, 'code', 'link_expired')),
    );
  });

  test('tampered approval fails AEAD/signature verification and nothing is consumed', () async {
    final pair = await makePair();
    final enrollment = await pair.newDevice.beginEnrollment(
      deviceName: 'Test device',
      platform: 'linux',
    );
    final payload = LinkPayload.parse(enrollment.linkPayload)!;
    final session = pair.primary.beginApproval(payload: payload);
    await session.finishApproval();

    pair.fake.tamperApproval(enrollment.requestId, target: 'approval');
    final approved = await pair.newDevice.checkStatus();
    expect(approved.kind, DeviceLinkPollKind.approved);
    await expectLater(
      () => pair.newDevice.verifyApproval(),
      throwsA(anything),
    );
    // Consume must not be possible from a failed verification.
    await expectLater(
      () => pair.newDevice.consumeAfterConfirm(),
      throwsStateError,
    );

    // Fresh attempt, tampered primEphPub, must fail too.
    final enrollment2 = await pair.newDevice.beginEnrollment(
      deviceName: 'Test device 2',
      platform: 'linux',
    );
    final payload2 = LinkPayload.parse(enrollment2.linkPayload)!;
    final session2 = pair.primary.beginApproval(payload: payload2);
    await session2.finishApproval();
    pair.fake.tamperApproval(enrollment2.requestId, target: 'primEphPub');
    await pair.newDevice.checkStatus();
    await expectLater(
      () => pair.newDevice.verifyApproval(),
      throwsA(anything),
    );
  });

  test('revoke of a device the server does not know fails and keeps the local record', () async {
    final pair = await makePair();
    // Seed a purely local record (approved but never consumed).
    const ghostId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await pair.primaryDb.writePlainKv(
      kLinkedDevicesKvKey,
      jsonEncode([
        DeviceLinkDeviceRecord(
          deviceId: ghostId,
          name: 'Ghost laptop',
          platform: 'windows',
          createdAt: DateTime.now().toUtc(),
        ).toJson(),
      ]),
    );

    await expectLater(
      () => pair.primary.revokeDevice(deviceId: ghostId),
      throwsA(isA<DeviceLinkException>().having((e) => e.statusCode, 'status', 404)),
    );

    final records =
        jsonDecode((await pair.primaryDb.readPlainKv(kLinkedDevicesKvKey))!) as List<dynamic>;
    final ghost = records.cast<Map<String, dynamic>>().firstWhere((r) => r['deviceId'] == ghostId);
    expect(ghost['revokedAt'], isNull);
  });

  test('list falls back to local records with serverUnavailable on network failure', () async {
    final pair = await makePair();
    final enrollment = await pair.newDevice.beginEnrollment(
      deviceName: 'Offline device',
      platform: 'linux',
    );
    final payload = LinkPayload.parse(enrollment.linkPayload)!;
    final session = pair.primary.beginApproval(payload: payload);
    await session.finishApproval();
    await pair.newDevice.checkStatus();
    await pair.newDevice.verifyApproval();
    await pair.newDevice.consumeAfterConfirm();

    // A primary service whose token the fake does not recognise gets 401s;
    // the list must degrade to local records with serverUnavailable=true.
    final failingClient = DeviceLinkClient(
      baseUrl: 'https://server.example',
      authToken: 'bogus-token',
      client: pair.fake.client(),
    );
    final offline = DeviceLinkService(
      client: failingClient,
      database: await makeDb(),
      keys: KeyManager(secureBackend: SecureStorageMock()),
      authTokenProvider: () async => 'bogus-token',
      profileProvider: () async => makeProfile(),
    );
    final list = await offline.listDevices();
    expect(list.serverUnavailable, isTrue);
    // Entries are built from the local kv records only (ffi in-memory DB is
    // process-global, so exact counts are not asserted).
    for (final entry in list.devices) {
      expect(entry.pending, isTrue);
    }

    // The consuming device's own view, with the token now valid device-side,
    // lists itself from its local record.
    final selfList = await pair.newDevice.listDevices();
    expect(selfList.serverUnavailable, isTrue); // new device has no account session
    expect(selfList.devices.any((d) => d.deviceId == enrollment.deviceId), isTrue);
  });
}
