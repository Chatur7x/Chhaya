import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import '../../core/models/message_attachment.dart';

class VoiceMessagePlayer extends StatefulWidget {
  const VoiceMessagePlayer({super.key, required this.attachment, required this.foreground});
  final MessageAttachment attachment;
  final Color foreground;
  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> with WidgetsBindingObserver {
  FlutterSoundPlayer? _player;
  Future<void> _operation = Future.value();
  bool _playing = false, _busy = false;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    _operation = _playOrStop();
    await _operation;
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _playOrStop() async {
    try {
      if (_playing) {
        await _player?.stopPlayer();
        if (mounted) setState(() => _playing = false);
        return;
      }
      if (_player == null) {
        _player = FlutterSoundPlayer();
        await _player!.openPlayer();
      }
      if (!mounted) return;
      await _player!.startPlayer(fromDataBuffer: widget.attachment.bytes, codec: Codec.aacADTS,
        whenFinished: () { if (mounted) setState(() => _playing = false); });
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) {
        setState(() => _playing = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not play this voice message.')));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_operation.then((_) async {
        try { await _player?.stopPlayer(); } catch (_) { /* Player may already be closed. */ }
        if (mounted) setState(() => _playing = false);
      }));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_operation.then((_) async {
      try { await _player?.closePlayer(); } catch (_) { /* Already disposed by platform. */ }
    }));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: TextButton.styleFrom(foregroundColor: widget.foreground),
    onPressed: _busy ? null : _toggle,
    icon: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
    label: Text(_playing ? 'Stop voice message' : 'Play voice message'),
  );
}
