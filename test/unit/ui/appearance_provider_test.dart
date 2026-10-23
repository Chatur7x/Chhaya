import 'package:chaaya/ui/theme/appearance_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fresh installs use Claude Light while saved theme choices are kept',
    () async {
      SharedPreferences.setMockInitialValues({});
      final freshInstall = AppearanceController();
      expect(freshInstall.state, ThemeMode.light);
      await Future<void>.delayed(Duration.zero);
      expect(freshInstall.state, ThemeMode.light);
      freshInstall.dispose();

      SharedPreferences.setMockInitialValues({'chhaya_appearance': 'system'});
      final existingPreference = AppearanceController();
      await Future<void>.delayed(Duration.zero);
      expect(existingPreference.state, ThemeMode.system);
      existingPreference.dispose();
    },
  );
}
