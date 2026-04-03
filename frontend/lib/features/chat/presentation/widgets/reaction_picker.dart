import 'package:flutter/material.dart';
import '../../../../core/theme/chaaya_theme.dart';
import '../../domain/models/message_metadata.dart';

class ReactionPicker extends StatelessWidget {
  final Function(String emoji) onReactionSelected;

  const ReactionPicker({
    super.key,
    required this.onReactionSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: ChaayaTheme.glassDecoration(
        borderRadius: 24,
        color: ChaayaTheme.glassWhite,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: availableReactions.map((emoji) {
          return GestureDetector(
            onTap: () => onReactionSelected(emoji),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 22),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class ReactionDisplay extends StatelessWidget {
  final List<MessageReaction> reactions;
  final VoidCallback? onTap;

  const ReactionDisplay({
    super.key,
    required this.reactions,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    final grouped = <String, int>{};
    for (final reaction in reactions) {
      grouped[reaction.emoji] = (grouped[reaction.emoji] ?? 0) + 1;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: ChaayaTheme.glassDecoration(
          borderRadius: 12,
          color: ChaayaTheme.surfaceLight,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: grouped.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(entry.key, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 2),
                  Text(
                    entry.value.toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: ChaayaTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
