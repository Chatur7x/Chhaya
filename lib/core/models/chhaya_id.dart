import 'dart:math';

class ChhayaId {
  final String publicKey;
  final String shortId;
  final DateTime createdAt;

  ChhayaId({
    required this.publicKey,
    required this.createdAt,
  }) : shortId = publicKey.length >= 8 ? publicKey.substring(0, 8) : publicKey;


  factory ChhayaId.generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(33, (_) => random.nextInt(256));
    final publicKey = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return ChhayaId(
      publicKey: publicKey,
      createdAt: DateTime.now(),
    );
  }

  factory ChhayaId.fromPublicKey(String publicKey) {
    return ChhayaId(
      publicKey: publicKey,
      createdAt: DateTime.now(),
    );
  }

  factory ChhayaId.fromJson(Map<String, dynamic> json) {
    return ChhayaId(
      publicKey: json['publicKey'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'publicKey': publicKey,
    'createdAt': createdAt.toIso8601String(),
  };

  String get displayId => '$shortId...${publicKey.substring(publicKey.length - 4)}';

  @override
  String toString() => '$shortId...';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChhayaId && publicKey == other.publicKey;

  @override
  int get hashCode => publicKey.hashCode;
}
