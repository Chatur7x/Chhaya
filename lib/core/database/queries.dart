// Parameterized query helpers (V14 Part 3).
//
// Purpose: the ONLY way to build SQL in this codebase. Table and column
// identifiers are validated against a strict pattern (identifiers can
// never be bound parameters in SQLite); every VALUE is bound via
// whereArgs — never interpolated. Any caller passing hostile strings
// gets them treated as data, and invalid identifiers throw.
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Sort directive with a validated column name.
class DbOrder {
  /// Creates a sort on [column], ascending unless [descending].
  const DbOrder(this.column, {this.descending = false});

  /// Column to sort by (validated on use).
  final String column;

  /// True for DESC, false for ASC.
  final bool descending;
}

/// Query builders. All values bound; identifiers validated.
class DbQueries {
  DbQueries._();

  static final RegExp _identifier = RegExp(r'^[a-z][a-z0-9_]*$');

  /// Validates a table or column identifier. Throws on mismatch.
  static void checkIdentifier(String identifier) {
    if (!_identifier.hasMatch(identifier)) {
      throw ArgumentError.value(
        identifier,
        'identifier',
        'Only lowercase letters, digits, and underscore allowed',
      );
    }
  }

  /// Inserts or replaces [row]. Keys and table validated; values bound.
  static Future<void> upsert(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> row,
  ) async {
    checkIdentifier(table);
    for (final column in row.keys) {
      checkIdentifier(column);
    }
    await db.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Selects rows matching all [equals] filters (AND-combined).
  static Future<List<Map<String, Object?>>> find(
    DatabaseExecutor db,
    String table, {
    Map<String, Object?> equals = const {},
    List<DbOrder> orderBy = const [],
    int? limit,
  }) async {
    checkIdentifier(table);
    String? where;
    List<Object?>? whereArgs;
    if (equals.isNotEmpty) {
      final clauses = <String>[];
      final args = <Object?>[];
      equals.forEach((column, value) {
        checkIdentifier(column);
        clauses.add('$column = ?');
        args.add(value);
      });
      where = clauses.join(' AND ');
      whereArgs = args;
    }
    String? orderClause;
    if (orderBy.isNotEmpty) {
      orderClause = orderBy.map((order) {
        checkIdentifier(order.column);
        return '${order.column} ${order.descending ? 'DESC' : 'ASC'}';
      }).join(', ');
    }
    return db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderClause,
      limit: limit,
    );
  }

  /// Deletes rows matching all [equals] filters. Returns deleted count.
  static Future<int> deleteWhere(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> equals,
  ) async {
    checkIdentifier(table);
    if (equals.isEmpty) {
      throw ArgumentError.value(
        equals,
        'equals',
        'Refusing unfiltered delete',
      );
    }
    final clauses = <String>[];
    final args = <Object?>[];
    equals.forEach((column, value) {
      checkIdentifier(column);
      clauses.add('$column = ?');
      args.add(value);
    });
    return db.delete(
      table,
      where: clauses.join(' AND '),
      whereArgs: args,
    );
  }

  /// Counts rows matching all [equals] filters.
  static Future<int> countWhere(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> equals,
  ) async {
    final rows = await find(db, table, equals: equals);
    return rows.length;
  }
}
