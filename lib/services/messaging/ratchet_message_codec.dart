import 'dart:convert';
import 'dart:typed_data';
import '../../core/crypto/chhaya_crypto_engine.dart';
import '../../core/crypto/primitives/aes_gcm.dart';
import '../../core/crypto/primitives/hkdf.dart';
import '../../core/crypto/primitives/rng.dart';
import '../../core/crypto/ratchet/session_store.dart';
import '../../core/crypto/ratchet/session_state.dart';
import '../../core/crypto/ratchet/triple_ratchet.dart';
import '../../core/models/contact.dart';

/// Authenticated direct-message envelopes. Callers serialize operations per
/// account. Ratchet state is committed only after successful authentication.
class RatchetMessageCodec {
  final SessionStorage sessions;
  final ChhayaKeyPair identity;
  final String ownId;
  RatchetMessageCodec({required this.sessions, required this.identity, required this.ownId});

  Future<SessionState> _state(Contact peer, String conversation) async {
    if(!peer.isVerified) { throw StateError('Verify this contact using their QR code first'); }
    final key = '$conversation:${peer.chhayaId.publicKey}';
    final saved = await sessions.loadSession(key);
    if(saved != null) { return saved; }
    final hex = peer.chhayaId.publicKey;
    if(!RegExp(r'^05[0-9a-f]{64}$').hasMatch(hex)) { throw StateError('Invalid contact identity'); }
    final publicKey = Uint8List.fromList(List.generate(32, (i) => int.parse(hex.substring(2+i*2, 4+i*2), radix:16)));
    final shared = await ChhayaCryptoEngine.deriveSharedSecret(identity.privateKey, publicKey);
    if(shared.every((byte) => byte == 0)) { throw StateError('Invalid peer key'); }
    final secret = Hkdf.deriveKey(inputKeyMaterial: shared,
        info: Uint8List.fromList(utf8.encode('Chhaya-direct-v1:$conversation')), length: 32);
    try {
      return await TripleRatchet.startSession(peer: peer.copyWith(id:key),
        remoteDhPublicKey: publicKey, sharedSecret: secret,
        initiator: ownId.compareTo(hex)<0, ourPrivateKey: identity.privateKey);
    } finally { Csprng.wipe(shared); Csprng.wipe(secret); }
  }

  Uint8List _aad(String conversation, String messageId, String sender) =>
      Uint8List.fromList(utf8.encode(jsonEncode(['chhaya-message-v1',conversation,messageId,sender])));

  Future<String> encrypt(Contact peer, String conversation, String messageId,
      String sender, Map<String,dynamic> payload,
      {Future<void> Function(SessionState state,String envelope)? commit}) async {
    final state = await _state(peer,conversation);
    final step = await TripleRatchet.encrypt(state);
    try {
      final header = step.header.toBytes();
      final aad = Uint8List.fromList([..._aad(conversation,messageId,sender),...header]);
      final bytes = AesGcm.encryptBytes(step.keys.messageKey,
          Uint8List.fromList(utf8.encode(jsonEncode(payload))), nonce:step.keys.nonce,aad:aad);
      final envelope=jsonEncode({'v':1,'header':base64Encode(header),'body':base64Encode(bytes)});
      // Persist before transport; the caller can atomically save its outbox.
      if(commit!=null) { await commit(state,envelope); }
      else { await sessions.saveSession(state); }
      return envelope;
    } finally { step.keys.wipe(); state.wipe(); }
  }

  Future<Map<String,dynamic>> decrypt(Contact peer,String conversation,
      String messageId,String sender,String envelope,{Future<void> Function(SessionState state,Map<String,dynamic> payload)? commit}) async {
    final wire=jsonDecode(envelope) as Map<String,dynamic>;
    if(wire['v']!=1) { throw const FormatException('Unsupported message protocol'); }
    final header=base64Decode(wire['header'] as String);
    final state=await _state(peer,conversation);
    final keys=await TripleRatchet.decrypt(state,TripleHeader.fromBytes(header));
    try {
      final aad=Uint8List.fromList([..._aad(conversation,messageId,sender),...header]);
      final plain=AesGcm.decryptBytes(keys.messageKey,base64Decode(wire['body'] as String),aad:aad);
      final result=jsonDecode(utf8.decode(plain)) as Map<String,dynamic>;
      if(commit!=null) { await commit(state,result); }
      else { await sessions.saveSession(state); }
      return result;
    } finally { keys.wipe(); state.wipe(); }
  }
}
