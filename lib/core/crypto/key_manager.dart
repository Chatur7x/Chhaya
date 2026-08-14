import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'chhaya_crypto_engine.dart';

class KeyManager {
  static const _publicKeyKey = 'Chhaya_public_key';
  static const _privateKeyKey = 'Chhaya_private_key';
  static const _recoveryPhraseKey = 'Chhaya_recovery_phrase';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }


  Future<void> storeKeyPair(ChhayaKeyPair keyPair) async {
    final prefs = await _preferences;
    await prefs.setString(_publicKeyKey, base64Encode(keyPair.publicKey));
    await prefs.setString(_privateKeyKey, base64Encode(keyPair.privateKey));
  }


  Future<ChhayaKeyPair?> getKeyPair() async {
    final prefs = await _preferences;
    final publicKeyB64 = prefs.getString(_publicKeyKey);
    final privateKeyB64 = prefs.getString(_privateKeyKey);

    if (publicKeyB64 == null || privateKeyB64 == null) return null;

    return ChhayaKeyPair(
      publicKey: Uint8List.fromList(base64Decode(publicKeyB64)),
      privateKey: Uint8List.fromList(base64Decode(privateKeyB64)),
    );
  }


  Future<void> storeRecoveryPhrase(List<String> phrase) async {
    final prefs = await _preferences;
    await prefs.setStringList(_recoveryPhraseKey, phrase);
  }


  Future<List<String>?> getRecoveryPhrase() async {
    final prefs = await _preferences;
    return prefs.getStringList(_recoveryPhraseKey);
  }


  Future<bool> hasKeys() async {
    final prefs = await _preferences;
    return prefs.containsKey(_publicKeyKey) &&
        prefs.containsKey(_privateKeyKey);
  }


  Future<void> clearAllKeys() async {
    final prefs = await _preferences;
    await prefs.remove(_publicKeyKey);
    await prefs.remove(_privateKeyKey);
    await prefs.remove(_recoveryPhraseKey);
  }
}
