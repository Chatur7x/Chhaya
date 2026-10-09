// Ratchet session persistence (V14 Part 4).
//
// Sessions are stored as AES-GCM field envelopes in the Part 3 kv
// table under `ratchet_session/<peerId>`, via LocalDatabase blob
// methods. [InMemorySessionStorage] covers unit tests without a DB.
import 'dart:convert';

import '../../database/local_database.dart';
import 'session_state.dart';

/// Abstract session persistence (swap implementations without
/// touching ratchet logic).
abstract class SessionStorage {
  Future<void> saveSession(SessionState state);
  Future<SessionState?> loadSession(String peerId);
  Future<void> deleteSession(String peerId);
}

/// Part 3 LocalDatabase backend. Blobs stay AES-GCM enveloped at rest.
class LocalDatabaseSessionStorage implements SessionStorage {
  final LocalDatabase _db;

  LocalDatabaseSessionStorage(this._db);

  @override
  Future<void> saveSession(SessionState state) {
    return _db.saveSessionBlob(state.peerId, jsonEncode(state.toJson()));
  }

  @override
  Future<SessionState?> loadSession(String peerId) async {
    final raw = await _db.loadSessionBlob(peerId);
    if (raw == null) {
      return null;
    }
    try {
      return SessionState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt session: unusable, never partially trusted.
      return null;
    }
  }

  @override
  Future<void> deleteSession(String peerId) {
    return _db.deleteSessionBlob(peerId);
  }
}

/// Volatile backend for unit tests. Never use for real sessions.
class InMemorySessionStorage implements SessionStorage {
  final Map<String, Map<String, dynamic>> _sessions = {};

  @override
  Future<void> saveSession(SessionState state) async {
    _sessions[state.peerId] =
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>;
  }

  @override
  Future<SessionState?> loadSession(String peerId) async {
    final raw = _sessions[peerId];
    if (raw == null) {
      return null;
    }
    return SessionState.fromJson(raw);
  }

  @override
  Future<void> deleteSession(String peerId) async {
    _sessions.remove(peerId);
  }
}
