import 'dart:async';
import 'package:flutter/services.dart';

/// Best-effort expiry for sensitive copies made by this process.
/// Clipboard history and copies taken by other apps cannot be erased here.
class SensitiveClipboard {
  static Timer? _timer;
  static int _generation = 0;

  static Future<void> copy(
    String text, {
    Duration lifetime = const Duration(seconds: 30),
  }) async {
    final generation = ++_generation;
    _timer?.cancel();
    await Clipboard.setData(ClipboardData(text: text));
    if (generation != _generation) return;
    _timer = Timer(lifetime, () async {
      try {
        final current = await Clipboard.getData(Clipboard.kTextPlain);
        if (generation == _generation && current?.text == text) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      } catch (_) {
        // Platforms can deny clipboard access while the app is backgrounded.
      }
    });
  }
}
