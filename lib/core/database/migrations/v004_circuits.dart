// Migration v004 — onion circuit cache (V14 Part 3).
//
// Purpose: persist onion circuits across restarts so a fresh circuit
// build is not required on every launch. Paths are encrypted; expiry
// is routing metadata and stays queryable for eviction.
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../schema.dart';
import 'migration_runner.dart';

/// v004: onion circuit cache.
class MigrationV004Circuits extends Migration {
  @override
  int get version => 4;

  @override
  String get name => 'onion circuit cache';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${DbTables.circuits} ('
      '${DbCols.id} TEXT PRIMARY KEY, '
      '${DbCols.pathEnc} TEXT NOT NULL, '
      '${DbCols.createdAt} INTEGER NOT NULL, '
      '${DbCols.expiresAt} INTEGER NOT NULL)',
    );
  }

  @override
  Future<void> down(DatabaseExecutor db) async {
    await db.execute('DROP TABLE IF EXISTS ${DbTables.circuits}');
  }
}
