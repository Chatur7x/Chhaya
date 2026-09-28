// Chhaya app logger — structured logging without print() calls.
//
// Purpose: single logging entry point for the Flutter app. All production
// code must use [ChhayaLog] instead of `print()` so output is tagged,
// filterable, and never leaks sensitive material. Never log keys, tokens,
// message content, or PII through this logger.
import 'dart:developer' as developer;

/// Log severity levels used across the app.
enum LogLevel {
  /// Verbose diagnostics, disabled in release builds.
  debug,

  /// Normal operational events.
  info,

  /// Recoverable problems (offline fallback, retry).
  warning,

  /// Failures that need attention.
  error,
}

/// Central application logger.
///
/// Example:
/// ```dart
/// ChhayaLog.i('Backend sync complete', name: 'Sync');
/// ChhayaLog.e('Decryption failed', name: 'Crypto', error: e);
/// ```
class ChhayaLog {
  ChhayaLog._();

  /// Debug-level log. No-op in release mode.
  static void d(String message, {String name = 'Chhaya'}) {
    developer.log(message, name: name, level: LogLevel.debug.index * 100);
  }

  /// Info-level log for normal operational events.
  static void i(String message, {String name = 'Chhaya'}) {
    developer.log(message, name: name, level: LogLevel.info.index * 100);
  }

  /// Warning-level log for recoverable problems.
  static void w(String message, {String name = 'Chhaya', Object? error}) {
    developer.log(
      message,
      name: name,
      level: LogLevel.warning.index * 100,
      error: error,
    );
  }

  /// Error-level log for failures. Never pass keys or message content.
  static void e(
    String message, {
    String name = 'Chhaya',
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: name,
      level: LogLevel.error.index * 100,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
