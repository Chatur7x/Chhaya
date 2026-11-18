// ML-DSA-87 adapter for the pinned native AWS-LC provider.
import 'dart:typed_data';

import 'package:chhaya_pqc/chhaya_pqc.dart';

import 'pqc_provider.dart';

/// ML-DSA-87 (FIPS 204) primitive adapter. Identity use stays separately gated.
class MlDsa87 implements PqSigner {
  @override
  String get name => 'ML-DSA-87';

  @override
  bool get isAvailable => ChhayaPqc.isAvailable;

  @override
  Future<bool> initialize() => ChhayaPqc.initialize();

  Future<ChhayaPqcKeyPair> generateKeyPair() => ChhayaPqc.generateDsaKeyPair();

  @override
  Future<Uint8List> sign(Uint8List privateKey, Uint8List message) async {
    if (!await initialize()) throw PqcUnavailableException(name);
    return ChhayaPqc.sign(privateKey, message);
  }

  @override
  Future<bool> verify(
    Uint8List publicKey,
    Uint8List message,
    Uint8List signature,
  ) async {
    if (!await initialize()) throw PqcUnavailableException(name);
    return ChhayaPqc.verify(publicKey, message, signature);
  }
}
