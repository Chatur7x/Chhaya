import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/widgets/animated_builder.dart';
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
  
  double _tiltX = 0.0;
  double _tiltY = 0.0;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _accelSubscription = accelerometerEventStream().listen((event) {
      if (mounted) {
        setState(() {
          _tiltX = (event.y * 0.04).clamp(-0.1, 0.1);
          _tiltY = (event.x * 0.04).clamp(-0.1, 0.1);
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pttService = ref.read(walkieTalkieServiceProvider);
      _pttService.switchChannel(_activeChannel);
    });
  }

  @override
  void dispose() {
    _accelSubscription?.cancel();
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
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: ChaayaTheme.surfaceLight.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
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
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..rotateX(_tiltX)
      ..rotateY(_tiltY);

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutQuart,
        transform: matrix,
        transformAlignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Callsign display
            Text(
              ident?.username.toUpperCase() ?? 'ALPHA-1',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: ChaayaTheme.textSecondary,
                fontFamily: 'JetBrains Mono',
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _activeChannel,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: ChaayaTheme.accent,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 50),

            // Heavy 3D PTT Button
            GestureDetector(
              onTapDown: (_) => _startTransmit(),
              onTapUp: (_) => _stopTransmit(),
              onTapCancel: () => _stopTransmit(),
              child: ChaayaAnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    width: 200 + (_isTransmitting ? _pulseController.value * 25 : 0),
                    height: 200 + (_isTransmitting ? _pulseController.value * 25 : 0),
                    transform: Matrix4.identity()..scale(_isTransmitting ? 0.92 : 1.0),
                    transformAlignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: _isTransmitting
                            ? [ChaayaTheme.sosRed, ChaayaTheme.sosRed.withValues(alpha: 0.6)]
                            : isReceiving
                                ? [ChaayaTheme.safeGreen, ChaayaTheme.safeGreen.withValues(alpha: 0.6)]
                                : [ChaayaTheme.accent, ChaayaTheme.accent.withValues(alpha: 0.6)],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: _isTransmitting ? 0.4 : 0.1),
                        width: _isTransmitting ? 4 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isTransmitting ? ChaayaTheme.sosRed : ChaayaTheme.accent)
                              .withValues(alpha: _isTransmitting ? 0.6 : 0.2),
                          blurRadius: _isTransmitting ? 50 : 25,
                          spreadRadius: _isTransmitting ? 10 : 0,
                          offset: const Offset(0, 10),
                        ),
                        // Inner deep shadow for 3D button effect
                        BoxShadow(
                          color: Colors.black.withValues(alpha: _isTransmitting ? 0.0 : 0.3),
                          blurRadius: 15,
                          spreadRadius: -5,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Inner ring glow
                        if (!_isTransmitting)
                          Container(
                            width: 170,
                            height: 170,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 2),
                            ),
                          ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isTransmitting ? Icons.mic : isReceiving ? Icons.volume_up : Icons.mic_none,
                              size: 56,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isTransmitting ? 'TRANSMITTING' : isReceiving ? 'RECEIVING' : 'HOLD TO TALK',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 50),

            // Status text
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _isTransmitting 
                    ? '🔴 BROADCASTING ON $_activeChannel' 
                    : isReceiving 
                        ? '🟢 RECEIVING TRANSMISSION' 
                        : 'READY TO TRANSMIT',
                key: ValueKey(_isTransmitting || isReceiving),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: _isTransmitting ? ChaayaTheme.sosRed : isReceiving ? ChaayaTheme.safeGreen : ChaayaTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSOSButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: ChaayaTheme.sosRed.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: _triggerSOS,
          style: ElevatedButton.styleFrom(
            backgroundColor: ChaayaTheme.sosRed.withValues(alpha: 0.15),
            foregroundColor: ChaayaTheme.sosRed,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: ChaayaTheme.sosRed, width: 1.5),
            ),
          ),
          icon: const Icon(Icons.sos_rounded, size: 24),
          label: const Text('SOS — OVERRIDE ALL', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5)),
        ),
      ),
    );
  }
}

