// Widget smoke test for the new-device enroll screen. Builds the screen
// against a service backed by an unreachable client and asserts the honesty
// copy and critical labels exist.
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/services/api/device_link_client.dart';
import 'package:chaaya/services/auth/device_link_service.dart';
import 'package:chaaya/ui/screens/settings/device_link_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceLinkService smokeService() => DeviceLinkService(
      client: DeviceLinkClient(baseUrl: 'https://unconfigured.invalid'),
      database: LocalDatabase(),
      keys: KeyManager(secureBackend: SecureStorageMock()),
      authTokenProvider: () async => null,
      profileProvider: () async => null,
      secureStorage: SecureStorageMock(),
    );

void main() {
  testWidgets('enroll screen builds with honesty copy and critical labels', (tester) async {
    final container = ProviderContainer(
      overrides: [
        deviceLinkServiceProvider.overrideWithValue(smokeService()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DeviceLinkScreen()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Link a device'), findsOneWidget);
    expect(find.text('Link this device'), findsWidgets);
    expect(
      find.text('Linked devices see your contacts and profile. They cannot read or send messages.'),
      findsOneWidget,
    );
    expect(find.textContaining('Messages stay on the device where they were written'), findsOneWidget);
    expect(find.bySemanticsLabel('Link code'), findsNothing); // only shown while linking
  });
}
