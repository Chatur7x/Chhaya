// Link-this-device screen (DL-B enroll flow, spec §3.2/§3.5).
//
// Steps: honest-scope notice → start enrollment → QR/code with countdown →
// fingerprint compare → confirm → result. The code and QR contain a one-time
// secret valid for ~5 minutes and are shown on screen only; they are never
// logged. Messages are NOT synced to the linked device — the UI says so
// before linking (spec §5.3).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/privacy/sensitive_clipboard.dart';
import '../../../core/providers/app_providers.dart';
import '../../../services/auth/device_link_service.dart';
import '../../../services/api/device_link_client.dart';
import '../../theme/chhaya_theme.dart';
import '../../widgets/chhaya_app_bar.dart';
import '../../widgets/chhaya_button.dart';

const String _kHonestyScope =
    'Linked devices see your contacts and profile. They cannot read or send messages.';
const String _kHonestyReview =
    'Messages stay on the device where they were written. Not independently reviewed.';

enum _EnrollStage { idle, showing, verifying, confirmed, failed }

class DeviceLinkScreen extends ConsumerStatefulWidget {
  const DeviceLinkScreen({super.key});

  @override
  ConsumerState<DeviceLinkScreen> createState() => _DeviceLinkScreenState();
}

class _DeviceLinkScreenState extends ConsumerState<DeviceLinkScreen> {
  _EnrollStage _stage = _EnrollStage.idle;
  ActiveEnrollment? _enrollment;
  VerifiedApproval? _verified;
  String? _error;
  int _pollFailures = 0;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;
  late final DeviceLinkService _service;

  @override
  void initState() {
    super.initState();
    _service = ref.read(deviceLinkServiceProvider);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    // Wipe any in-flight attempt secrets when the screen disappears.
    unawaited(_service.cancelEnrollment());
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _stage = _EnrollStage.showing;
      _error = null;
      _pollFailures = 0;
    });
    try {
      final platform = defaultTargetPlatform.name;
      final enrollment = await _service.beginEnrollment(
        deviceName: _defaultDeviceName(platform),
        platform: _platformTag(platform),
      );
      if (!mounted) return;
      setState(() {
        _enrollment = enrollment;
        _remaining = enrollment.expiresAt.difference(DateTime.now().toUtc());
      });
      _startTimers();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _EnrollStage.failed;
        _error = deviceLinkErrorCopy(error);
      });
    }
  }

  void _startTimers() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollOnce());
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final enrollment = _enrollment;
      if (enrollment == null || !mounted) return;
      setState(() {
        _remaining = enrollment.expiresAt.difference(DateTime.now().toUtc());
        if (_remaining.isNegative) {
          _remaining = Duration.zero;
        }
      });
    });
  }

  Future<void> _pollOnce() async {
    if (_stage != _EnrollStage.showing) return;
    final result = await _service.checkStatus();
    if (!mounted || _stage != _EnrollStage.showing) return;
    switch (result.kind) {
      case DeviceLinkPollKind.pending:
        _pollFailures = 0;
        return;
      case DeviceLinkPollKind.networkError:
        _pollFailures += 1;
        if (_pollFailures >= 5) {
          _fail('No connection to the server. Check your network and try again.');
        }
        return;
      case DeviceLinkPollKind.approved:
        _pollFailures = 0;
        _pollTimer?.cancel();
        _countdownTimer?.cancel();
        await _verify();
        return;
      case DeviceLinkPollKind.denied:
        _fail('The other device declined this link request.');
        return;
      case DeviceLinkPollKind.expired:
      case DeviceLinkPollKind.notFound:
        _fail(deviceLinkErrorCopy(const DeviceLinkException(410, 'link_expired')));
        return;
    }
  }

  Future<void> _verify() async {
    setState(() => _stage = _EnrollStage.verifying);
    try {
      final verified = await _service.verifyApproval();
      if (!mounted) return;
      setState(() {
        _verified = verified;
        _stage = _EnrollStage.showing; // compare stage renders while verified != null
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _EnrollStage.failed;
        _error = 'The approval could not be verified. Nothing was linked.';
      });
    }
  }

  Future<void> _confirm() async {
    try {
      await _service.consumeAfterConfirm();
      if (!mounted) return;
      setState(() => _stage = _EnrollStage.confirmed);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _EnrollStage.failed;
        _error = deviceLinkErrorCopy(error);
      });
    }
  }

  Future<void> _cancelAll() async {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    await _service.cancelEnrollment();
    if (!mounted) return;
    setState(() {
      _stage = _EnrollStage.idle;
      _enrollment = null;
      _verified = null;
      _error = null;
    });
  }

  void _fail(String message) {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    setState(() {
      _stage = _EnrollStage.failed;
      _error = message;
    });
  }

  static String _defaultDeviceName(String platform) {
    switch (platform) {
      case 'windows':
        return 'Windows device';
      case 'macos':
        return 'Mac';
      case 'linux':
        return 'Linux device';
      case 'android':
        return 'Android device';
      case 'ios':
        return 'iPhone';
      default:
        return 'Linked device';
    }
  }

  static String _platformTag(String platform) {
    switch (platform) {
      case 'windows':
        return 'windows';
      case 'macos':
        return 'macos';
      case 'linux':
        return 'linux';
      case 'android':
        return 'android';
      case 'ios':
        return 'ios';
      default:
        return 'other';
    }
  }

  String _grouped(String code) {
    final buffer = StringBuffer();
    for (var i = 0; i < code.length; i += 4) {
      if (i > 0) buffer.write(' ');
      buffer.write(code.substring(i, (i + 4).clamp(0, code.length)));
    }
    return buffer.toString();
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
      appBar: const ChhayaAppBar(title: 'Link a device'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ChhayaSpacing.space4),
          children: [
            switch (_stage) {
              _EnrollStage.idle => _idleView(palette),
              _EnrollStage.showing => _verified == null
                  ? _waitingView(palette)
                  : _compareView(palette),
              _EnrollStage.verifying => _busyView(palette, 'Verifying approval…'),
              _EnrollStage.confirmed => _confirmedView(palette),
              _EnrollStage.failed => _failedView(palette),
            },
          ],
        ),
      ),
    );
  }

  Widget _idleView(ChhayaPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: ChhayaSpacing.space4),
        Icon(Icons.devices_rounded, size: 56, color: palette.info),
        const SizedBox(height: ChhayaSpacing.space4),
        Text('Link this device', style: ChhayaType.of(context).displaySmall),
        const SizedBox(height: ChhayaSpacing.space3),
        Text(_kHonestyScope, style: ChhayaType.of(context).bodyMedium),
        const SizedBox(height: ChhayaSpacing.space2),
        Text(_kHonestyReview, style: ChhayaType.of(context).bodyMedium.copyWith(color: palette.labelSecondary)),
        const SizedBox(height: ChhayaSpacing.space4),
        Container(
          padding: const EdgeInsets.all(ChhayaSpacing.space3),
          decoration: BoxDecoration(
            color: palette.primaryBackground,
            borderRadius: BorderRadius.circular(ChhayaRadius.md),
            border: Border.all(color: palette.separator),
          ),
          child: const Text(
            'You will get a one-time code that expires in 5 minutes. '
            'Enter it on your existing device to approve this one.',
          ),
        ),
        const SizedBox(height: ChhayaSpacing.space6),
        ChhayaPrimaryButton(
          label: 'Link this device',
          icon: Icons.link_rounded,
          height: 48,
          onPressed: _start,
        ),
      ],
    );
  }

  Widget _waitingView(ChhayaPalette palette) {
    final enrollment = _enrollment;
    if (enrollment == null) {
      return _busyView(palette, 'Preparing link…');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ChhayaSpacing.space2),
        Text(_kHonestyScope, textAlign: TextAlign.center, style: ChhayaType.of(context).bodyMedium),
        const SizedBox(height: ChhayaSpacing.space4),
        Center(
          child: Semantics(
            label: 'Link code QR',
            child: QrImageView(
              data: enrollment.linkPayload,
              size: 220,
              backgroundColor: ChhayaColors.white,
              padding: const EdgeInsets.all(16),
            ),
          ),
        ),
        const SizedBox(height: ChhayaSpacing.space4),
        Text(
          'LINK CODE',
          style: ChhayaType.of(context).labelSmall.copyWith(color: palette.labelSecondary, letterSpacing: 1.2),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ChhayaSpacing.space2),
        SelectableText(
          _grouped(enrollment.code),
          textAlign: TextAlign.center,
          semanticsLabel: 'Link code',
          style: ChhayaType.of(context).code.copyWith(fontSize: 20, letterSpacing: 2),
        ),
        const SizedBox(height: ChhayaSpacing.space3),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => SensitiveClipboard.copy(enrollment.linkPayload),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy link code'),
            ),
            const SizedBox(width: ChhayaSpacing.space2),
            Text('Expires in ${_countdownLabel()}',
                style: ChhayaType.of(context).bodyMedium.copyWith(color: palette.warning, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: ChhayaSpacing.space3),
        SelectableText(
          enrollment.linkPayload,
          textAlign: TextAlign.center,
          semanticsLabel: 'Link payload',
          style: ChhayaType.of(context).code.copyWith(fontSize: 10, color: palette.labelSecondary),
        ),
        const SizedBox(height: ChhayaSpacing.space4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: palette.accent),
            ),
            const SizedBox(width: ChhayaSpacing.space3),
            Text('Waiting for approval…', style: ChhayaType.of(context).bodyMedium),
          ],
        ),
        const SizedBox(height: ChhayaSpacing.space4),
        TextButton(
          onPressed: _cancelAll,
          child: const Text('Cancel link'),
        ),
      ],
    );
  }

  Widget _compareView(ChhayaPalette palette) {
    final verified = _verified!;
    final accountPrefix = verified.accountChhayaId.length > 7
        ? verified.accountChhayaId.substring(0, 7)
        : verified.accountChhayaId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ChhayaSpacing.space4),
        Icon(Icons.verified_user_rounded, size: 56, color: palette.success),
        const SizedBox(height: ChhayaSpacing.space4),
        Text('Confirm this code', style: ChhayaType.of(context).displaySmall, textAlign: TextAlign.center),
        const SizedBox(height: ChhayaSpacing.space3),
        Text(
          'Check that this code matches the one shown on your other device. If it does not match, cancel — the link is refused.',
          textAlign: TextAlign.center,
          style: ChhayaType.of(context).bodyMedium,
        ),
        const SizedBox(height: ChhayaSpacing.space4),
        Semantics(
          label: 'Fingerprint',
          child: SelectableText(
            formatFingerprint(verified.fingerprint),
            textAlign: TextAlign.center,
            style: ChhayaType.of(context).code.copyWith(fontSize: 28, letterSpacing: 3, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: ChhayaSpacing.space3),
        Text(
          'Link to account $accountPrefix…',
          textAlign: TextAlign.center,
          style: ChhayaType.of(context).bodyMedium.copyWith(color: palette.labelSecondary),
        ),
        const SizedBox(height: ChhayaSpacing.space6),
        ChhayaPrimaryButton(
          label: 'Confirm and link',
          icon: Icons.check_rounded,
          height: 48,
          onPressed: _confirm,
        ),
        const SizedBox(height: ChhayaSpacing.space2),
        TextButton(
          onPressed: _cancelAll,
          child: const Text('Cancel — codes do not match'),
        ),
      ],
    );
  }

  Widget _busyView(ChhayaPalette palette, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: ChhayaSpacing.space8),
      child: Column(
        children: [
          CircularProgressIndicator(color: palette.accent),
          const SizedBox(height: ChhayaSpacing.space4),
          Text(label, style: ChhayaType.of(context).bodyMedium),
        ],
      ),
    );
  }

  Widget _confirmedView(ChhayaPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ChhayaSpacing.space8),
        Icon(Icons.check_circle_rounded, size: 64, color: palette.success),
        const SizedBox(height: ChhayaSpacing.space4),
        Text('Device linked', style: ChhayaType.of(context).displaySmall, textAlign: TextAlign.center),
        const SizedBox(height: ChhayaSpacing.space3),
        Text(
          'This device can now see your contacts and profile. Your messages are not visible here — messages stay on the device where they were written.',
          textAlign: TextAlign.center,
          style: ChhayaType.of(context).bodyMedium,
        ),
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

  Widget _failedView(ChhayaPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ChhayaSpacing.space8),
        Icon(Icons.error_outline_rounded, size: 64, color: palette.error),
        const SizedBox(height: ChhayaSpacing.space4),
        Text('Could not link', style: ChhayaType.of(context).displaySmall, textAlign: TextAlign.center),
        const SizedBox(height: ChhayaSpacing.space3),
        Text(
          _error ?? 'Something went wrong. Nothing was linked.',
          textAlign: TextAlign.center,
          style: ChhayaType.of(context).bodyMedium,
        ),
        const SizedBox(height: ChhayaSpacing.space6),
        ChhayaPrimaryButton(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          height: 48,
          onPressed: () => setState(() {
            _stage = _EnrollStage.idle;
            _enrollment = null;
            _verified = null;
            _error = null;
          }),
        ),
      ],
    );
  }
}
