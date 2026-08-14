import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto_lib;
import 'package:pointycastle/export.dart';
import '../models/chhaya_id.dart';


class ChhayaKeyPair {
  final Uint8List publicKey;
  final Uint8List privateKey;

  ChhayaKeyPair({required this.publicKey, required this.privateKey});

  String get publicKeyHex =>
      publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  String get privateKeyHex =>
      privateKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  factory ChhayaKeyPair.fromHex(String publicHex, String privateHex) {
    return ChhayaKeyPair(
      publicKey: _hexToBytes(publicHex),
      privateKey: _hexToBytes(privateHex),
    );
  }

  static Uint8List _hexToBytes(String hex) {
    final length = hex.length ~/ 2;
    final result = Uint8List(length);
    for (int i = 0; i < length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}


class EncryptedPayload {
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List tag;

  EncryptedPayload({
    required this.nonce,
    required this.ciphertext,
    required this.tag,
  });


  String toBase64() {
    final combined = Uint8List(nonce.length + tag.length + ciphertext.length);
    combined.setAll(0, nonce);
    combined.setAll(nonce.length, tag);
    combined.setAll(nonce.length + tag.length, ciphertext);
    return base64Encode(combined);
  }


  factory EncryptedPayload.fromBase64(String encoded) {
    final combined = base64Decode(encoded);
    return EncryptedPayload(
      nonce: Uint8List.fromList(combined.sublist(0, 12)),
      tag: Uint8List.fromList(combined.sublist(12, 28)),
      ciphertext: Uint8List.fromList(combined.sublist(28)),
    );
  }
}


class ChhayaCryptoEngine {
  final SecureRandom _secureRandom;

  ChhayaCryptoEngine() : _secureRandom = _createSecureRandom();

  static SecureRandom _createSecureRandom() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }


  ChhayaKeyPair generateKeyPair() {
    final privateKey = _secureRandom.nextBytes(32);
    final publicKey = hashData(privateKey);
    return ChhayaKeyPair(publicKey: publicKey, privateKey: privateKey);
  }


  ChhayaId generateChhayaId() {
    final keyPair = generateKeyPair();

    final idBytes = keyPair.publicKey.sublist(0, 33.clamp(0, keyPair.publicKey.length));
    final paddedBytes = Uint8List(33);
    paddedBytes.setAll(0, idBytes);
    final hexId = paddedBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return ChhayaId(publicKey: hexId, createdAt: DateTime.now());
  }


  EncryptedPayload encryptMessage(String plaintext, Uint8List sharedSecret) {
    final nonce = _secureRandom.nextBytes(12);
    final key = _deriveEncryptionKey(sharedSecret);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128,
          nonce,
          Uint8List(0),
        ),
      );

    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
    final outputLength = cipher.getOutputSize(plaintextBytes.length);
    final output = Uint8List(outputLength);

    var offset = 0;
    offset += cipher.processBytes(plaintextBytes, 0, plaintextBytes.length, output, 0);
    offset += cipher.doFinal(output, offset);

    final ciphertext = Uint8List.fromList(output.sublist(0, offset - 16));
    final tag = Uint8List.fromList(output.sublist(offset - 16, offset));

    return EncryptedPayload(nonce: nonce, ciphertext: ciphertext, tag: tag);
  }


  String decryptMessage(EncryptedPayload payload, Uint8List sharedSecret) {
    final key = _deriveEncryptionKey(sharedSecret);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          payload.nonce,
          Uint8List(0),
        ),
      );


    final input = Uint8List(payload.ciphertext.length + payload.tag.length);
    input.setAll(0, payload.ciphertext);
    input.setAll(payload.ciphertext.length, payload.tag);

    final outputLength = cipher.getOutputSize(input.length);
    final output = Uint8List(outputLength);

    var offset = 0;
    offset += cipher.processBytes(input, 0, input.length, output, 0);
    offset += cipher.doFinal(output, offset);

    return utf8.decode(output.sublist(0, offset));
  }


  Uint8List deriveSharedSecret(Uint8List myPrivateKey, Uint8List theirPublicKey) {
    final combined = Uint8List(myPrivateKey.length + theirPublicKey.length);
    combined.setAll(0, myPrivateKey);
    combined.setAll(myPrivateKey.length, theirPublicKey);
    return hashData(combined);
  }


  Uint8List hashData(Uint8List data) {
    final digest = crypto_lib.sha256.convert(data);
    return Uint8List.fromList(digest.bytes);
  }


  Uint8List _deriveEncryptionKey(Uint8List sharedSecret) {
    return hashData(sharedSecret).sublist(0, 32);
  }


  List<String> generateRecoveryPhrase() {
    const wordlist = [
      'abandon', 'ability', 'able', 'about', 'above', 'absent',
      'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
      'account', 'accuse', 'achieve', 'acid', 'acoustic', 'acquire',
      'across', 'act', 'action', 'actor', 'actress', 'actual',
      'adapt', 'add', 'addict', 'address', 'adjust', 'admit',
      'adult', 'advance', 'advice', 'aerobic', 'affair', 'afford',
      'afraid', 'again', 'age', 'agent', 'agree', 'ahead',
      'aim', 'air', 'airport', 'aisle', 'alarm', 'album',
      'alcohol', 'alert', 'alien', 'all', 'alley', 'allow',
      'almost', 'alone', 'alpha', 'already', 'also', 'alter',
      'always', 'amateur', 'amazing', 'among', 'amount', 'amused',
      'analyst', 'anchor', 'ancient', 'anger', 'angle', 'angry',
      'animal', 'ankle', 'announce', 'annual', 'another', 'answer',
      'antenna', 'antique', 'anxiety', 'any', 'apart', 'apology',
      'appear', 'apple', 'approve', 'april', 'arch', 'arctic',
      'area', 'arena', 'argue', 'arm', 'armed', 'armor',
      'army', 'around', 'arrange', 'arrest', 'arrive', 'arrow',
      'art', 'artefact', 'artist', 'artwork', 'ask', 'aspect',
      'assault', 'asset', 'assist', 'assume', 'asthma', 'athlete',
      'atom', 'attack', 'attend', 'attitude', 'attract', 'auction',
      'audit', 'august', 'aunt', 'author', 'auto', 'autumn',
      'average', 'avocado', 'avoid', 'awake', 'aware', 'awesome',
      'awful', 'awkward', 'axis', 'baby', 'bachelor', 'bacon',
      'badge', 'bag', 'balance', 'balcony', 'ball', 'bamboo',
      'banana', 'banner', 'bar', 'barely', 'bargain', 'barrel',
      'base', 'basic', 'basket', 'battle', 'beach', 'bean',
      'beauty', 'because', 'become', 'beef', 'before', 'begin',
      'behave', 'behind', 'believe', 'below', 'belt', 'bench',
      'benefit', 'best', 'betray', 'better', 'between', 'beyond',
      'bicycle', 'bid', 'bike', 'bind', 'biology', 'bird',
      'birth', 'bitter', 'black', 'blade', 'blame', 'blanket',
      'blast', 'bleak', 'bless', 'blind', 'blood', 'blossom',
      'blow', 'blue', 'blur', 'blush', 'board', 'boat',
      'body', 'boil', 'bomb', 'bone', 'bonus', 'book',
      'boost', 'border', 'boring', 'borrow', 'boss', 'bottom',
      'bounce', 'box', 'boy', 'bracket', 'brain', 'brand',
      'brass', 'brave', 'bread', 'breeze', 'brick', 'bridge',
      'brief', 'bright', 'bring', 'brisk', 'broccoli', 'broken',
      'bronze', 'broom', 'brother', 'brown', 'brush', 'bubble',
      'buddy', 'budget', 'buffalo', 'build', 'bulb', 'bulk',
      'bullet', 'bundle', 'bunny', 'burden', 'burger', 'burst',
      'bus', 'business', 'busy', 'butter', 'buyer', 'buzz',
      'cabbage', 'cabin', 'cable', 'cactus', 'cage', 'cake',
      'call', 'calm', 'camera', 'camp', 'can', 'canal',
      'cancel', 'candy', 'cannon', 'canoe', 'canvas', 'canyon',
      'capable', 'capital', 'captain', 'carbon', 'cargo', 'carpet',
      'carry', 'cart', 'case', 'cash', 'casino', 'castle',
      'casual', 'catalog', 'catch', 'category', 'cattle', 'caught',
      'cause', 'caution', 'cave', 'ceiling', 'celery', 'cement',
      'census', 'century', 'cereal', 'certain', 'chair', 'chalk',
      'champion', 'change', 'chaos', 'chapter', 'charge', 'chase',
      'cheap', 'check', 'cheese', 'cherry', 'chest', 'chicken',
      'chief', 'child', 'chimney', 'choice', 'choose', 'chronic',
      'chunk', 'circle', 'citizen', 'city', 'civil', 'claim',
      'clap', 'clarify', 'claw', 'clay', 'clean', 'clerk',
      'clever', 'click', 'client', 'cliff', 'climb', 'clinic',
      'clip', 'clock', 'clog', 'close', 'cloth', 'cloud',
      'clown', 'club', 'clump', 'cluster', 'clutch', 'coach',
    ];

    final random = Random.secure();
    return List.generate(12, (_) => wordlist[random.nextInt(wordlist.length)]);
  }


  Uint8List generateNonce(int length) {
    return _secureRandom.nextBytes(length);
  }
}



class DoubleRatchetSession {
  final String peerId;
  Uint8List rootKey;
  Uint8List? sendingChainKey;
  Uint8List? receivingChainKey;


  ChhayaKeyPair dhrsKeyPair;
  Uint8List? dhriPublicKey;

  DoubleRatchetSession({
    required this.peerId,
    required this.rootKey,
    required this.dhrsKeyPair,
    this.sendingChainKey,
    this.receivingChainKey,
    this.dhriPublicKey,
  });



  ({Uint8List messageKey, Uint8List newChainKey}) ratchetSendChain() {
    if (sendingChainKey == null) {
      throw StateError('Sending chain key not initialized');
    }



    final hmacInput = Uint8List.fromList([0x01, ...sendingChainKey!]);
    final derived = _hkdfDerive(sendingChainKey!, hmacInput);

    final messageKey = derived.sublist(0, 32);
    final newChainKey = derived.sublist(32, 64);


    sendingChainKey = newChainKey;

    return (messageKey: messageKey, newChainKey: newChainKey);
  }



  ({Uint8List messageKey, Uint8List newChainKey}) ratchetReceiveChain() {
    if (receivingChainKey == null) {
      throw StateError('Receiving chain key not initialized');
    }

    final hmacInput = Uint8List.fromList([0x01, ...receivingChainKey!]);
    final derived = _hkdfDerive(receivingChainKey!, hmacInput);

    final messageKey = derived.sublist(0, 32);
    final newChainKey = derived.sublist(32, 64);


    receivingChainKey = newChainKey;

    return (messageKey: messageKey, newChainKey: newChainKey);
  }


  void performDhRatchetStep(Uint8List newRemoteDhPublicKey, ChhayaCryptoEngine engine) {
    dhriPublicKey = newRemoteDhPublicKey;


    final sharedSecret = engine.deriveSharedSecret(dhrsKeyPair.privateKey, dhriPublicKey!);



    final derived = _hkdfDerive(rootKey, sharedSecret);

    rootKey = derived.sublist(0, 32);
    receivingChainKey = derived.sublist(32, 64);


    dhrsKeyPair = engine.generateKeyPair();


    final newSharedSecret = engine.deriveSharedSecret(dhrsKeyPair.privateKey, dhriPublicKey!);


    final derivedSend = _hkdfDerive(rootKey, newSharedSecret);
    rootKey = derivedSend.sublist(0, 32);
    sendingChainKey = derivedSend.sublist(32, 64);
  }


  static Uint8List _hkdfDerive(Uint8List ikm, Uint8List salt) {
    final digest = crypto_lib.sha256;




    final keyBytes = Uint8List.fromList(ikm + salt);
    final hash1 = digest.convert(keyBytes).bytes;
    final hash2 = digest.convert(Uint8List.fromList(hash1 + const [0x01])).bytes;

    final result = Uint8List(64);
    result.setAll(0, hash1);
    result.setAll(32, hash2);
    return result;
  }
}

