import 'package:flutter/material.dart';

class ReactionPicker extends StatelessWidget {
  final Function(String) onReactionSelected;
  const ReactionPicker({super.key, required this.onReactionSelected});

  static const List<String> reactions = ['❤️', '😂', '😮', '😢', '👍', '🔥'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: reactions
            .map((r) => GestureDetector(
                  onTap: () => onReactionSelected(r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(r, style: const TextStyle(fontSize: 24)),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class ReactionDisplay extends StatelessWidget {
  final List<String> reactions;
  const ReactionDisplay({super.key, required this.reactions});

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: reactions
          .map((r) => Text(r, style: const TextStyle(fontSize: 14)))
          .toList(),
    );
  }
}
