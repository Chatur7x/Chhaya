// Versioned, transactional migration runner (V14 Part 3).
//
// Purpose: apply schema migrations in order inside transactions, track
// applied versions in `schema_version`, and roll back on failure.
// Migrations are idempotent: DDL uses IF NOT EXISTS and version rows
// use INSERT OR IGNORE, so a re-run after a crash is always safe.
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../schema.dart';

/// A single versioned schema migration.
abstract class Migration {
  /// Schema version this migration produces (1-based, gapless).
  int get version;

  /// Human-readable name for logs (no secrets, no user data).
  String get name;

  /// Applies the migration. Must be idempotent.
  /// Takes [DatabaseExecutor] so the runner can execute inside a
  /// transaction ([Transaction] is not a [Database]).
  Future<void> up(DatabaseExecutor db);

  /// Reverts the migration. Must be idempotent.
  Future<void> down(DatabaseExecutor db);
}

/// Applies registered [Migration]s in version order.
class MigrationRunner {
  /// Creates a runner over an explicit migration list.
  MigrationRunner(List<Migration> migrations)
      : _migrations = List.of(migrations)
          ..sort((a, b) => a.version.compareTo(b.version)) {
    for (var i = 0; i < _migrations.length; i++) {
      if (_migrations[i].version != i + 1) {
        throw ArgumentError(
          'Migration versions must be gapless from 1 '
          '(found ${_migrations[i].version} at position $i)',
        );
      }
    }
  }

  final List<Migration> _migrations;

  /// Highest version this runner knows how to build.
  int get latestVersion => _migrations.length;

  /// Current applied version (0 when the database is fresh).
  Future<int> currentVersion(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${DbTables.schemaVersion} ('
      '${DbCols.version} INTEGER PRIMARY KEY, '
      '${DbCols.appliedAt} INTEGER NOT NULL)',
    );
    final rows = await db.query(
      DbTables.schemaVersion,
      columns: ['MAX(${DbCols.version}) AS v'],
    );
    final v = rows.first['v'];
    if (v == null) {
      return 0;
    }
    return (v as int?) ?? 0;
  }

  /// Migrates up to [latestVersion] inside one transaction.
  Future<void> migrateUp(Database db) => migrateTo(db, latestVersion);

  /// Migrates to exactly [target] (up or down) inside one transaction.
  /// Rolls back everything on failure.
  Future<void> migrateTo(Database db, int target) async {
    if (target < 0 || target > latestVersion) {
      throw ArgumentError.value(target, 'target', 'Out of range');
    }
    await db.transaction((txn) async {
      final current = await _currentVersionTxn(txn);
      if (current == target) {
        return;
      }
      if (current < target) {
        for (var v = current + 1; v <= target; v++) {
          final migration = _migrations[v - 1];
          await migration.up(txn);
          await txn.insert(
            DbTables.schemaVersion,
            {
              DbCols.version: v,
              DbCols.appliedAt: DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      } else {
        for (var v = current; v > target; v--) {
          final migration = _migrations[v - 1];
          await migration.down(txn);
          await txn.delete(
            DbTables.schemaVersion,
            where: '${DbCols.version} = ?',
            whereArgs: [v],
          );
        }
      }
    });
  }

  Future<int> _currentVersionTxn(Transaction txn) async {
    await txn.execute(
      'CREATE TABLE IF NOT EXISTS ${DbTables.schemaVersion} ('
      '${DbCols.version} INTEGER PRIMARY KEY, '
      '${DbCols.appliedAt} INTEGER NOT NULL)',
    );
    final rows = await txn.query(
      DbTables.schemaVersion,
      columns: ['MAX(${DbCols.version}) AS v'],
    );
    final v = rows.first['v'];
    if (v == null) {
      return 0;
    }
    return (v as int?) ?? 0;
  }
}
