import 'package:flutter/material.dart';
import '../../../../core/theme/chaaya_theme.dart';

class ReplyQuoteCard extends StatelessWidget {
  final String senderName;
  final String quotedText;
  final VoidCallback onCancel;

  const ReplyQuoteCard({
    super.key,
    required this.senderName,
    required this.quotedText,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 4),
      padding: const EdgeInsets.only(left: 12, right: 4, top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: ChaayaTheme.surfaceLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: ChaayaTheme.accent,
            width: 3,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  senderName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ChaayaTheme.accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  quotedText.length > 100
                      ? '${quotedText.substring(0, 100)}...'
                      : quotedText,
                  style: const TextStyle(
                    fontSize: 13,
                    color: ChaayaTheme.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(
              Icons.close,
              size: 18,
              color: ChaayaTheme.textMuted,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
