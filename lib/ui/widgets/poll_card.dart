import 'package:flutter/material.dart';
import '../../services/messaging/poll_payload.dart';
import '../theme/chhaya_theme.dart';

class PollCard extends StatefulWidget {
  final PollDefinition poll;
  final Map<String, int> totals;
  final int totalVotes;
  final List<String> selectedOptions;
  final bool canVote;
  final ValueChanged<List<String>> onVote;
  const PollCard({
    super.key,
    required this.poll,
    required this.totals,
    required this.totalVotes,
    required this.selectedOptions,
    required this.canVote,
    required this.onVote,
  });

  @override
  State<PollCard> createState() => _PollCardState();
}

class PollComposerSheet extends StatefulWidget {
  const PollComposerSheet({super.key});
  @override
  State<PollComposerSheet> createState() => _PollComposerSheetState();
}

class _PollComposerSheetState extends State<PollComposerSheet> {
  final _question = TextEditingController();
  final _options = [TextEditingController(), TextEditingController()];
  bool _multiple = false;
  int _expiryHours = 0;
  @override
  void dispose() {
    _question.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_options.length < PollPayload.maxOptions) {
      setState(() => _options.add(TextEditingController()));
    }
  }

  void _removeOption(int index) {
    if (_options.length > PollPayload.minOptions) {
      setState(() => _options.removeAt(index).dispose());
    }
  }

  void _create() {
    try {
      final end =
          _expiryHours == 0
              ? null
              : DateTime.now().add(Duration(hours: _expiryHours));
      final poll = PollPayload.create(
        question: _question.text,
        labels: _options.map((e) => e.text).toList(),
        allowMultiple: _multiple,
        endsAt: end,
      );
      Navigator.of(context).pop(poll);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a question and at least two non-empty choices.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ChhayaPalette.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create a poll',
                style: ChhayaType.of(
                  context,
                ).displaySmall.copyWith(fontSize: 22),
              ),
              const SizedBox(height: 8),
              Text(
                'Votes are end-to-end encrypted with this conversation.',
                style: ChhayaType.of(context).caption,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _question,
                maxLength: PollPayload.maxQuestionLength,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Question',
                  hintText: 'Where should we meet?',
                ),
              ),
              const SizedBox(height: 8),
              ...List.generate(
                _options.length,
                (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _options[index],
                          maxLength: PollPayload.maxOptionLength,
                          decoration: InputDecoration(
                            labelText: 'Option ${index + 1}',
                            counterText: '',
                          ),
                        ),
                      ),
                      if (_options.length > PollPayload.minOptions)
                        IconButton(
                          tooltip: 'Remove option',
                          onPressed: () => _removeOption(index),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                    ],
                  ),
                ),
              ),
              TextButton.icon(
                onPressed:
                    _options.length < PollPayload.maxOptions
                        ? _addOption
                        : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add option'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow multiple choices'),
                value: _multiple,
                onChanged: (value) => setState(() => _multiple = value),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Close poll after',
                      style: ChhayaType.of(context).bodyMedium,
                    ),
                  ),
                  DropdownButton<int>(
                    value: _expiryHours,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Never')),
                      DropdownMenuItem(value: 1, child: Text('1 hour')),
                      DropdownMenuItem(value: 24, child: Text('1 day')),
                      DropdownMenuItem(value: 168, child: Text('7 days')),
                    ],
                    onChanged:
                        (value) => setState(() => _expiryHours = value ?? 0),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                  ),
                  onPressed: _question.text.trim().isNotEmpty ? _create : null,
                  icon: const Icon(Icons.poll_outlined),
                  label: const Text('Send poll'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PollCardState extends State<PollCard> {
  late Set<String> _selected = widget.selectedOptions.toSet();
  @override
  void didUpdateWidget(covariant PollCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.poll.id != widget.poll.id ||
        oldWidget.selectedOptions != widget.selectedOptions) {
      _selected = widget.selectedOptions.toSet();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ChhayaPalette.of(context);
    final showResults = widget.totalVotes > 0 || !widget.canVote;
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardSurface.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.poll_outlined, size: 18, color: colors.accent),
              const SizedBox(width: 7),
              Text(
                'POLL',
                style: ChhayaType.of(
                  context,
                ).labelSmall.copyWith(color: colors.accent, letterSpacing: 1),
              ),
              const Spacer(),
              Text(
                '${widget.totalVotes} vote${widget.totalVotes == 1 ? '' : 's'}',
                style: ChhayaType.of(context).caption,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            widget.poll.question,
            style: ChhayaType.of(
              context,
            ).bodyLarge.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...widget.poll.options.map((option) {
            final count = widget.totals[option.id] ?? 0;
            final percent =
                widget.totalVotes == 0 ? 0.0 : count / widget.totalVotes;
            final chosen = _selected.contains(option.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: colors.surface.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(11),
                child: InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap:
                      widget.canVote
                          ? () => setState(() {
                            if (widget.poll.allowMultiple) {
                              if (!_selected.add(option.id)) {
                                _selected.remove(option.id);
                              }
                            } else {
                              _selected = {option.id};
                            }
                          })
                          : null,
                  child: Stack(
                    children: [
                      if (showResults)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: SizedBox(
                              height: 42,
                              child: LinearProgressIndicator(
                                value: percent,
                                backgroundColor: colors.surface,
                                color: colors.accent.withValues(alpha: .17),
                              ),
                            ),
                          ),
                        ),
                      Container(
                        constraints: const BoxConstraints(minHeight: 42),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: chosen ? colors.accent : colors.separator,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              widget.poll.allowMultiple
                                  ? (chosen
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded)
                                  : (chosen
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_unchecked_rounded),
                              size: 18,
                              color:
                                  chosen ? colors.accent : colors.labelTertiary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                option.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: ChhayaType.of(context).bodyMedium,
                              ),
                            ),
                            if (showResults)
                              Text(
                                '${(percent * 100).round()}%  $count',
                                style: ChhayaType.of(context).caption,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (widget.poll.allowMultiple)
            Padding(
              padding: const EdgeInsets.only(top: 1, bottom: 6),
              child: Text(
                'Select all that apply',
                style: ChhayaType.of(context).caption,
              ),
            ),
          if (widget.canVote)
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed:
                    _selected.isEmpty
                        ? null
                        : () => widget.onVote(_selected.toList()),
                child: Text(
                  widget.selectedOptions.isEmpty ? 'Vote' : 'Update vote',
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                widget.poll.isClosed ? 'Poll closed' : 'Voting unavailable',
                style: ChhayaType.of(context).caption,
              ),
            ),
        ],
      ),
    );
  }
}
