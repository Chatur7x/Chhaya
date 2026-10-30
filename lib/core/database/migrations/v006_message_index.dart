import 'package:sqflite_sqlcipher/sqflite.dart';
import '../schema.dart';
import 'migration_runner.dart';

class MigrationV006MessageIndex extends Migration {
  @override
  int get version => 6;
  @override
  String get name => 'message synchronization index';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${DbTables.messageIndex} ('
      'id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, sent_at INTEGER NOT NULL, '
      'expires_at INTEGER, is_sent INTEGER NOT NULL, valid INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS message_sync_conversation '
      'ON ${DbTables.messageIndex} (conversation_id, sent_at, id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS message_sync_pending '
      'ON ${DbTables.messageIndex} (conversation_id, is_sent)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS message_sync_expiry '
      'ON ${DbTables.messageIndex} (conversation_id, expires_at)',
    );
  }

  @override
  Future<void> down(DatabaseExecutor db) async {
    // This index is rebuildable; encrypted message rows remain untouched.
    await db.execute('DROP TABLE IF EXISTS ${DbTables.messageIndex}');
  }
}
