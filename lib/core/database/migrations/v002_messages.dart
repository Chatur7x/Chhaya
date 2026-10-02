// Migration v002 — conversations, participants, messages (V14 Part 3).
//
// Purpose: conversation headers, membership history, and the message
// store. Message text lives only in `encrypted_content`; the index
// covers (conversation_id, sent_at) routing metadata.
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../schema.dart';
import 'migration_runner.dart';

/// v002: conversations, participants, messages + indices.
class MigrationV002Messages extends Migration {
  @override
  int get version => 2;

  @override
  String get name => 'conversations/participants/messages';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${DbTables.conversations} ('
      '${DbCols.id} TEXT PRIMARY KEY, '
      '${DbCols.type} TEXT NOT NULL, '
      '${DbCols.nameEnc} TEXT, '
      '${DbCols.avatarBlob} BLOB, '
      '${DbCols.createdBy} TEXT NOT NULL, '
      '${DbCols.createdAt} INTEGER NOT NULL, '
      '${DbCols.pinned} INTEGER NOT NULL DEFAULT 0, '
      '${DbCols.lastTs} INTEGER NOT NULL DEFAULT 0)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${DbTables.participants} ('
      '${DbCols.conversationId} TEXT NOT NULL, '
      '${DbCols.userId} TEXT NOT NULL, '
      '${DbCols.joinedAt} INTEGER NOT NULL, '
      '${DbCols.leftAt} INTEGER, '
      '${DbCols.isAdmin} INTEGER NOT NULL DEFAULT 0, '
      'PRIMARY KEY (${DbCols.conversationId}, ${DbCols.userId}))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${DbTables.messages} ('
      '${DbCols.id} TEXT PRIMARY KEY, '
      '${DbCols.conversationId} TEXT NOT NULL, '
      '${DbCols.senderId} TEXT NOT NULL, '
      '${DbCols.encryptedContent} TEXT NOT NULL, '
      '${DbCols.contentType} TEXT NOT NULL DEFAULT \'text\', '
      '${DbCols.mediaBlob} BLOB, '
      '${DbCols.mediaMetaEnc} TEXT, '
      '${DbCols.replyToId} TEXT, '
      '${DbCols.sentAt} INTEGER NOT NULL, '
      '${DbCols.deliveredAt} INTEGER, '
      '${DbCols.readAt} INTEGER)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ${DbIndices.messagesByConversation} '
      'ON ${DbTables.messages} (${DbCols.conversationId}, ${DbCols.sentAt})',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ${DbIndices.participantsByUser} '
      'ON ${DbTables.participants} (${DbCols.userId})',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ${DbIndices.conversationsOrder} '
      'ON ${DbTables.conversations} (${DbCols.pinned}, ${DbCols.lastTs})',
    );
  }

  @override
  Future<void> down(DatabaseExecutor db) async {
    await db.execute(
        'DROP INDEX IF EXISTS ${DbIndices.conversationsOrder}');
    await db.execute(
        'DROP INDEX IF EXISTS ${DbIndices.participantsByUser}');
    await db.execute(
        'DROP INDEX IF EXISTS ${DbIndices.messagesByConversation}');
    await db.execute('DROP TABLE IF EXISTS ${DbTables.messages}');
    await db.execute('DROP TABLE IF EXISTS ${DbTables.participants}');
    await db.execute('DROP TABLE IF EXISTS ${DbTables.conversations}');
  }
}
