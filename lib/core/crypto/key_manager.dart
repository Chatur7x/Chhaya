import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'chhaya_crypto_engine.dart';

class KeyManager {
  static const _publicKeyKey = 'Chhaya_public_key';
  static const _privateKeyKey = 'Chhaya_private_key';
  static const _recoveryPhraseKey = 'Chhaya_recovery_phrase';
  static const _chhayaIdKey = 'Chhaya_chhaya_id';
  final FlutterSecureStorage _storage;
  KeyManager({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  Future<void> storeKeyPair(ChhayaKeyPair keyPair) async {
    await _storage.write(key: _publicKeyKey, value: base64Encode(keyPair.publicKey));
    await _storage.write(key: _privateKeyKey, value: base64Encode(keyPair.privateKey));
  }
  Future<ChhayaKeyPair?> getKeyPair() async {
    final pub = await _storage.read(key: _publicKeyKey);
    final priv = await _storage.read(key: _privateKeyKey);
    if (pub == null || priv == null) return null;
    return ChhayaKeyPair(publicKey: base64Decode(pub), privateKey: base64Decode(priv));
  }
  Future<void> storeRecoveryPhrase(List<String> phrase) async => _storage.write(key: _recoveryPhraseKey, value: jsonEncode(phrase));
  Future<List<String>?> getRecoveryPhrase() async {
    final s = await _storage.read(key: _recoveryPhraseKey);
    if (s == null) return null;
    return (jsonDecode(s) as List).cast<String>();
  }
  Future<void> storeChhayaId(String id) async => _storage.write(key: _chhayaIdKey, value: id);
  Future<String?> getChhayaId() async => _storage.read(key: _chhayaIdKey);
  Future<bool> hasKeys() async { final p = await _storage.read(key: _publicKeyKey); final pr = await _storage.read(key: _privateKeyKey); return p != null && pr != null; }
  Future<void> clearAllKeys() async { await _storage.delete(key: _publicKeyKey); await _storage.delete(key: _privateKeyKey); await _storage.delete(key: _recoveryPhraseKey); await _storage.delete(key: _chhayaIdKey); }
}
