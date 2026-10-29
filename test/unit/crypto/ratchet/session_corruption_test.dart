import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/crypto/ratchet/session_store.dart';

class CorruptSessionDatabase extends LocalDatabase {
  final String? raw;
  CorruptSessionDatabase(this.raw);
  @override
  Future<String?> loadSessionBlob(String peerId) async => raw;
}

void main() {
  test('only absent sessions allow fresh establishment', () async {
    final store = LocalDatabaseSessionStorage(CorruptSessionDatabase(null));
    expect(await store.loadSession('peer'), isNull);
  });
  for (final raw in ['not json', '{}', '[]']) {
    test('corrupt persisted state fails closed: $raw', () async {
      final store = LocalDatabaseSessionStorage(CorruptSessionDatabase(raw));
      await expectLater(store.loadSession('peer'), throwsStateError);
    });
  }
}
