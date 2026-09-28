// Migration v003 — linked devices (V14 Part 3).
//
// Purpose: multi-device records. Push tokens are always stored
// encrypted (`fcm_token_encrypted`) — never plaintext, never indexed.
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../schema.dart';
import 'migration_runner.dart';

/// v003: devices + owner index.
class MigrationV003Devices extends Migration {
  @override
  int get version => 3;

  @override
  String get name => 'devices';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${DbTables.devices} ('
      '${DbCols.id} TEXT PRIMARY KEY, '
      '${DbCols.userId} TEXT NOT NULL, '
      '${DbCols.deviceName} TEXT NOT NULL, '
      '${DbCols.platform} TEXT NOT NULL, '
      '${DbCols.fcmTokenEncrypted} TEXT, '
      '${DbCols.publicKey} TEXT NOT NULL, '
      '${DbCols.isLinked} INTEGER NOT NULL DEFAULT 0, '
      '${DbCols.lastActiveAt} INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ${DbIndices.devicesByUser} '
      'ON ${DbTables.devices} (${DbCols.userId})',
    );
  }

  @override
  Future<void> down(DatabaseExecutor db) async {
    await db.execute('DROP INDEX IF EXISTS ${DbIndices.devicesByUser}');
    await db.execute('DROP TABLE IF EXISTS ${DbTables.devices}');
  }
}
