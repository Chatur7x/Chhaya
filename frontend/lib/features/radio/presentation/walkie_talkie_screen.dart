import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../data/walkie_talkie_service.dart';

/// Walkie-Talkie PTT Screen — Zello-style push-to-talk radio interface.
class WalkieTalkieScreen extends ConsumerStatefulWidget {
  const WalkieTalkieScreen({super.key});

  @override
  ConsumerState<WalkieTalkieScreen> createState() => _WalkieTalkieScreenState();
}

class _WalkieTalkieScreenState extends ConsumerState<WalkieTalkieScreen>
    with SingleTickerProviderStateMixin {
  bool _isTransmitting = false;
  bool _scrambleOn = false;
  bool _repeaterOn = false;
  String _activeChannel = '#default';
  final List<String> _channels = ['#default', '#emergency', '#team-alpha', '#family'];
  late AnimationController _pulseController;
  late WalkieTalkieService _pttService;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pttService = ref.read(walkieTalkieServiceProvider);
      _pttService.switchChannel(_activeChannel);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pttService.dispose();
    super.dispose();
  }

  void _startTransmit() async {
    HapticFeedback.heavyImpact();
    setState(() => _isTransmitting = true);
    _pulseController.repeat(reverse: true);
    
    if (_activeChannel == '#emergency') {
      await _pttService.priorityBroadcast();
    } else {
      await _pttService.startTransmitting();
    }
  }

  void _stopTransmit() async {
    HapticFeedback.lightImpact();
    setState(() => _isTransmitting = false);
    _pulseController.stop();
    _pulseController.reset();
    
    await _pttService.stopTransmitting();
  }

  void _triggerSOS() async {
    HapticFeedback.heavyImpact();
    await _pttService.sosBroadcast();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🆘 SOS broadcast sent on ALL channels'),
          backgroundColor: ChaayaTheme.sosRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to incoming audio streams from provider if available
    final isReceiving = false; // In a full app, listen to a PTT receive stream StateProvider
    
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        backgroundColor: ChaayaTheme.background,
        title: const Row(
          children: [
            Icon(Icons.radio, color: ChaayaTheme.warningYellow, size: 22),
            SizedBox(width: 10),
            Text('Walkie-Talkie'),
          ],
        ),
        actions: [
          // Scramble toggle
          IconButton(
            icon: Icon(
              _scrambleOn ? Icons.lock : Icons.lock_open,
              color: _scrambleOn ? ChaayaTheme.safeGreen : ChaayaTheme.textMuted,
              size: 20,
            ),
            onPressed: () {
              setState(() => _scrambleOn = !_scrambleOn);
              _pttService.toggleScramble();
            },
            tooltip: 'Scramble',
          ),
          // Repeater toggle
          IconButton(
            icon: Icon(
              Icons.cell_tower,
              color: _repeaterOn ? ChaayaTheme.bleColor : ChaayaTheme.textMuted,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _repeaterOn = !_repeaterOn;
                _pttService.toggleRepeater();
              });
            },
            tooltip: 'Repeater',
          ),
        ],
      ),
      body: Column(
        children: [
          // Channel selector
          _buildChannelSelector(),

          // Status indicators
          _buildStatusBar(isReceiving),

          // Main PTT area
          Expanded(child: _buildPTTArea(isReceiving)),

          // SOS Button
          _buildSOSButton(),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildChannelSelector() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _channels.length,
        itemBuilder: (context, index) {
          final ch = _channels[index];
          final isActive = ch == _activeChannel;
          return GestureDetector(
            onTap: () {
              setState(() => _activeChannel = ch);
              _pttService.switchChannel(ch);
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isActive
                    ? ChaayaTheme.accent.withOpacity(0.2)
                    : ChaayaTheme.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isActive ? ChaayaTheme.accent : ChaayaTheme.glassBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    ch == '#emergency' ? Icons.warning_amber : Icons.tag,
                    size: 14,
                    color: isActive
                        ? ChaayaTheme.accent
                        : ChaayaTheme.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    ch,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive
                          ? ChaayaTheme.accent
                          : ChaayaTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusBar(bool isReceiving) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statusItem(
            isReceiving ? Icons.hearing : Icons.bluetooth,
            isReceiving ? 'RECEIVING' : 'STANDBY',
            isReceiving ? 'Incoming...' : '3 peers',
            isReceiving ? ChaayaTheme.safeGreen : ChaayaTheme.bleColor,
          ),
          _divider(),
          _statusItem(
            _scrambleOn ? Icons.lock : Icons.lock_open,
            'Scramble',
            _scrambleOn ? 'ON' : 'OFF',
            _scrambleOn ? ChaayaTheme.safeGreen : ChaayaTheme.textMuted,
          ),
          _divider(),
          _statusItem(
            Icons.cell_tower,
            'Repeater',
            _repeaterOn ? 'ON' : 'OFF',
            _repeaterOn ? ChaayaTheme.bleColor : ChaayaTheme.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _statusItem(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: ChaayaTheme.textMuted)),
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 30, color: ChaayaTheme.glassBorder);
  }

  Widget _buildPTTArea(bool isReceiving) {
    final ident = ref.watch(identityServiceProvider).currentIdentity;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Callsign display
          Text(
            ident?.username.toUpperCase() ?? 'ALPHA-1',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ChaayaTheme.textSecondary,
              fontFamily: 'JetBrains Mono',
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _activeChannel,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: ChaayaTheme.accent,
            ),
          ),
          const SizedBox(height: 30),

          // PTT Button
          GestureDetector(
            onTapDown: (_) => _startTransmit(),
            onTapUp: (_) => _stopTransmit(),
            onTapCancel: () => _stopTransmit(),
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 140 + (_isTransmitting ? _pulseController.value * 20 : 0),
                  height: 140 + (_isTransmitting ? _pulseController.value * 20 : 0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: _isTransmitting
                          ? [ChaayaTheme.sosRed, ChaayaTheme.sosRed.withOpacity(0.6)]
                          : isReceiving
                              ? [ChaayaTheme.safeGreen, ChaayaTheme.safeGreen.withOpacity(0.6)]
                              : [ChaayaTheme.accent, ChaayaTheme.accent.withOpacity(0.6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_isTransmitting ? ChaayaTheme.sosRed : ChaayaTheme.accent)
                            .withOpacity(0.4),
                        blurRadius: _isTransmitting ? 40 : 20,
                        spreadRadius: _isTransmitting ? 5 : 0,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isTransmitting ? Icons.mic : isReceiving ? Icons.volume_up : Icons.mic_none,
                        size: 48,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isTransmitting ? 'TRANSMITTING' : isReceiving ? 'RECEIVING' : 'HOLD TO TALK',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Status text
          Text(
            _isTransmitting 
                ? '🔴 Broadcasting on $_activeChannel' 
                : isReceiving 
                    ? '🟢 Receiving transmission' 
                    : 'Ready to transmit',
            style: TextStyle(
              fontSize: 13,
              color: _isTransmitting ? ChaayaTheme.sosRed : isReceiving ? ChaayaTheme.safeGreen : ChaayaTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSOSButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: _triggerSOS,
          style: ElevatedButton.styleFrom(
            backgroundColor: ChaayaTheme.sosRed.withOpacity(0.2),
            foregroundColor: ChaayaTheme.sosRed,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: ChaayaTheme.sosRed),
            ),
          ),
          icon: const Icon(Icons.sos, size: 20),
          label: const Text('SOS — ALL CHANNELS', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

/// AnimatedBuilder from controller
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;

  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) => builder(context, null);
}

