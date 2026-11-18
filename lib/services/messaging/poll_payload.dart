import 'dart:convert';
import 'package:uuid/uuid.dart';

class PollOption {
  final String id;
  final String label;
  const PollOption({required this.id, required this.label});
  Map<String, dynamic> toJson() => {'id': id, 'label': label};
}

class PollDefinition {
  final String id;
  final String question;
  final List<PollOption> options;
  final bool allowMultiple;
  final DateTime? endsAt;
  const PollDefinition({
    required this.id,
    required this.question,
    required this.options,
    required this.allowMultiple,
    this.endsAt,
  });
  bool get isClosed => endsAt != null && !DateTime.now().isBefore(endsAt!);
  Map<String, dynamic> toJson() => {
    'kind': 'definition',
    'pollId': id,
    'question': question,
    'options': options.map((option) => option.toJson()).toList(),
    'allowMultiple': allowMultiple,
    'endsAtMs': endsAt?.millisecondsSinceEpoch,
  };
  String encode() => jsonEncode(toJson());
}

class PollVote {
  final String pollId;
  final List<String> optionIds;
  const PollVote({required this.pollId, required this.optionIds});
  Map<String, dynamic> toJson() => {
    'kind': 'vote',
    'pollId': pollId,
    'optionIds': optionIds,
  };
  String encode() => jsonEncode(toJson());
}

/// Validates poll definitions and vote events before ratchet state advances.
class PollPayload {
  static const maxQuestionLength = 240;
  static const maxOptionLength = 80;
  static const minOptions = 2;
  static const maxOptions = 10;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  static PollDefinition create({
    required String question,
    required List<String> labels,
    required bool allowMultiple,
    DateTime? endsAt,
  }) {
    final normalized =
        labels
            .map((label) => label.trim())
            .where((label) => label.isNotEmpty)
            .toList();
    final poll = PollDefinition(
      id: const Uuid().v4(),
      question: question.trim(),
      options:
          normalized
              .map((label) => PollOption(id: const Uuid().v4(), label: label))
              .toList(),
      allowMultiple: allowMultiple,
      endsAt: endsAt,
    );
    validateDefinition(poll.toJson());
    return poll;
  }

  static PollDefinition decodeDefinition(Map<String, dynamic> value) {
    if (value['kind'] != 'definition' ||
        value['pollId'] is! String ||
        !_uuid.hasMatch(value['pollId'] as String)) {
      throw const FormatException('Invalid poll definition');
    }
    final question = value['question'];
    final rawOptions = value['options'];
    final multiple = value['allowMultiple'];
    final rawEnd = value['endsAtMs'];
    if (question is! String ||
        question.trim().isEmpty ||
        question.length > maxQuestionLength ||
        rawOptions is! List ||
        multiple is! bool ||
        (rawEnd != null &&
            (rawEnd is! int || rawEnd < 0 || rawEnd > 4102444800000))) {
      throw const FormatException('Invalid poll definition');
    }
    final options = <PollOption>[];
    final ids = <String>{};
    for (final raw in rawOptions) {
      if (raw is! Map) throw const FormatException('Invalid poll option');
      final id = raw['id'], label = raw['label'];
      if (id is! String ||
          !_uuid.hasMatch(id) ||
          !ids.add(id) ||
          label is! String ||
          label.trim().isEmpty ||
          label.length > maxOptionLength) {
        throw const FormatException('Invalid poll option');
      }
      options.add(PollOption(id: id, label: label));
    }
    if (options.length < minOptions || options.length > maxOptions) {
      throw const FormatException('Invalid poll options');
    }
    return PollDefinition(
      id: value['pollId'] as String,
      question: question,
      options: options,
      allowMultiple: multiple,
      endsAt:
          rawEnd == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(rawEnd as int),
    );
  }

  static void validateDefinition(Map<String, dynamic> value) =>
      decodeDefinition(value);

  static PollVote decodeVote(
    Map<String, dynamic> value, {
    PollDefinition? definition,
    DateTime? votedAt,
  }) {
    final pollId = value['pollId'], rawOptions = value['optionIds'];
    if (value['kind'] != 'vote' ||
        pollId is! String ||
        !_uuid.hasMatch(pollId) ||
        rawOptions is! List ||
        rawOptions.isEmpty ||
        rawOptions.length > maxOptions) {
      throw const FormatException('Invalid poll vote');
    }
    final options = <String>[];
    for (final option in rawOptions) {
      if (option is! String ||
          !_uuid.hasMatch(option) ||
          options.contains(option)) {
        throw const FormatException('Invalid poll vote');
      }
      options.add(option);
    }
    if (definition != null &&
        (definition.id != pollId ||
            (definition.endsAt != null &&
                !(votedAt ?? DateTime.now()).isBefore(definition.endsAt!)) ||
            (!definition.allowMultiple && options.length != 1) ||
            options.any(
              (id) => !definition.options.any((option) => option.id == id),
            ))) {
      throw const FormatException('Vote does not match this poll');
    }
    return PollVote(pollId: pollId, optionIds: options);
  }
}
