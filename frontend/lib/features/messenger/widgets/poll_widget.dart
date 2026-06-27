import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../domain/models/poll.dart';
import '../data/poll_service.dart';

class PollWidget extends ConsumerStatefulWidget {
  final Poll poll;
  final String currentUserId;
  final Function(Poll updatedPoll)? onPollUpdated;

  const PollWidget({
    super.key,
    required this.poll,
    required this.currentUserId,
    this.onPollUpdated,
  });

  @override
  ConsumerState<PollWidget> createState() => _PollWidgetState();
}

class _PollWidgetState extends ConsumerState<PollWidget> {
  late Poll _poll;

  @override
  void initState() {
    super.initState();
    _poll = widget.poll;
  }

  void _handleVote(String optionId) async {
    final service = ref.read(pollServiceProvider);

    if (_poll.hasVotedFor(widget.currentUserId, optionId)) {
      await service.removeVote(_poll.id, optionId, widget.currentUserId);
    } else {
      await service.vote(_poll.id, optionId, widget.currentUserId);
    }

    final updatedPoll = service.getPoll(_poll.id);
    if (updatedPoll != null) {
      setState(() => _poll = updatedPoll);
      widget.onPollUpdated?.call(updatedPoll);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVoted = _poll.hasVoted(widget.currentUserId);
    final isExpired = _poll.isExpired;
    final totalVotes = _poll.totalVotes;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: ChaayaTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ChaayaTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: ChaayaTheme.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.poll_outlined,
                    color: ChaayaTheme.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _poll.question,
                        style: ChaayaTheme.heading3.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (_poll.isAnonymous)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color:
                                    ChaayaTheme.warningYellow.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Anonymous',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: ChaayaTheme.warningYellow,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          if (_poll.allowsMultiple)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: ChaayaTheme.accent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Multi-vote',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: ChaayaTheme.accent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Options
          ..._poll.options
              .map((option) => _buildOptionItem(option, hasVoted, isExpired)),

          // Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                  top: BorderSide(color: ChaayaTheme.glassBorder, width: 0.5)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.people_outline,
                  size: 14,
                  color: ChaayaTheme.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  '$totalVotes vote${totalVotes == 1 ? '' : 's'}',
                  style: ChaayaTheme.bodySmall,
                ),
                const SizedBox(width: 16),
                Icon(
                  isExpired ? Icons.timer_off : Icons.timer_outlined,
                  size: 14,
                  color: isExpired ? ChaayaTheme.sosRed : ChaayaTheme.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  isExpired ? 'Ended' : _getTimeRemaining(),
                  style: ChaayaTheme.bodySmall.copyWith(
                    color: isExpired ? ChaayaTheme.sosRed : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionItem(PollOption option, bool hasVoted, bool isExpired) {
    final isSelected = _poll.hasVotedFor(widget.currentUserId, option.id);
    final voteCount = _poll.getOptionVoteCount(option.id);
    final percentage = _poll.getOptionPercentage(option.id);

    return InkWell(
      onTap: isExpired ? null : () => _handleVote(option.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Selection indicator
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? ChaayaTheme.accent : Colors.transparent,
                border: Border.all(
                  color:
                      isSelected ? ChaayaTheme.accent : ChaayaTheme.textMuted,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            // Option text and progress
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.text,
                    style: ChaayaTheme.bodyLarge.copyWith(
                      color: isSelected
                          ? ChaayaTheme.textPrimary
                          : ChaayaTheme.textSecondary,
                    ),
                  ),
                  if (hasVoted && !_poll.isAnonymous) ...[
                    const SizedBox(height: 6),
                    Stack(
                      children: [
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: ChaayaTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: 6,
                          width: (percentage / 100) *
                              (MediaQuery.of(context).size.width - 120),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? ChaayaTheme.accent
                                : ChaayaTheme.textMuted,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Vote count / percentage
            if (hasVoted && !_poll.isAnonymous) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 50,
                child: Text(
                  '${percentage.toStringAsFixed(0)}%',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? ChaayaTheme.accent
                        : ChaayaTheme.textSecondary,
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(width: 12),
              Text(
                '$voteCount',
                style: ChaayaTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getTimeRemaining() {
    final remaining = _poll.expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Ended';

    if (remaining.inDays > 0) {
      return '${remaining.inDays}d left';
    } else if (remaining.inHours > 0) {
      return '${remaining.inHours}h left';
    } else if (remaining.inMinutes > 0) {
      return '${remaining.inMinutes}m left';
    } else {
      return 'Ending soon';
    }
  }
}
