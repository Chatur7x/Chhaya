import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';

class VoiceMessageRecorder extends ConsumerStatefulWidget {
  final Function(String base64Audio, int durationSeconds) onVoiceMessageSent;
  const VoiceMessageRecorder({super.key, required this.onVoiceMessageSent});

  @override
  ConsumerState<VoiceMessageRecorder> createState() =>
      _VoiceMessageRecorderState();
}

class _VoiceMessageRecorderState extends ConsumerState<VoiceMessageRecorder> {
  bool _isRecording = false;
  int _recordingDuration = 0;
  Timer? _timer;

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _recordingDuration = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recordingDuration++);
      if (_recordingDuration >= 120) {
        _stopRecording();
      }
    });
  }

  void _stopRecording() {
    _timer?.cancel();
    widget.onVoiceMessageSent('', _recordingDuration);
    setState(() {
      _isRecording = false;
      _recordingDuration = 0;
    });
  }

  void _cancelRecording() {
    _timer?.cancel();
    setState(() {
      _isRecording = false;
      _recordingDuration = 0;
    });
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isRecording) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: ChaayaTheme.surface,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.delete, color: ChaayaTheme.sosRed),
            onPressed: _cancelRecording,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: ChaayaTheme.sosRed.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.mic, color: ChaayaTheme.sosRed, size: 20),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(_recordingDuration),
                  style: const TextStyle(
                      color: ChaayaTheme.textPrimary,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _stopRecording,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: ChaayaTheme.sosRed,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class AttachmentPicker extends StatelessWidget {
  final VoidCallback onPickImage;
  final VoidCallback onPickFile;
  final VoidCallback onPickVoice;
  const AttachmentPicker({
    super.key,
    required this.onPickImage,
    required this.onPickFile,
    required this.onPickVoice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: ChaayaTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildOption(
                icon: Icons.image,
                label: 'Image',
                color: Colors.purple,
                onTap: onPickImage,
              ),
              _buildOption(
                icon: Icons.insert_drive_file,
                label: 'File',
                color: Colors.blue,
                onTap: onPickFile,
              ),
              _buildOption(
                icon: Icons.mic,
                label: 'Voice',
                color: ChaayaTheme.sosRed,
                onTap: onPickVoice,
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  color: ChaayaTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
