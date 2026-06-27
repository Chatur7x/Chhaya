import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointycastle/export.dart';
import 'dart:convert';

final keyVerificationServiceProvider = Provider<KeyVerificationService>((ref) {
  return KeyVerificationService();
});

class KeyVerificationService {
  String generateSafetyNumber(String publicKey1, String publicKey2) {
    final keys = [publicKey1, publicKey2]..sort();
    final combinedInput = keys.join('|');

    final sha256Digest = SHA256Digest();
    final inputBytes = utf8.encode(combinedInput);
    final hash = sha256Digest.process(Uint8List.fromList(inputBytes));

    final hexHash = _bytesToHex(hash);
    final numbersOnly = _hexToNumbers(hexHash);

    return _formatAsGroups(numbersOnly, 5, ' ');
  }

  bool verifySafetyNumber(String expected, String scanned) {
    final cleanExpected = expected.replaceAll(RegExp(r'\s'), '');
    final cleanScanned = scanned.replaceAll(RegExp(r'\s'), '');
    return cleanExpected == cleanScanned;
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hexToNumbers(String hex) {
    final buffer = StringBuffer();
    for (int i = 0; i < hex.length; i++) {
      final charCode = hex.codeUnitAt(i);
      buffer.write(charCode % 10);
    }
    return buffer.toString();
  }

  String _formatAsGroups(String input, int groupSize, String separator) {
    final groups = <String>[];
    for (int i = 0; i < input.length; i += groupSize) {
      if (i + groupSize <= input.length) {
        groups.add(input.substring(i, i + groupSize));
      }
    }
    return groups.join(separator);
  }
}
