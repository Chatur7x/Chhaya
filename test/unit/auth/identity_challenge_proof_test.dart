import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/services/auth/identity_challenge_proof.dart';

void main(){
  test('Dart identity proof matches Node reference and binds purpose and device',() async {
    final f=jsonDecode(File('test/fixtures/identity-proof.json').readAsStringSync()) as Map<String,dynamic>;
    Uint8List hex(String value)=>Uint8List.fromList(List.generate(value.length~/2,(i)=>int.parse(value.substring(i*2,i*2+2),radix:16)));
    final identity=ChhayaKeyPair(privateKey:hex(f['privateKey'] as String),publicKey:hex(f['publicKey'] as String));
    final challenge=Map<String,dynamic>.from(f['challenge'] as Map);
    final proof=await IdentityChallengeProof.create(identity:identity,purpose:'register',deviceId:f['deviceId'] as String,challenge:challenge);
    expect(proof,f['expectedProof']);
    expect(await IdentityChallengeProof.create(identity:identity,purpose:'login',deviceId:f['deviceId'] as String,challenge:challenge),isNot(proof));
    expect(await IdentityChallengeProof.create(identity:identity,purpose:'register',deviceId:'other-device',challenge:challenge),isNot(proof));
    await expectLater(IdentityChallengeProof.create(identity:identity,purpose:'register',deviceId:f['deviceId'] as String,challenge:{...challenge,'serverPublicKey':'invalid'}),throwsFormatException);
  });
}
