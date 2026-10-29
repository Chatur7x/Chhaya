import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../../core/models/message_attachment.dart';
import '../theme/chhaya_theme.dart';
import 'audio_level_waveform.dart';

/// User-started AAC capture remains bounded in memory until encrypted staging.
class VoiceRecorderSheet extends StatefulWidget {
  const VoiceRecorderSheet({super.key});
  @override
  State<VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<VoiceRecorderSheet>
    with WidgetsBindingObserver {
  final _recorder = AudioRecorder();
  Future<void> _starting = Future.value();
  final _audio = BytesBuilder(copy: true);
  StreamSubscription<Uint8List>? _audioSubscription;
  bool _tooLarge = false;
  bool _streamFailed = false;
  Timer? _timer;
  StreamSubscription<Amplitude>? _meter;
  final _levels = <double>[];
  bool _recording = false, _busy = false, _closing = false;
  int _seconds = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stop(false);
    }
  }

  Future<void> _start() async {
    if (_busy || _recording || _closing) return;
    final discarded = _audio.takeBytes();
    discarded.fillRange(0, discarded.length, 0);
    _tooLarge = false;
    _streamFailed = false;
    setState(() {
      _busy = true;
      _error = null;
    });
    _starting = _beginRecording();
    await _starting;
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _beginRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        throw StateError('Microphone permission is required.');
      }
      if (!mounted || _closing) return;
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 24000,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _audioSubscription = stream.listen(
        (chunk) {
          if (_audio.length + chunk.length > MessageAttachment.maxBytes) {
            _tooLarge = true;
            unawaited(_stop(false));
          } else if (!_tooLarge) {
            _audio.add(chunk);
          }
        },
        onError: (_) {
          _streamFailed = true;
          unawaited(_stop(false));
        },
      );
      _meter = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((event) {
            if (!mounted || _closing || !event.current.isFinite) return;
            setState(() {
              _levels.add(
                ((event.current + 120) / 120).clamp(0.0, 1.0).toDouble(),
              );
              if (_levels.length > 32) _levels.removeAt(0);
            });
          });
      if (!mounted || _closing) return;
      setState(() => _recording = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _closing) return;
        setState(() => _seconds++);
        if (_seconds >= 60) _stop(true);
      });
    } catch (_) {
      await _cleanup();
      if (mounted) {
        setState(
          () =>
              _error =
                  'Could not record. Check microphone permission and try again.',
        );
      }
    }
  }

  Future<void> _cleanup() async {
    _timer?.cancel();
    await _meter?.cancel();
    _meter = null;
    try {
      await _recorder.cancel();
    } catch (_) {
      /* Already stopped. */
    }
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    final discarded = _audio.takeBytes();
    discarded.fillRange(0, discarded.length, 0);
  }

  Future<void> _stop(bool keep) async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (mounted) setState(() => _busy = true);
    MessageAttachment? attachment;
    try {
      await _starting;
      if (await _recorder.isRecording()) await _recorder.stop();
      if (keep && !_tooLarge) {
        final bytes = _audio.takeBytes();
        try {
          attachment = MessageAttachment.fromBytes(
            name: 'Voice message.aac',
            mimeType: 'audio/aac',
            bytes: bytes,
          );
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Recording could not be attached. Try a shorter recording.',
            ),
          ),
        );
      }
    } finally {
      await _cleanup();
      await _recorder.dispose();
    }
    if (_tooLarge && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recording exceeds the attachment limit. Try a shorter recording.',
          ),
        ),
      );
    }
    if (_streamFailed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recording interrupted. Please try again.'),
        ),
      );
    }
    if (mounted) Navigator.pop(context, attachment);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if (!_closing) {
      _closing = true;
      unawaited(
        _starting.whenComplete(() async {
          await _cleanup();
          await _recorder.dispose();
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Voice message', style: ChhayaType.of(context).headline),
          const SizedBox(height: 16),
          Text(
            _recording
                ? 'Recording · ${_seconds}s / 60s'
                : 'Record up to one minute. Review the attachment before sending.',
            textAlign: TextAlign.center,
            style: ChhayaType.of(context).bodyLarge,
          ),
          const SizedBox(height: 12),
          AudioLevelWaveform(levels: List.unmodifiable(_levels)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: _closing ? null : () => _stop(false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed:
                    _busy
                        ? null
                        : _recording
                        ? () => _stop(true)
                        : _start,
                icon: AnimatedSwitcher(
                  duration: ChhayaMotion.duration(context, 180),
                  child: Icon(
                    _recording ? Icons.stop_rounded : Icons.mic_rounded,
                    key: ValueKey(_recording),
                  ),
                ),
                label: Text(_recording ? 'Use recording' : 'Start recording'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
