import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/message_attachment.dart';

class VoiceMessagePlayer extends StatefulWidget {
  const VoiceMessagePlayer({
    super.key,
    required this.attachment,
    required this.foreground,
  });
  final MessageAttachment attachment;
  final Color foreground;
  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer>
    with WidgetsBindingObserver {
  AudioPlayer? _player;
  StreamSubscription<void>? _completed;
  File? _temporaryFile;
  Future<void> _operation = Future.value();
  bool _playing = false, _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _removeTemporaryFile() async {
    final file = _temporaryFile;
    _temporaryFile = null;
    if (file != null) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        /* OS may remove temporary files. */
      }
    }
  }

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
        await _player?.stop();
        await _removeTemporaryFile();
        if (mounted) setState(() => _playing = false);
        return;
      }
      _player ??= AudioPlayer();
      _completed ??= _player!.onPlayerComplete.listen((_) {
        unawaited(_removeTemporaryFile());
        if (mounted) setState(() => _playing = false);
      });
      final bytes = widget.attachment.bytes;
      Source source = BytesSource(bytes, mimeType: 'audio/aac');
      // This platform's BytesSource implementation writes an unmanaged cache file.
      if (Platform.isIOS || Platform.isMacOS || Platform.isLinux) {
        final directory = await getTemporaryDirectory();
        _temporaryFile = File(
          '${directory.path}/chhaya-voice-play-${const Uuid().v4()}.aac',
        );
        await _temporaryFile!.writeAsBytes(bytes, flush: true);
        source = DeviceFileSource(_temporaryFile!.path, mimeType: 'audio/aac');
      }
      if (!mounted) {
        await _removeTemporaryFile();
        return;
      }
      await _player!.play(source);
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      await _removeTemporaryFile();
      if (mounted) {
        setState(() => _playing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play this voice message.')),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(
        _operation.then((_) async {
          try {
            await _player?.stop();
          } catch (_) {
            /* Player may already be closed. */
          }
          await _removeTemporaryFile();
          if (mounted) setState(() => _playing = false);
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      _operation.then((_) async {
        try {
          await _completed?.cancel();
          await _player?.dispose();
        } finally {
          await _removeTemporaryFile();
        }
      }),
    );
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
