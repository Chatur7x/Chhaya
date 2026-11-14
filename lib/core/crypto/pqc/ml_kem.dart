// ML-KEM-1024 adapter for the pinned native AWS-LC provider.
import 'dart:typed_data';

import 'package:chhaya_pqc/chhaya_pqc.dart';

import 'pqc_provider.dart';

/// ML-KEM-1024 (FIPS 203) primitive adapter. Protocol use stays separately gated.
class MlKem1024 implements PqKem {
  @override
  String get name => 'ML-KEM-1024';

  @override
  bool get isAvailable => ChhayaPqc.isAvailable;

  @override
  Future<bool> initialize() => ChhayaPqc.initialize();

  @override
  Future<({Uint8List publicKey, Uint8List privateKey})> generateKeyPair() async {
    final pair = await ChhayaPqc.generateKemKeyPair();
    return (publicKey: pair.publicKey, privateKey: pair.privateKey);
  }

  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
    Uint8List publicKey,
  ) async {
    if (!await initialize()) throw PqcUnavailableException(name);
    return ChhayaPqc.encapsulate(publicKey);
  }

  @override
  Future<Uint8List> decapsulate(
    Uint8List privateKey,
    Uint8List ciphertext,
  ) async {
    if (!await initialize()) throw PqcUnavailableException(name);
    return ChhayaPqc.decapsulate(privateKey, ciphertext);
  }
}
