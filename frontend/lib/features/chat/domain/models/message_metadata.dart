import 'package:hive/hive.dart';

part 'message_metadata.g.dart';

@HiveType(typeId: 10)
class MessageReaction extends HiveObject {
  @HiveField(0)
  final String emoji;

  @HiveField(1)
  final String userId;

  @HiveField(2)
  final DateTime timestamp;

  MessageReaction({
    required this.emoji,
    required this.userId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

@HiveType(typeId: 11)
class MessageMetadata extends HiveObject {
  @HiveField(0)
  List<MessageReaction> reactions;

  @HiveField(1)
  String? replyToId;

  @HiveField(2)
  String? quotedText;

  @HiveField(3)
  bool edited;

  @HiveField(4)
  DateTime? editedAt;

  MessageMetadata({
    List<MessageReaction>? reactions,
    this.replyToId,
    this.quotedText,
    this.edited = false,
    this.editedAt,
  }) : reactions = reactions ?? [];
}

const List<String> availableReactions = [
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '🔥',
  '👎',
  '🎉',
];
