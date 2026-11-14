// Approve-an-enrollment screen (DL-B approve flow, spec §3.5).
//
// The primary device enters the link payload (typed or pasted — QR scanning
// is out of scope; no camera permissions are added). The screen derives the
// fingerprint, shows the device being linked, and requires an explicit tap to
// approve. Denial is a first-class path. The primary's ephemeral key is
// wiped on approve, deny, or dispose.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../services/auth/device_link_service.dart';
import '../../theme/chhaya_theme.dart';
import '../../widgets/chhaya_app_bar.dart';
import '../../widgets/chhaya_button.dart';

const String _kHonestyScope =
    'Linked devices see your contacts and profile. They cannot read or send messages.';

enum _ApproveStage { input, ready, working, approved, denied, failed }

class DeviceApproveScreen extends ConsumerStatefulWidget {
  const DeviceApproveScreen({super.key});

  @override
  ConsumerState<DeviceApproveScreen> createState() => _DeviceApproveScreenState();
}

class _DeviceApproveScreenState extends ConsumerState<DeviceApproveScreen> {
  final TextEditingController _payloadController = TextEditingController();
  _ApproveStage _stage = _ApproveStage.input;
  LinkPayload? _payload;
  ApproveSession? _session;
  String? _fingerprint;
  String? _error;
  Timer? _countdownTimer;
  Duration _remaining = const Duration(minutes: 5);

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _payloadController.dispose();
    final session = _session;
    if (session != null &&
        _stage != _ApproveStage.approved &&
        _stage != _ApproveStage.denied) {
      unawaited(session.wipe());
    }
    super.dispose();
  }

  void _parse() {
    final parsed = LinkPayload.parse(_payloadController.text);
    if (parsed == null) {
      setState(() {
        _error = 'That does not look like a Chhaya link request. Check the code and try again.';
      });
      return;
    }
    final service = ref.read(deviceLinkServiceProvider);
    final session = service.beginApproval(payload: parsed);
    setState(() {
      _payload = parsed;
      _session = session;
      _stage = _ApproveStage.ready;
      _error = null;
      _remaining = const Duration(minutes: 5);
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining -= const Duration(seconds: 1);
        if (_remaining <= Duration.zero) {
          _remaining = Duration.zero;
          if (_stage == _ApproveStage.ready) {
            // Auto-abort on timeout (spec §3.5): wipe the ephemeral key.
            final session = _session;
            _session = null;
            if (session != null) unawaited(session.wipe());
            _countdownTimer?.cancel();
            _stage = _ApproveStage.failed;
            _error = 'That link code has expired. Generate a new one on the other device.';
          }
        }
      });
    });
    unawaited(_loadFingerprint());
  }

  Future<void> _loadFingerprint() async {
    final session = _session;
    if (session == null) return;
    try {
      final fp = await session.fingerprint();
      if (!mounted) return;
      setState(() => _fingerprint = formatFingerprint(fp));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _ApproveStage.failed;
        _error = 'Could not prepare the approval. Nothing was linked.';
      });
    }
  }

  Future<void> _approve() async {
    final session = _session;
    if (session == null) return;
    setState(() => _stage = _ApproveStage.working);
    try {
      await session.finishApproval();
      _session = null;
      _countdownTimer?.cancel();
      if (!mounted) return;
      setState(() => _stage = _ApproveStage.approved);
    } catch (error) {
      _session = null;
      _countdownTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _stage = _ApproveStage.failed;
        _error = deviceLinkErrorCopy(error);
      });
    }
  }

  Future<void> _deny() async {
    final payload = _payload;
    if (payload == null) return;
    final session = _session;
    setState(() => _stage = _ApproveStage.working);
    try {
      if (session != null) await session.wipe();
      await ref.read(deviceLinkServiceProvider).denyPendingLink(payload: payload);
      _session = null;
      _countdownTimer?.cancel();
      if (!mounted) return;
      setState(() => _stage = _ApproveStage.denied);
    } catch (error) {
      _session = null;
      _countdownTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _stage = _ApproveStage.failed;
        _error = deviceLinkErrorCopy(error);
      });
    }
  }

  String _countdownLabel() {
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = ChhayaPalette.of(context);
    return Scaffold(
      appBar: const ChhayaAppBar(title: 'Approve enrollment'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ChhayaSpacing.space4),
          children: [
            switch (_stage) {
              _ApproveStage.input => _inputView(palette),
              _ApproveStage.ready => _approveView(palette),
              _ApproveStage.working => _busyView(palette),
              _ApproveStage.approved => _resultView(
                  palette,
                  icon: Icons.check_circle_rounded,
                  iconColor: palette.success,
                  title: 'Device linked',
                  body:
                      'The new device can now see your contacts and profile. Your messages are not synced to it.',
                ),
              _ApproveStage.denied => _resultView(
                  palette,
                  icon: Icons.block_rounded,
                  iconColor: palette.warning,
                  title: 'Enrollment denied',
                  body: 'The link request was declined. No device was added to your account.',
                ),
              _ApproveStage.failed => _resultView(
                  palette,
                  icon: Icons.error_outline_rounded,
                  iconColor: palette.error,
                  title: 'Could not complete',
                  body: _error ?? 'Something went wrong. Nothing was linked.',
                ),
            },
          ],
        ),
      ),
    );
  }

  Widget _inputView(ChhayaPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ChhayaSpacing.space4),
        Icon(Icons.qr_code_scanner_rounded, size: 56, color: palette.info),
        const SizedBox(height: ChhayaSpacing.space4),
        Text('Approve a new device', style: ChhayaType.of(context).displaySmall),
        const SizedBox(height: ChhayaSpacing.space3),
        Text(_kHonestyScope, style: ChhayaType.of(context).bodyMedium),
        const SizedBox(height: ChhayaSpacing.space4),
        Text(
          'On the new device, open Settings → Linked devices → Link a device. '
          'Paste its link code here (or its QR contents).',
          style: ChhayaType.of(context).bodyMedium.copyWith(color: palette.labelSecondary),
        ),
        const SizedBox(height: ChhayaSpacing.space3),
        TextField(
          controller: _payloadController,
          maxLines: 3,
          autocorrect: false,
          enableSuggestions: false,
          textAlignVertical: TextAlignVertical.center,
          decoration: const InputDecoration(
            labelText: 'Link request code',
            hintText: 'Chhaya-link-v1:…',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: ChhayaSpacing.space2),
          Text(_error!, style: TextStyle(color: palette.error)),
        ],
        const SizedBox(height: ChhayaSpacing.space6),
        ChhayaPrimaryButton(
          label: 'Review request',
          icon: Icons.fingerprint_rounded,
          height: 48,
          onPressed: _parse,
        ),
      ],
    );
  }

  Widget _approveView(ChhayaPalette palette) {
    final payload = _payload;
    final name = payload?.deviceName;
    final title = name != null ? 'Link to "$name"?' : 'Link a new device?';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ChhayaSpacing.space4),
        Text(title, style: ChhayaType.of(context).displaySmall, textAlign: TextAlign.center),
        const SizedBox(height: ChhayaSpacing.space2),
        if (payload?.platform != null)
          Center(
            child: Chip(label: Text(payload!.platform!)),
          ),
        const SizedBox(height: ChhayaSpacing.space4),
        Text(
          'Compare this code with the one shown on the new device. If they match, tap Approve.',
          textAlign: TextAlign.center,
          style: ChhayaType.of(context).bodyMedium,
        ),
        const SizedBox(height: ChhayaSpacing.space4),
        Semantics(
          label: 'Fingerprint',
          child: SelectableText(
            _fingerprint ?? '…',
            textAlign: TextAlign.center,
            style: ChhayaType.of(context).code.copyWith(
                fontSize: 28, letterSpacing: 3, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: ChhayaSpacing.space2),
        Text(
          'Expires in ${_countdownLabel()}',
          textAlign: TextAlign.center,
          style: ChhayaType.of(context).bodyMedium.copyWith(color: palette.warning, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ChhayaSpacing.space6),
        ChhayaPrimaryButton(
          label: 'Approve',
          icon: Icons.check_rounded,
          height: 48,
          onPressed: _approve,
        ),
        const SizedBox(height: ChhayaSpacing.space2),
        TextButton(
          onPressed: _deny,
          child: const Text('Deny request'),
        ),
      ],
    );
  }

  Widget _busyView(ChhayaPalette palette) {
    return Padding(
      padding: const EdgeInsets.only(top: ChhayaSpacing.space8),
      child: Column(
        children: [
          CircularProgressIndicator(color: palette.accent),
          const SizedBox(height: ChhayaSpacing.space4),
          Text('Contacting the server…', style: ChhayaType.of(context).bodyMedium),
        ],
      ),
    );
  }

  Widget _resultView(
    ChhayaPalette palette, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ChhayaSpacing.space8),
        Icon(icon, size: 64, color: iconColor),
        const SizedBox(height: ChhayaSpacing.space4),
        Text(title, style: ChhayaType.of(context).displaySmall, textAlign: TextAlign.center),
        const SizedBox(height: ChhayaSpacing.space3),
        Text(body, textAlign: TextAlign.center, style: ChhayaType.of(context).bodyMedium),
        const SizedBox(height: ChhayaSpacing.space6),
        ChhayaPrimaryButton(
          label: 'Done',
          icon: Icons.check_rounded,
          height: 48,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}
