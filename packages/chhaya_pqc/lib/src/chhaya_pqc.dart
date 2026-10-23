import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

/// Narrow Dart API for the version-pinned native AWS-LC provider.
///
/// The provider exposes primitives only. Calling [initialize] does not enable
/// or negotiate a post-quantum messaging protocol.
class ChhayaPqc {
  ChhayaPqc._();

  static const MethodChannel _channel = MethodChannel('org.chhaya/pqc');
  static Future<bool>? _probe;
  static bool _available = false;
  static String _provider = 'uninitialized';

  static bool get isAvailable => _available;
  static String get provider => _provider;

  /// Performs the native known-answer and round-trip self-check once.
  /// Unsupported targets and missing native libraries remain unavailable.
  static Future<bool> initialize() => _probe ??= _readCapabilities();

  static Future<bool> _readCapabilities() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'capabilities',
      );
      _available = result?['available'] == true;
      _provider = result?['provider'] as String? ?? 'unavailable';
    } on MissingPluginException {
      _available = false;
      _provider = 'unavailable';
    } on PlatformException {
      _available = false;
      _provider = 'unavailable';
    }
    return _available;
  }

  static Future<ChhayaPqcKeyPair> generateKemKeyPair() async {
    final output = await _run(1);
    return _splitKeyPair(output, publicLength: 1568, privateLength: 3168);
  }

  static Future<ChhayaPqcKeyPair> generateDsaKeyPair() async {
    final output = await _run(4);
    return _splitKeyPair(output, publicLength: 2592, privateLength: 4896);
  }

  static ChhayaPqcKeyPair _splitKeyPair(
    Uint8List output, {
    required int publicLength,
    required int privateLength,
  }) {
    if (output.length != publicLength + privateLength) {
      output.fillRange(0, output.length, 0);
      throw const FormatException('Native key pair length is invalid.');
    }
    final pair = ChhayaPqcKeyPair(
      publicKey: Uint8List.fromList(output.sublist(0, publicLength)),
      privateKey: Uint8List.fromList(output.sublist(publicLength)),
    );
    output.fillRange(0, output.length, 0);
    return pair;
  }

  static Future<({Uint8List ciphertext, Uint8List sharedSecret})>
      encapsulate(Uint8List publicKey) async {
    if (publicKey.length != 1568) {
      throw ArgumentError.value(publicKey.length, 'publicKey');
    }
    final output = await _run(2, key: publicKey);
    if (output.length != 1600) {
      output.fillRange(0, output.length, 0);
      throw const FormatException('Native encapsulation length is invalid.');
    }
    final result = (
      ciphertext: Uint8List.fromList(output.sublist(0, 1568)),
      sharedSecret: Uint8List.fromList(output.sublist(1568)),
    );
    output.fillRange(0, output.length, 0);
    return result;
  }

  static Future<Uint8List> decapsulate(
    Uint8List privateKey,
    Uint8List ciphertext,
  ) async {
    if (privateKey.length != 3168) {
      throw ArgumentError.value(privateKey.length, 'privateKey');
    }
    if (ciphertext.length != 1568) {
      throw ArgumentError.value(ciphertext.length, 'ciphertext');
    }
    final output = await _run(3, key: privateKey, input: ciphertext);
    if (output.length != 32) {
      output.fillRange(0, output.length, 0);
      throw const FormatException('Native decapsulation length is invalid.');
    }
    return output;
  }

  static Future<Uint8List> sign(Uint8List privateKey, Uint8List message) async {
    if (privateKey.length != 4896) {
      throw ArgumentError.value(privateKey.length, 'privateKey');
    }
    _checkMessage(message);
    final output = await _run(5, key: privateKey, input: message);
    if (output.length != 4627) {
      output.fillRange(0, output.length, 0);
      throw const FormatException('Native signature length is invalid.');
    }
    return output;
  }

  static Future<bool> verify(
    Uint8List publicKey,
    Uint8List message,
    Uint8List signature,
  ) async {
    if (publicKey.length != 2592) {
      throw ArgumentError.value(publicKey.length, 'publicKey');
    }
    if (signature.length != 4627) {
      throw ArgumentError.value(signature.length, 'signature');
    }
    _checkMessage(message);
    final output = await _run(
      6,
      key: publicKey,
      input: message,
      extra: signature,
    );
    if (output.length != 1 || output[0] > 1) {
      output.fillRange(0, output.length, 0);
      throw const FormatException('Native verification result is invalid.');
    }
    final valid = output[0] == 1;
    output.fillRange(0, output.length, 0);
    return valid;
  }

  static void _checkMessage(Uint8List message) {
    if (message.length > 1024 * 1024) {
      throw ArgumentError.value(message.length, 'message');
    }
  }

  static Future<Uint8List> _run(
    int operation, {
    Uint8List? key,
    Uint8List? input,
    Uint8List? extra,
  }) async {
    if (!await initialize()) {
      throw StateError('AWS-LC post-quantum provider is unavailable.');
    }
    final output = await _channel.invokeMethod<Uint8List>('run', {
      'operation': operation,
      'key': key ?? Uint8List(0),
      'input': input ?? Uint8List(0),
      'extra': extra ?? Uint8List(0),
    });
    if (output == null || output.length > 8192) {
      throw const FormatException('Native provider returned an invalid result.');
    }
    return output;
  }

  @visibleForTesting
  static void resetForTesting() {
    _probe = null;
    _available = false;
    _provider = 'uninitialized';
  }
}

/// Native key pair. Call [destroy] when the private key is no longer needed.
class ChhayaPqcKeyPair {
  ChhayaPqcKeyPair({required this.publicKey, required this.privateKey});

  final Uint8List publicKey;
  final Uint8List privateKey;

  void destroy() {
    privateKey.fillRange(0, privateKey.length, 0);
  }
}
