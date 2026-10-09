import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';

/// ChhayaChatBubble — Sent/received message bubble.
///
/// Sent ([isMine]) uses a coral fill with white text; received uses a
/// white fill with ink text and a [ChhayaColors.borderMed] hairline.
/// Capped at ~75% of the screen width and aligned to the message side.
class ChhayaChatBubble extends StatelessWidget {
  final String message;
  final bool isMine;
  final String? timestamp;
  final bool verified;

  const ChhayaChatBubble({
    super.key,
    required this.message,
    this.isMine = false,
    this.timestamp,
    this.verified = false,
  });

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.75;
    final fill = isMine ? ChhayaColors.coral : ChhayaColors.white;
    final textColor = isMine ? ChhayaColors.white : ChhayaColors.ink;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ChhayaSpacing.space4,
            vertical: ChhayaSpacing.space3,
          ),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(ChhayaRadius.lg),
            border: isMine
                ? null
                : Border.all(color: ChhayaColors.borderMed, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: ChhayaTypography.body.copyWith(color: textColor),
              ),
              if (timestamp != null || verified) ...[
                const SizedBox(height: ChhayaSpacing.space1),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (timestamp != null)
                      Text(timestamp!, style: ChhayaTypography.caption),
                    if (verified) ...[
                      if (timestamp != null)
                        const SizedBox(width: ChhayaSpacing.space1),
                      Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: ChhayaColors.coralDeep,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 9,
                          color: ChhayaColors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
