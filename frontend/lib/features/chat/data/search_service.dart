import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../core/mesh/mesh_message.dart';

/// Search Service (Req 16).
/// Full-text search across stored message plaintexts.
/// In-memory inverted index for ≤500ms response on up to 100k messages.
class SearchService {
  static const String _indexBox = 'chaaya_search_index';

  // In-memory inverted index: token → Set of messageIds
  final Map<String, Set<String>> _index = {};

  // Message cache for result retrieval
  final Map<String, SearchableMessage> _messages = {};

  Future<void> initialize(List<MeshMessage> existingMessages) async {
    await Hive.openBox<String>(_indexBox); // open for persistence (not used in-memory)
    // Build index from all existing messages
    for (final msg in existingMessages) {
      if (msg.type == MeshMessageType.text || msg.type == MeshMessageType.audio) {
        _indexMessage(msg);
      }
    }
    debugPrint('[Search] Indexed ${_messages.length} messages');
  }

  /// Index a new message (Req 16.5 — within 1s of storage)
  void indexNewMessage(MeshMessage message) {
    _indexMessage(message);
  }

  /// Search messages (Req 16.2 — returns within 500ms for 100k messages)
  List<SearchResult> search(
    String query, {
    String? senderPublicKey,
    DateTime? from,
    DateTime? to,
    MeshMessageType? type,
  }) {
    if (query.trim().isEmpty) return [];

    final tokens = _tokenize(query);
    if (tokens.isEmpty) return [];

    // Find messages matching all tokens (AND logic)
    Set<String>? candidates;
    for (final token in tokens) {
      final matches = _index[token] ?? const {};
      candidates = candidates == null ? matches.toSet() : (candidates.intersection(matches));
    }

    if (candidates == null || candidates.isEmpty) return [];

    // Apply filters + score by relevance
    final results = <SearchResult>[];
    for (final msgId in candidates) {
      final msg = _messages[msgId];
      if (msg == null) continue;

      // Filter: sender
      if (senderPublicKey != null && msg.senderId != senderPublicKey) continue;

      // Filter: date range
      if (from != null && msg.timestamp.isBefore(from)) continue;
      if (to != null && msg.timestamp.isAfter(to)) continue;

      // Filter: message type
      if (type != null && msg.type != type) continue;

      // Score: count matching tokens
      final msgTokens = _tokenize(msg.plaintext);
      int score = 0;
      for (final t in tokens) {
        score += msgTokens.where((mt) => mt == t).length;
      }

      results.add(SearchResult(
        message: msg,
        score: score,
        highlightedText: _highlight(msg.plaintext, tokens),
      ));
    }

    // Sort by relevance (Req 16.2)
    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  void _indexMessage(MeshMessage msg) {
    final plaintext = msg.content; // plaintext before encryption (or decrypted)
    final searchable = SearchableMessage(
      id: msg.id,
      senderId: msg.senderId,
      recipientId: msg.recipientId,
      plaintext: plaintext,
      timestamp: msg.timestamp,
      type: msg.type,
      conversationId: _convId(msg.senderId, msg.recipientId),
    );

    _messages[msg.id] = searchable;

    for (final token in _tokenize(plaintext)) {
      _index.putIfAbsent(token, () => {}).add(msg.id);
    }
  }

  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 2)
        .toList();
  }

  String _highlight(String text, List<String> tokens) {
    // Mark matching tokens with **bold** markers for UI
    var result = text;
    for (final token in tokens) {
      result = result.replaceAllMapped(
        RegExp('($token)', caseSensitive: false),
        (m) => '**${m.group(1)}**',
      );
    }
    return result;
  }

  String _convId(String id1, String id2) {
    final sorted = [id1, id2]..sort();
    return sorted.join('_');
  }

  /// Remove a message from the index (e.g. on delete)
  void removeFromIndex(String messageId) {
    _messages.remove(messageId);
    for (final ids in _index.values) {
      ids.remove(messageId);
    }
  }

  void clear() {
    _index.clear();
    _messages.clear();
  }
}

class SearchableMessage {
  final String id;
  final String senderId;
  final String recipientId;
  final String plaintext;
  final DateTime timestamp;
  final MeshMessageType type;
  final String conversationId;

  SearchableMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.plaintext,
    required this.timestamp,
    required this.type,
    required this.conversationId,
  });
}

class SearchResult {
  final SearchableMessage message;
  final int score;
  final String highlightedText;

  SearchResult({
    required this.message,
    required this.score,
    required this.highlightedText,
  });
}
