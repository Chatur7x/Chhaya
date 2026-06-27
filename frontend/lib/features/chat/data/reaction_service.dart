import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/models/message_metadata.dart';

final reactionServiceProvider = Provider<ReactionService>((ref) {
  return ReactionService();
});

class ReactionService {
  static const String _boxName = 'message_metadata';
  Box<MessageMetadata>? _box;

  Future<void> initialize() async {
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(MessageReactionAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(MessageMetadataAdapter());
    }
    _box = await Hive.openBox<MessageMetadata>(_boxName);
  }

  Future<void> addReaction(
      String messageId, String emoji, String userId) async {
    if (_box == null) return;

    final metadata = _box!.get(messageId) ?? MessageMetadata();
    final existingIndex = metadata.reactions.indexWhere(
      (r) => r.userId == userId && r.emoji == emoji,
    );

    if (existingIndex == -1) {
      metadata.reactions.add(MessageReaction(emoji: emoji, userId: userId));
    }

    await _box!.put(messageId, metadata);
  }

  Future<void> removeReaction(String messageId, String userId) async {
    if (_box == null) return;

    final metadata = _box!.get(messageId);
    if (metadata == null) return;

    metadata.reactions.removeWhere((r) => r.userId == userId);
    await _box!.put(messageId, metadata);
  }

  Future<void> toggleReaction(
      String messageId, String emoji, String userId) async {
    if (_box == null) return;

    final metadata = _box!.get(messageId) ?? MessageMetadata();
    final existingIndex = metadata.reactions.indexWhere(
      (r) => r.userId == userId && r.emoji == emoji,
    );

    if (existingIndex != -1) {
      metadata.reactions.removeAt(existingIndex);
    } else {
      final otherIndex =
          metadata.reactions.indexWhere((r) => r.userId == userId);
      if (otherIndex != -1) {
        metadata.reactions.removeAt(otherIndex);
      }
      metadata.reactions.add(MessageReaction(emoji: emoji, userId: userId));
    }

    await _box!.put(messageId, metadata);
  }

  MessageMetadata? getMetadata(String messageId) {
    return _box?.get(messageId);
  }

  List<MessageReaction> getReactions(String messageId) {
    return _box?.get(messageId)?.reactions ?? [];
  }
}
