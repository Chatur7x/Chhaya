// Migration v005 — full-fidelity payload envelopes (V14 Part 3).
//
// Purpose: the v001/v002 normalized columns cover routing metadata,
// but V13 models carry richer state (pins, votes, group metadata,
// recovery phrases) that must survive the swap with zero data loss.
// `payload_enc` holds the complete model JSON under AES-GCM and is the
// read source of truth; normalized columns serve queries. Downgrade
// rebuilds the v004 schema (payload data is dropped on the way down —
// normalized rows survive).
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../queries.dart';
import '../schema.dart';
import 'migration_runner.dart';

/// v005: payload_enc envelopes on contacts, conversations, users.
class MigrationV005Payloads extends Migration {
  @override
  int get version => 5;

  @override
  String get name => 'payload envelopes';

  @override
  Future<void> up(DatabaseExecutor db) async {
    // Idempotent: plain ALTER fails when the column exists, so probe
    // the schema first instead of relying on IF NOT EXISTS (which
    // SQLite does not support for ADD COLUMN).
    await _addColumnIfMissing(db, DbTables.contacts, 'payload_enc');
    await _addColumnIfMissing(db, DbTables.conversations, 'payload_enc');
    await _addColumnIfMissing(db, DbTables.users, 'payload_enc');
  }

  @override
  Future<void> down(DatabaseExecutor db) async {
    // ALTER TABLE DROP COLUMN is unavailable on older Android SQLite
    // builds, so downgrade rebuilds the v004 tables explicitly.
    await _rebuildWithoutPayload(
      db,
      table: DbTables.contacts,
      createV004:
          '${DbCols.userId} TEXT NOT NULL, ${DbCols.contactId} TEXT NOT NULL, '
          '${DbCols.displayNameEnc} TEXT NOT NULL, ${DbCols.avatarEnc} TEXT, '
          '${DbCols.verificationLevel} INTEGER NOT NULL DEFAULT 1, '
          '${DbCols.isBlocked} INTEGER NOT NULL DEFAULT 0, '
          '${DbCols.addedAt} INTEGER NOT NULL, '
          'PRIMARY KEY (${DbCols.userId}, ${DbCols.contactId})',
      keepColumns: [
        DbCols.userId,
        DbCols.contactId,
        DbCols.displayNameEnc,
        DbCols.avatarEnc,
        DbCols.verificationLevel,
        DbCols.isBlocked,
        DbCols.addedAt,
      ],
    );
    await _rebuildWithoutPayload(
      db,
      table: DbTables.conversations,
      createV004:
          '${DbCols.id} TEXT PRIMARY KEY, ${DbCols.type} TEXT NOT NULL, '
          '${DbCols.nameEnc} TEXT, ${DbCols.avatarBlob} BLOB, '
          '${DbCols.createdBy} TEXT NOT NULL, ${DbCols.createdAt} INTEGER NOT NULL, '
          '${DbCols.pinned} INTEGER NOT NULL DEFAULT 0, '
          '${DbCols.lastTs} INTEGER NOT NULL DEFAULT 0',
      keepColumns: [
        DbCols.id,
        DbCols.type,
        DbCols.nameEnc,
        DbCols.avatarBlob,
        DbCols.createdBy,
        DbCols.createdAt,
        DbCols.pinned,
        DbCols.lastTs,
      ],
    );
    await _rebuildWithoutPayload(
      db,
      table: DbTables.users,
      createV004:
          '${DbCols.id} TEXT PRIMARY KEY, ${DbCols.chhayaId} TEXT UNIQUE NOT NULL, '
          '${DbCols.displayNameEnc} TEXT NOT NULL, ${DbCols.publicKey} TEXT NOT NULL, '
          '${DbCols.encryptedPrivateKey} TEXT NOT NULL, ${DbCols.createdAt} INTEGER NOT NULL',
      keepColumns: [
        DbCols.id,
        DbCols.chhayaId,
        DbCols.displayNameEnc,
        DbCols.publicKey,
        DbCols.encryptedPrivateKey,
        DbCols.createdAt,
      ],
    );
  }

  Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
  ) async {
    DbQueries.checkIdentifier(table);
    DbQueries.checkIdentifier(column);
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column TEXT');
    }
  }

  Future<void> _rebuildWithoutPayload(
    DatabaseExecutor db, {
    required String table,
    required String createV004,
    required List<String> keepColumns,
  }) async {
    DbQueries.checkIdentifier(table);
    for (final column in keepColumns) {
      DbQueries.checkIdentifier(column);
    }
    final cols = keepColumns.join(', ');
    await db.execute('DROP TABLE IF EXISTS ${table}_downgrade_tmp');
    await db.execute('CREATE TABLE ${table}_downgrade_tmp ($createV004)');
    await db.execute(
      'INSERT INTO ${table}_downgrade_tmp ($cols) SELECT $cols FROM $table',
    );
    await db.execute('DROP TABLE $table');
    await db.execute('ALTER TABLE ${table}_downgrade_tmp RENAME TO $table');
  }
}
