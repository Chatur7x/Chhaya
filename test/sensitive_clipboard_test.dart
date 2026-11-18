import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/core/privacy/sensitive_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var clipboard = '';
  setUp(() {
    clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  testWidgets('expires sensitive copy after thirty seconds', (tester) async {
    await SensitiveClipboard.copy('secret');
    await tester.pump(const Duration(seconds: 29));
    expect(clipboard, 'secret');
    await tester.pump(const Duration(seconds: 1));
    expect(clipboard, '');
  });
  testWidgets('preserves clipboard replaced by another application', (
    tester,
  ) async {
    await SensitiveClipboard.copy('secret');
    clipboard = 'another app';
    await tester.pump(const Duration(seconds: 30));
    expect(clipboard, 'another app');
  });
  testWidgets('new copy receives a fresh expiry', (tester) async {
    await SensitiveClipboard.copy('first');
    await tester.pump(const Duration(seconds: 20));
    await SensitiveClipboard.copy('second');
    await tester.pump(const Duration(seconds: 10));
    expect(clipboard, 'second');
    await tester.pump(const Duration(seconds: 20));
    expect(clipboard, '');
  });
}
