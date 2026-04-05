import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/chaaya_theme.dart';

class ScheduleMessageSheet extends ConsumerStatefulWidget {
  final String chatId;
  final String messageText;
  final Function(DateTime) onSchedule;

  const ScheduleMessageSheet({
    super.key,
    required this.chatId,
    required this.messageText,
    required this.onSchedule,
  });

  @override
  ConsumerState<ScheduleMessageSheet> createState() =>
      _ScheduleMessageSheetState();
}

class _ScheduleMessageSheetState extends ConsumerState<ScheduleMessageSheet> {
  DateTime _scheduledDate = DateTime.now().add(const Duration(hours: 1));
  TimeOfDay _scheduledTime = TimeOfDay.now();

  void _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _scheduledDate = date);
    }
  }

  void _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _scheduledTime,
    );
    if (time != null) {
      setState(() => _scheduledTime = time);
    }
  }

  void _schedule() {
    final scheduledAt = DateTime(
      _scheduledDate.year,
      _scheduledDate.month,
      _scheduledDate.day,
      _scheduledTime.hour,
      _scheduledTime.minute,
    );

    final scheduleService = ref.read(scheduleServiceProvider);
    scheduleService.scheduleMessage(
      chatId: widget.chatId,
      content: widget.messageText,
      scheduledAt: scheduledAt,
    );

    widget.onSchedule(scheduledAt);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ChaayaTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Schedule Message',
            style: TextStyle(
              color: ChaayaTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.messageText.length > 50
                ? '${widget.messageText.substring(0, 50)}...'
                : widget.messageText,
            style: const TextStyle(color: ChaayaTheme.textMuted),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildOption(
                  icon: Icons.calendar_today,
                  label: 'Date',
                  value:
                      '${_scheduledDate.day}/${_scheduledDate.month}/${_scheduledDate.year}',
                  onTap: _selectDate,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildOption(
                  icon: Icons.access_time,
                  label: 'Time',
                  value: _scheduledTime.format(context),
                  onTap: _selectTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel',
                      style: TextStyle(color: ChaayaTheme.textMuted)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _schedule,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ChaayaTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Schedule'),
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ChaayaTheme.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ChaayaTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: ChaayaTheme.accent),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(
                        color: ChaayaTheme.textMuted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    color: ChaayaTheme.textPrimary,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
