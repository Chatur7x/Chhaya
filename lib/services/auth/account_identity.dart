import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../../core/crypto/chhaya_crypto_engine.dart';
import '../../core/crypto/primitives/bip39.dart';
import '../../core/crypto/primitives/rng.dart';

/// Versioned, deterministic identity for newly created accounts.
/// Existing randomly generated accounts require their encrypted key backup.
class AccountIdentity {
  AccountIdentity._();

  static Future<ChhayaKeyPair> fromRecoveryPhrase(List<String> words) async {
    if(words.length != 12) { throw ArgumentError('Recovery phrase must contain 12 words'); }
    final entropy = Bip39.mnemonicToEntropy(words);
    Csprng.wipe(entropy);
    final seed = ChhayaCryptoEngine.keyFromRecoveryPhrase(words.join(' '),
        salt: Uint8List.fromList('chhaya-identity-x25519-v1'.codeUnits));
    try {
      final pair = await X25519().newKeyPairFromSeed(seed);
      return ChhayaKeyPair(
          publicKey: Uint8List.fromList((await pair.extractPublicKey()).bytes),
          privateKey: Uint8List.fromList(await pair.extractPrivateKeyBytes()));
    } finally {
      Csprng.wipe(seed);
    }
  }

  static String idFor(ChhayaKeyPair pair) => '05${pair.publicKeyHex}';
}
