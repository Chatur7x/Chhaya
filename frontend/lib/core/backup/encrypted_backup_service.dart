import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path_provider/path_provider.dart';

class EncryptedBackupService {
  static const String _backupDirName = 'backups';
  static const String _backupPasswordKey = 'backup_password';
  static const String _backupVersion = '1.0';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<Directory> _getBackupDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${appDir.path}/$_backupDirName');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  Future<String?> _getBackupPassword() async {
    return await _secureStorage.read(key: _backupPasswordKey);
  }

  Future<void> _setBackupPassword(String password) async {
    await _secureStorage.write(key: _backupPasswordKey, value: password);
  }

  encrypt.Key _deriveKey(String password) {
    final padded = password.padRight(32, '0');
    return encrypt.Key.fromUtf8(padded.substring(0, 32));
  }

  String _encryptData(String data, String password) {
    final key = _deriveKey(password);
    final iv = encrypt.IV.fromLength(16);
    final encrypter =
        encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final encrypted = encrypter.encrypt(data, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  String _decryptData(String encryptedData, String password) {
    final parts = encryptedData.split(':');
    if (parts.length != 2) throw Exception('Invalid encrypted data format');

    final key = _deriveKey(password);
    final iv = encrypt.IV.fromBase64(parts[0]);
    final encrypter =
        encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    return encrypter.decrypt64(parts[1], iv: iv);
  }

  Future<String> createBackup({
    required List<String> boxNames,
    String? password,
  }) async {
    final backupPassword = password ?? await _getBackupPassword();
    if (backupPassword == null) {
      throw Exception('No backup password set. Please set a password first.');
    }

    final backupData = <String, dynamic>{
      'version': _backupVersion,
      'timestamp': DateTime.now().toIso8601String(),
      'boxes': <String, dynamic>{},
    };

    for (final boxName in boxNames) {
      try {
        final box = Hive.box(boxName);
        final data = Map<String, dynamic>.from(
          box
              .toMap()
              .map((key, value) => MapEntry(key, _serializeValue(value))),
        );
        backupData['boxes'][boxName] = data;
      } catch (e) {
        print('Warning: Could not backup box $boxName: $e');
      }
    }

    final jsonString = jsonEncode(backupData);
    final encryptedData = _encryptData(jsonString, backupPassword);

    final backupDir = await _getBackupDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final backupFile = File('${backupDir.path}/backup_$timestamp.cback');
    await backupFile.writeAsString(encryptedData);

    return backupFile.path;
  }

  Future<void> restoreBackup({
    required String filePath,
    required String password,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Backup file not found');
    }

    final encryptedData = await file.readAsString();
    String decryptedData;

    try {
      decryptedData = _decryptData(encryptedData, password);
    } catch (e) {
      throw Exception('Invalid password or corrupted backup file');
    }

    final backupData = jsonDecode(decryptedData) as Map<String, dynamic>;
    final boxes = backupData['boxes'] as Map<String, dynamic>;

    for (final entry in boxes.entries) {
      final boxName = entry.key;
      final boxData = entry.value as Map<String, dynamic>;

      try {
        final box = Hive.box(boxName);
        await box.clear();

        for (final dataEntry in boxData.entries) {
          await box.put(dataEntry.key, _deserializeValue(dataEntry.value));
        }
      } catch (e) {
        print('Warning: Could not restore box $boxName: $e');
      }
    }
  }

  Future<void> deleteBackup(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<List<FileSystemEntity>> listBackups() async {
    final backupDir = await _getBackupDirectory();
    final files =
        await backupDir.list().where((f) => f.path.endsWith('.cback')).toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<bool> hasBackupPassword() async {
    final password = await _getBackupPassword();
    return password != null;
  }

  Future<void> setBackupPassword(String password) async {
    await _setBackupPassword(password);
  }

  Future<int> getBackupSize(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  Future<DateTime?> getBackupDate(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    try {
      final stat = await file.stat();
      return stat.modified;
    } catch (e) {
      return null;
    }
  }

  dynamic _serializeValue(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(
        value.map((k, v) => MapEntry(k.toString(), _serializeValue(v))),
      );
    }
    if (value is List) {
      return value.map((e) => _serializeValue(e)).toList();
    }
    return value;
  }

  dynamic _deserializeValue(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(
        value.map((k, v) => MapEntry(k.toString(), _deserializeValue(v))),
      );
    }
    if (value is List) {
      return value.map((e) => _deserializeValue(e)).toList();
    }
    return value;
  }
}
