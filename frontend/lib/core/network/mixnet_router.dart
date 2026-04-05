import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class MixPackage {
  final String id;
  final List<String> messages;
  final DateTime createdAt;
  final int mixIndex;
  final Uint8List ciphertext;

  MixPackage({
    required this.id,
    required this.messages,
    required this.createdAt,
    required this.mixIndex,
    required this.ciphertext,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'messages': messages,
        'createdAt': createdAt.toIso8601String(),
        'mixIndex': mixIndex,
        'ciphertext': ciphertext.toList(),
      };
}

class MixNode {
  final String id;
  final String address;
  final DateTime lastSeen;
  final bool isOnline;

  MixNode({
    required this.id,
    required this.address,
    required this.lastSeen,
    required this.isOnline,
  });
}

class MixnetRouter {
  final List<MixNode> _mixNodes = [];
  final Random _random = Random.secure();
  final Map<String, List<String>> _activeCircuits = {};
  String _nodeId = 'local';

  static const int _minMixChainLength = 3;
  static const int _maxMixChainLength = 7;
  static const int _defaultBatchSize = 20;
  static const Duration _mixDelay = Duration(seconds: 5);
  static const Duration _maxMixDelay = Duration(seconds: 30);

  int _mixChainLength = 3;
  int _batchSize = _defaultBatchSize;
  int _maxDelaySeconds = 30;

  final _mixController = StreamController<MixPackage>.broadcast();
  Stream<MixPackage> get mixStream => _mixController.stream;

  final _circuitController = StreamController<List<String>>.broadcast();
  Stream<List<String>> get circuitStream => _circuitController.stream;

  String get nodeId => _nodeId;
  List<MixNode> get activeNodes => _mixNodes.where((n) => n.isOnline).toList();

  void setMixChainLength(int length) {
    _mixChainLength = length.clamp(_minMixChainLength, _maxMixChainLength);
  }

  void setBatchSize(int size) {
    _batchSize = size.clamp(10, 50);
  }

  void setMaxDelay(int seconds) {
    _maxDelaySeconds = seconds.clamp(1, 30);
  }

  void registerMixNode(MixNode node) {
    final existing = _mixNodes.indexWhere((n) => n.id == node.id);
    if (existing >= 0) {
      _mixNodes[existing] = node;
    } else {
      _mixNodes.add(node);
    }
  }

  void removeMixNode(String nodeId) {
    _mixNodes.removeWhere((n) => n.id == nodeId);
    _activeCircuits.remove(nodeId);
  }

  List<String> generateMixChain({int? length}) {
    final onlineNodes = activeNodes;
    if (onlineNodes.length < _minMixChainLength) {
      return [];
    }

    final chainLength = length ?? _mixChainLength;
    final chain = <String>[];

    final shuffled = List<MixNode>.from(onlineNodes)..shuffle(_random);

    for (int i = 0; i < chainLength && i < shuffled.length; i++) {
      chain.add(shuffled[i].id);
    }

    if (chain.length >= _minMixChainLength) {
      _activeCircuits[DateTime.now().millisecondsSinceEpoch.toString()] = chain;
      _circuitController.add(chain);
    }

    return chain;
  }

  MixPackage createMixPackage(List<String> messageIds, int mixIndex) {
    final delay = _random.nextInt(_maxDelaySeconds) + 1;
    final package = MixPackage(
      id: 'MIX_${DateTime.now().millisecondsSinceEpoch}',
      messages: messageIds,
      createdAt: DateTime.now().add(Duration(seconds: delay)),
      mixIndex: mixIndex,
      ciphertext: _encryptBatch(messageIds),
    );

    _mixController.add(package);
    return package;
  }

  Uint8List _encryptBatch(List<String> messageIds) {
    final data = messageIds.join(',').codeUnits;
    final encrypted = Uint8List.fromList(data);
    for (int i = 0; i < encrypted.length; i++) {
      encrypted[i] = (encrypted[i] + _random.nextInt(256)) % 256;
    }
    return encrypted;
  }

  Uint8List decryptBatch(Uint8List ciphertext) {
    final decrypted = Uint8List.fromList(ciphertext);
    for (int i = 0; i < decrypted.length; i++) {
      decrypted[i] = (decrypted[i] - _random.nextInt(256)) % 256;
    }
    return decrypted;
  }

  Duration getRandomDelay() {
    return Duration(seconds: _random.nextInt(_maxDelaySeconds) + 1);
  }

  Map<String, dynamic> getStatistics() {
    return {
      'totalMixNodes': _mixNodes.length,
      'onlineMixNodes': activeNodes.length,
      'activeCircuits': _activeCircuits.length,
      'mixChainLength': _mixChainLength,
      'batchSize': _batchSize,
      'maxDelay': _maxDelaySeconds,
    };
  }

  void dispose() {
    _mixController.close();
    _circuitController.close();
  }
}
