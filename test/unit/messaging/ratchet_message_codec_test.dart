import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/ratchet/session_store.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/services/messaging/ratchet_message_codec.dart';

void main(){
  test('two clients exchange authenticated messages, reject tampering and replay',() async {
    final a=await ChhayaCryptoEngine.generateKeyPair();
    final b=await ChhayaCryptoEngine.generateKeyPair();
    final aid='05${a.publicKeyHex}',bid='05${b.publicKeyHex}';
    final alice=RatchetMessageCodec(sessions:InMemorySessionStorage(),identity:a,ownId:aid);
    final bob=RatchetMessageCodec(sessions:InMemorySessionStorage(),identity:b,ownId:bid);
    final ap=Contact(id:'alice',chhayaId:ChhayaId.fromPublicKey(aid),displayName:'Alice',isVerified:true);
    final bp=Contact(id:'bob',chhayaId:ChhayaId.fromPublicKey(bid),displayName:'Bob',isVerified:true);
    await expectLater(alice.encrypt(bp,'conversation','failed','alice',{'content':'not committed'},
      commit:(state,envelope) async { throw StateError('disk full'); }),throwsStateError);
    final encrypted=await alice.encrypt(bp,'conversation','one','alice',{'content':'hello'});
    expect(encrypted,isNot(contains('hello')));
    final damaged=jsonDecode(encrypted) as Map<String,dynamic>;
    final bytes=base64Decode(damaged['body'] as String); bytes[bytes.length-1]^=1;
    damaged['body']=base64Encode(bytes);
    await expectLater(bob.decrypt(ap,'conversation','one','alice',jsonEncode(damaged)),throwsA(anything));
    await expectLater(bob.decrypt(ap,'conversation','one','alice',encrypted,
        commit:(state,payload) async { throw StateError('database unavailable'); }),throwsStateError);
    expect((await bob.decrypt(ap,'conversation','one','alice',encrypted))['content'],'hello');
    await expectLater(bob.decrypt(ap,'conversation','one','alice',encrypted),throwsA(anything));
    final reply=await bob.encrypt(ap,'conversation','two','bob',{'content':'reply'});
    expect((await alice.decrypt(bp,'conversation','two','bob',reply))['content'],'reply');
    final next=await alice.encrypt(bp,'conversation','three','alice',{'content':'bound metadata'});
    await expectLater(bob.decrypt(ap,'conversation','wrong-id','alice',next),throwsA(anything));
    expect((await bob.decrypt(ap,'conversation','three','alice',next))['content'],'bound metadata');
  });
  test('unverified contacts cannot start an encrypted session',() async {
    final a=await ChhayaCryptoEngine.generateKeyPair();
    final b=await ChhayaCryptoEngine.generateKeyPair();
    final codec=RatchetMessageCodec(sessions:InMemorySessionStorage(),identity:a,ownId:'05${a.publicKeyHex}');
    final peer=Contact(id:'bob',chhayaId:ChhayaId.fromPublicKey('05${b.publicKeyHex}'),displayName:'Bob');
    await expectLater(codec.encrypt(peer,'conversation','id','alice',{'content':'hello'}),throwsStateError);
  });
}
