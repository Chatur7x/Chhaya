import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/message_attachment.dart';
import '../../services/messaging/attachment_service.dart';
import '../theme/chhaya_theme.dart';
import 'audio_level_waveform.dart';

/// User-started, bounded AAC capture. The temporary recording is deleted after
/// staging/cancel; only its encrypted message representation is persisted.
class VoiceRecorderSheet extends StatefulWidget {
  const VoiceRecorderSheet({super.key});
  @override
  State<VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<VoiceRecorderSheet> with WidgetsBindingObserver {
  final _recorder = FlutterSoundRecorder();
  Future<void> _starting = Future.value();
  File? _file;
  Timer? _timer;
  StreamSubscription<RecordingDisposition>? _meter;
  final _levels = <double>[];
  bool _opened = false, _recording = false, _busy = false, _closing = false;
  int _seconds = 0;
  String? _error;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _stop(false);
    }
  }

  Future<void> _start() async {
    if (_busy || _recording || _closing) return;
    setState(() { _busy = true; _error = null; });
    _starting = _beginRecording();
    await _starting;
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _beginRecording() async {
    try {
      final granted = await Permission.microphone.request();
      if (!mounted || _closing) return;
      if (!granted.isGranted) throw StateError('Microphone permission is required.');
      final directory = await getTemporaryDirectory();
      _file = File('${directory.path}/chhaya-voice-${const Uuid().v4()}.aac');
      await _recorder.openRecorder();
      _opened = true;
      if (!mounted || _closing) return;
      await _recorder.setSubscriptionDuration(const Duration(milliseconds:100));
      _meter = _recorder.onProgress?.listen((event) {
        if (!mounted || _closing) return;
        final decibels=event.decibels;
        if(decibels==null || !decibels.isFinite) return;
        setState(() {
          _levels.add((decibels/120).clamp(0.0,1.0).toDouble());
          if(_levels.length>32) _levels.removeAt(0);
        });
      });
      await _recorder.startRecorder(toFile: _file!.path, codec: Codec.aacADTS,
        bitRate: 24000, sampleRate: 16000, numChannels: 1);
      if (!mounted || _closing) return;
      setState(() => _recording = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _closing) return;
        setState(() => _seconds++);
        if (_seconds >= 60) _stop(true);
      });
    } catch (_) {
      await _cleanup();
      if (mounted) setState(() => _error = 'Could not record. Check microphone permission and try again.');
    }
  }

  Future<void> _cleanup() async {
    _timer?.cancel();
    await _meter?.cancel();
    _meter=null;
    if (_opened) {
      try { if (_recorder.isRecording) await _recorder.stopRecorder(); } catch (_) { /* Close below. */ }
      try { await _recorder.closeRecorder(); } catch (_) { /* No recording remains active. */ }
      _opened = false;
    }
    final file = _file;
    _file = null;
    if (file != null) {
      try { if (await file.exists()) await file.delete(); } catch (_) { /* OS may already remove its temporary file. */ }
    }
  }

  Future<void> _stop(bool keep) async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (mounted) setState(() => _busy = true);
    MessageAttachment? attachment;
    try {
      await _starting;
      if (_opened && _recorder.isRecording) await _recorder.stopRecorder();
      if (keep && _file != null) {
        final bytes = await AttachmentService.readBounded(_file!.openRead());
        attachment = MessageAttachment.fromBytes(name: 'Voice message.aac', mimeType: 'audio/aac', bytes: bytes);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording could not be attached. Try a shorter recording.')));
      }
    } finally { await _cleanup(); }
    if (mounted) Navigator.pop(context, attachment);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if (!_closing) {
      _closing = true;
      unawaited(_starting.whenComplete(_cleanup));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(child: SingleChildScrollView(
    padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('Voice message', style: ChhayaType.of(context).headline),
      const SizedBox(height: 16),
      Text(_recording ? 'Recording · ${_seconds}s / 60s' : 'Record up to one minute. Review the attachment before sending.',
        textAlign: TextAlign.center, style: ChhayaType.of(context).bodyLarge),
      const SizedBox(height:12),
      AudioLevelWaveform(levels:List.unmodifiable(_levels)),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!)),
      const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 8, children: [
        TextButton(onPressed: _closing ? null : () => _stop(false), child: const Text('Cancel')),
        FilledButton.icon(onPressed: _busy ? null : _recording ? () => _stop(true) : _start,
          icon: AnimatedSwitcher(duration:ChhayaMotion.duration(context,180),
            child:Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded,key:ValueKey(_recording))),
          label: Text(_recording ? 'Use recording' : 'Start recording')),
      ]),
    ]),
  ));
}
