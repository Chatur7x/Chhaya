import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import '../../core/crypto/chhaya_crypto_engine.dart';
import '../../core/crypto/primitives/rng.dart';

/// Wire-compatible proof of X25519 private-key possession. No key or shared
/// secret leaves the client. The transcript binds purpose, device and both keys.
class IdentityChallengeProof {
  IdentityChallengeProof._();
  static Future<String> create({required ChhayaKeyPair identity,
    required String purpose,required String deviceId,
    required Map<String,dynamic> challenge}) async {
    final id=challenge['challengeId'];
    final server=challenge['serverPublicKey'];
    final nonce=challenge['nonce'];
    if(!['register','login'].contains(purpose)||id is! String||
        !RegExp(r'^[0-9a-f-]{36}$').hasMatch(id)||server is! String||nonce is! String||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(server)||!RegExp(r'^[0-9a-f]{64}$').hasMatch(nonce)) {
      throw const FormatException('Invalid identity challenge');
    }
    final public=Uint8List.fromList(List.generate(32,(i)=>int.parse(server.substring(i*2,i*2+2),radix:16)));
    final shared=await ChhayaCryptoEngine.deriveSharedSecret(identity.privateKey,public);
    try {
      if(shared.every((byte)=>byte==0)) { throw const FormatException('Invalid server key'); }
      final transcript='chhaya-auth-v1|$purpose|$id|$deviceId|${identity.publicKeyHex}|$server|$nonce';
      return crypto.Hmac(crypto.sha256,shared).convert(utf8.encode(transcript)).toString();
    } finally { Csprng.wipe(shared); }
  }
}
