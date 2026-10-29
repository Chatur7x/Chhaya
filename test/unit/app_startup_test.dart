import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('notification setup failure does not block opening the app', () async {
    var attempted = false;

    await expectLater(
      initializeNotificationsBestEffort(() async {
        attempted = true;
        throw PlatformException(code: 'notifications_unavailable');
      }),
      completes,
    );

    expect(attempted, isTrue);
  });

  test('startup failure exposes a safe stage and error type', () {
    final failure = AppInitializationFailure(
      stage: 'encrypted local database',
      cause: StateError('private diagnostic text'),
    );

    expect(failure.stage, 'encrypted local database');
    expect(failure.causeType, 'StateError');
    expect(failure.toString(), isNot(contains('private diagnostic text')));
  });

  test('missing storage plugin guidance does not suggest deleting account data', () {
    final failure = AppInitializationFailure(
      stage: 'local storage',
      cause: MissingPluginException('No implementation found'),
    );
    expect(failure.safeSummary, contains('secure storage plugin'));
    expect(failure.safeSummary.toLowerCase(), isNot(contains('reinstall')));
    expect(failure.safeSummary, contains('left untouched'));
  });
}
