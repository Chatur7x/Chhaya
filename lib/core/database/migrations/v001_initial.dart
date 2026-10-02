// Migration v001 — users, contacts, kv (V14 Part 3).
//
// Purpose: identity and address-book tables plus the settings
// key-value store. Content columns are encrypted envelopes; indices
// cover routing metadata only.
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../schema.dart';
import 'migration_runner.dart';

/// v001: users, contacts, kv, contacts-by-owner index.
class MigrationV001Initial extends Migration {
  @override
  int get version => 1;

  @override
  String get name => 'initial users/contacts/kv';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${DbTables.users} ('
      '${DbCols.id} TEXT PRIMARY KEY, '
      '${DbCols.chhayaId} TEXT UNIQUE NOT NULL, '
      '${DbCols.displayNameEnc} TEXT NOT NULL, '
      '${DbCols.publicKey} TEXT NOT NULL, '
      '${DbCols.encryptedPrivateKey} TEXT NOT NULL, '
      '${DbCols.createdAt} INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${DbTables.contacts} ('
      '${DbCols.userId} TEXT NOT NULL, '
      '${DbCols.contactId} TEXT NOT NULL, '
      '${DbCols.displayNameEnc} TEXT NOT NULL, '
      '${DbCols.avatarEnc} TEXT, '
      '${DbCols.verificationLevel} INTEGER NOT NULL DEFAULT 1, '
      '${DbCols.isBlocked} INTEGER NOT NULL DEFAULT 0, '
      '${DbCols.addedAt} INTEGER NOT NULL, '
      'PRIMARY KEY (${DbCols.userId}, ${DbCols.contactId}))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${DbTables.kv} ('
      '${DbCols.key} TEXT PRIMARY KEY, '
      '${DbCols.value} TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ${DbIndices.contactsByUser} '
      'ON ${DbTables.contacts} (${DbCols.userId})',
    );
  }

  @override
  Future<void> down(DatabaseExecutor db) async {
    await db.execute('DROP INDEX IF EXISTS ${DbIndices.contactsByUser}');
    await db.execute('DROP TABLE IF EXISTS ${DbTables.kv}');
    await db.execute('DROP TABLE IF EXISTS ${DbTables.contacts}');
    await db.execute('DROP TABLE IF EXISTS ${DbTables.users}');
  }
}
