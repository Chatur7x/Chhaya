import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/chhaya_theme.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/chhaya_button.dart';
import '../../../core/models/chhaya_id.dart';
import '../../../core/router/chhaya_router.dart';
import '../../../core/providers/app_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> with TickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;
  bool _isLoginMode = false;

  // Signup state
  final _nameCtrl = TextEditingController();
  ChhayaId? _generatedId;
  List<String>? _generatedPhrase;
  bool _creating = false;
  bool _phraseCopied = false;

  // Login state
  final _loginPhraseCtrl = TextEditingController();
  final _loginBackupCtrl = TextEditingController();
  bool _loginLoading = false;
  bool _loginObscure = true;

  // Animations
  late AnimationController _heroAnimCtrl;
  late Animation<double> _heroFadeAnim;

  bool get disableAnimations => MediaQuery.of(context).disableAnimations;

  @override
  void initState() {
    super.initState();
    _heroAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _heroFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _heroAnimCtrl, curve: const Interval(0.2, 1.0, curve: Curves.easeOut)),
    );
    _heroAnimCtrl.forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _loginPhraseCtrl.dispose();
    _loginBackupCtrl.dispose();
    _heroAnimCtrl.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 3) {
      _pageCtrl.animateToPage(_currentPage + 1, duration: ChhayaAnimation.normal, curve: ChhayaAnimation.springCurve);
    }
  }

  void _goToAuth(bool isLogin) {
    setState(() => _isLoginMode = isLogin);
    _pageCtrl.animateToPage(3, duration: ChhayaAnimation.normal, curve: ChhayaAnimation.springCurve);
  }

  void _generateId() {
    final id = ChhayaId.generate();
    setState(() {
      _generatedId = id;
    });
    ChhayaHaptics.medium();
  }

  Future<void> _handleCreateAccount() async {
    if (_creating) return;
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter display name')));
      return;
    }
    setState(() => _creating = true);
    try {
      final auth = ref.read(authServiceProvider);
      final profile = await auth.createAccount(displayName: _nameCtrl.text.trim());
      final phrase = profile.recoveryPhrase;
      setState(() {
        _generatedPhrase = phrase;
        _creating = false;
      });
      ChhayaHaptics.success();
    } catch (e) {
      setState(() => _creating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _confirmPhraseAndEnter() async {
    final auth = ref.read(authServiceProvider);
    final profile = auth.currentUser;
    if (profile == null) return;
    final db = ref.read(localDatabaseProvider);
    final convos = await db.getAllConversations();
    final contacts = await db.getAllContacts();
    ref.read(currentUserProvider.notifier).state = profile;
    ref.read(conversationsProvider.notifier).setConversations(convos);
    ref.read(contactsProvider.notifier).setContacts(contacts);
    if (mounted) Navigator.of(context).pushReplacementNamed(ChhayaRouter.home);
  }

  Future<void> _handleLogin() async {
    final phraseText = _loginPhraseCtrl.text.trim();
    final backupText = _loginBackupCtrl.text.trim();
    if (phraseText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter 12-word recovery phrase')));
      return;
    }
    final words = phraseText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length != 12) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recovery phrase must be 12 words')));
      return;
    }
    setState(() => _loginLoading = true);
    try {
      final auth = ref.read(authServiceProvider);
      bool success = false;
      if (backupText.isNotEmpty) {
        success = await auth.restoreFromBackup(backupText, words);
        if (!success) {
          await auth.restoreAccount(words);
          success = auth.currentUser != null;
        }
      } else {
        await auth.restoreAccount(words);
        success = auth.currentUser != null;
      }

      if (success) {
        final profile = auth.currentUser;
        ref.read(currentUserProvider.notifier).state = profile;
        final db = ref.read(localDatabaseProvider);
        final convos = await db.getAllConversations();
        final contacts = await db.getAllContacts();
        ref.read(conversationsProvider.notifier).setConversations(convos);
        ref.read(contactsProvider.notifier).setContacts(contacts);
        if (mounted) Navigator.of(context).pushReplacementNamed(ChhayaRouter.home);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restore failed — check phrase/backup')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      body: Stack(
        children: [
          // Aurora glow background
          Positioned(
            top: -120,
            left: -80,
            right: -80,
            height: 380,
            child: Container(
              decoration: const BoxDecoration(gradient: ChhayaColors.glowGradient),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Top bar with skip
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space4, vertical: ChhayaSpacing.space2),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space3, vertical: ChhayaSpacing.space1),
                        decoration: BoxDecoration(
                          color: ChhayaColors.cardSurface.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(ChhayaRadius.pill),
                          border: Border.all(color: ChhayaColors.glassBorder.withValues(alpha: 0.14)),
                        ),
                        child: Row(
                          children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: ChhayaColors.online, shape: BoxShape.circle)),
                            const SizedBox(width: ChhayaSpacing.space1),
                            Text('End-to-End Encrypted', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.labelSecondary, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (_currentPage < 3)
                        TextButton(
                          onPressed: () => _goToAuth(false),
                          child: Text('Skip', style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.labelTertiary)),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageCtrl,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _pageWelcome(),
                      _pageFeatures(),
                      _pageAuthChoice(),
                      _isLoginMode ? _pageLogin() : _pageSignup(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: ChhayaSpacing.space5, top: ChhayaSpacing.space2),
                  child: _buildDots(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final isActive = i == _currentPage;
        final isPast = i < _currentPage;
        return AnimatedContainer(
          duration: disableAnimations ? Duration.zero : ChhayaAnimation.fast,
          margin: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space1),
          width: isActive ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? ChhayaColors.accent : isPast ? ChhayaColors.info.withValues(alpha: 0.5) : ChhayaColors.fillTertiary,
            borderRadius: BorderRadius.circular(ChhayaRadius.xs),
            boxShadow: isActive && !disableAnimations ? ChhayaShadows.glowBlue : null,
          ),
        );
      }),
    );
  }

  Widget _pageWelcome() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ChhayaSpacing.space6, ChhayaSpacing.space3, ChhayaSpacing.space6, ChhayaSpacing.space6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Terminal boot panel — left-aligned, hacker minimal (taste §4.3)
          AnimatedBuilder(
            animation: _heroAnimCtrl,
            builder: (context, child) {
              return Opacity(
                opacity: disableAnimations ? 1.0 : _heroFadeAnim.value,
                child: child,
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(ChhayaSpacing.space4),
              decoration: BoxDecoration(
                color: ChhayaColors.cardSurface,
                borderRadius: BorderRadius.circular(ChhayaRadius.md),
                border: Border.all(
                  color: ChhayaColors.accent.withValues(alpha: 0.35),
                  width: 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: ChhayaColors.accent,
                          borderRadius: BorderRadius.circular(ChhayaRadius.sm),
                        ),
                        child: const Icon(Icons.shield_outlined, size: 22, color: ChhayaColors.onAccent),
                      ),
                      const SizedBox(width: ChhayaSpacing.space3),
                      Text(
                        'CHHAYA',
                        style: ChhayaTypography.displaySmall.copyWith(
                          fontFamily: 'JetBrains Mono',
                          color: ChhayaColors.accent,
                          fontSize: 24,
                          letterSpacing: 4.0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ChhayaSpacing.space3),
                  Divider(height: 1, thickness: 1, color: ChhayaColors.separator),
                  const SizedBox(height: ChhayaSpacing.space3),
                  _termLine('> identity ..... 66-char key [OK]'),
                  _termLine('> route ........ 3-hop onion [OK]'),
                  _termLine('> cipher ....... AES-256-GCM [OK]'),
                  Row(
                    children: [
                      Text(
                        '> status ....... GHOST',
                        style: ChhayaTypography.code.copyWith(
                          color: ChhayaColors.labelSecondary,
                          fontSize: 12,
                        ),
                      ),
                      _BlinkCursor(disabled: disableAnimations),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: ChhayaSpacing.space5),
          Text('Privacy Redefined. Speed Perfected.', style: ChhayaTypography.headlineSmall.copyWith(color: ChhayaColors.labelPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: ChhayaSpacing.space2),
          Text(
            'No phone. No email. Just you.',
            style: ChhayaTypography.bodySmall.copyWith(color: ChhayaColors.labelSecondary, height: 1.5),
          ),
          const SizedBox(height: ChhayaSpacing.space8),
          ChhayaPrimaryButton(label: 'Get Started', icon: Icons.arrow_forward_rounded, onPressed: _nextPage),
          const SizedBox(height: ChhayaSpacing.space3),
          Center(
            child: ChhayaGhostButton(
              label: 'I already have an account — Log In',
              icon: Icons.login_rounded,
              onPressed: () => _goToAuth(true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _termLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ChhayaSpacing.space1),
      child: Text(
        text,
        style: ChhayaTypography.code.copyWith(
          color: ChhayaColors.labelSecondary,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _pageFeatures() {
    final features = [
      {'icon': Icons.lock_rounded, 'title': 'End-to-End Encrypted', 'desc': 'AES-256-GCM + Double Ratchet', 'color': ChhayaColors.success},
      {'icon': Icons.person_off_rounded, 'title': 'No Phone Number', 'desc': '66-char anonymous Chhaya ID', 'color': ChhayaColors.accent},
      {'icon': Icons.alt_route_rounded, 'title': 'Onion Routed', 'desc': '3 hops • 512B padding • IP hidden', 'color': ChhayaColors.info},
      {'icon': Icons.bolt_rounded, 'title': 'Lightning Fast', 'desc': 'P2P WebRTC • Decentralized files', 'color': ChhayaColors.warning},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(ChhayaSpacing.space5, ChhayaSpacing.space2, ChhayaSpacing.space5, ChhayaSpacing.space5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Why Chhaya?', style: ChhayaTypography.displayMedium.copyWith(fontSize: 26)),
          const SizedBox(height: ChhayaSpacing.space1),
          Text('Military-grade privacy, consumer-grade polish', style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.labelTertiary)),
          const SizedBox(height: ChhayaSpacing.space5),
          ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: ChhayaSpacing.space3),
                child: GlassContainer(
                  padding: const EdgeInsets.all(ChhayaSpacing.space4),
                  borderRadius: ChhayaRadius.xl,
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: (f['color'] as Color).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(ChhayaRadius.xl), border: Border.all(color: (f['color'] as Color).withValues(alpha: 0.22))),
                      child: Icon(f['icon'] as IconData, color: f['color'] as Color, size: 22),
                    ),
                    const SizedBox(width: ChhayaSpacing.space4),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(f['title'] as String, style: ChhayaTypography.headlineMedium.copyWith(fontSize: 14)),
                        const SizedBox(height: ChhayaSpacing.space1),
                        Text(f['desc'] as String, style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.labelTertiary, fontSize: 12)),
                      ]),
                    ),
                    Icon(Icons.check_circle_rounded, size: 18, color: (f['color'] as Color).withValues(alpha: 0.6)),
                  ]),
                ),
              )),
          const SizedBox(height: ChhayaSpacing.space4),
          ChhayaPrimaryButton(label: 'Continue', onPressed: _nextPage),
        ],
      ),
    );
  }

  Widget _pageAuthChoice() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ChhayaSpacing.space5, ChhayaSpacing.space4, ChhayaSpacing.space5, ChhayaSpacing.space5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Welcome', style: ChhayaTypography.displaySmall),
          const SizedBox(height: ChhayaSpacing.space2),
          Text('Choose how you want to enter Chhaya', style: ChhayaTypography.bodySmall.copyWith(color: ChhayaColors.labelSecondary)),
          const SizedBox(height: ChhayaSpacing.space7),
          // Signup card
          ChhayaCard(
            onTap: () => _goToAuth(false),
            padding: const EdgeInsets.all(ChhayaSpacing.space5),
            radius: ChhayaRadius.xxl,
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(gradient: ChhayaColors.accentGradient, borderRadius: BorderRadius.circular(ChhayaRadius.xl)),
                  child: const Icon(Icons.person_add_rounded, color: ChhayaColors.onAccent, size: 26),
                ),
                const SizedBox(width: ChhayaSpacing.space4),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Create New Account', style: ChhayaTypography.headlineMedium),
                    const SizedBox(height: ChhayaSpacing.space1),
                    Text('Generate Chhaya ID + recovery phrase', style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.labelTertiary)),
                  ]),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: ChhayaColors.labelTertiary),
              ],
            ),
          ),
          const SizedBox(height: ChhayaSpacing.space4),
          ChhayaCard(
            onTap: () => _goToAuth(true),
            padding: const EdgeInsets.all(ChhayaSpacing.space5),
            radius: ChhayaRadius.xxl,
            color: ChhayaColors.secondaryBackground,
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: ChhayaColors.info.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(ChhayaRadius.xl), border: Border.all(color: ChhayaColors.info.withValues(alpha: 0.25))),
                  child: const Icon(Icons.login_rounded, color: ChhayaColors.info, size: 26),
                ),
                const SizedBox(width: ChhayaSpacing.space4),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('I Have an Account', style: ChhayaTypography.headlineMedium),
                    const SizedBox(height: ChhayaSpacing.space1),
                    Text('Restore with phrase or backup', style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.labelTertiary)),
                  ]),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: ChhayaColors.labelTertiary),
              ],
            ),
          ),
          const SizedBox(height: ChhayaSpacing.space5),
          Text('Your keys never leave your device. Zero-knowledge.', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.labelQuaternary)),
        ],
      ),
    );
  }

  Widget _pageSignup() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(ChhayaSpacing.space5, ChhayaSpacing.space2, ChhayaSpacing.space5, ChhayaSpacing.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: ChhayaSpacing.space2),
          Row(
            children: [
              ChhayaIconButton(
                icon: Icons.arrow_back_rounded,
                onPressed: () => _pageCtrl.animateToPage(2, duration: ChhayaAnimation.normal, curve: ChhayaAnimation.springCurve),
                size: 40,
                background: ChhayaColors.cardSurface,
              ),
              const SizedBox(width: ChhayaSpacing.space3),
              Text('Create Account', style: ChhayaTypography.displaySmall.copyWith(fontSize: 20)),
            ],
          ),
          const SizedBox(height: ChhayaSpacing.space5),
          ChhayaInput(controller: _nameCtrl, hint: 'Display name', prefixIcon: Icons.person_outline_rounded),
          const SizedBox(height: ChhayaSpacing.space4),
          // ID generation
          if (_generatedId == null)
            ChhayaCard(
              padding: const EdgeInsets.all(ChhayaSpacing.space5),
              child: Column(
                children: [
                  Icon(Icons.fingerprint_rounded, size: 36, color: ChhayaColors.accent.withValues(alpha: 0.8)),
                  const SizedBox(height: ChhayaSpacing.space3),
                  Text('Your Anonymous Identity', style: ChhayaTypography.headlineMedium.copyWith(fontSize: 14)),
                  const SizedBox(height: ChhayaSpacing.space2),
                  Text('Generate a 66-char Chhaya ID. No phone needed.', textAlign: TextAlign.center, style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.labelTertiary)),
                  const SizedBox(height: ChhayaSpacing.space4),
                  ChhayaSecondaryButton(label: 'Generate Chhaya ID', icon: Icons.auto_awesome_rounded, onPressed: _generateId),
                ],
              ),
            )
          else
            GlassContainer(
              padding: const EdgeInsets.all(ChhayaSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 32, height: 32, decoration: BoxDecoration(color: ChhayaColors.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(ChhayaRadius.xl)), child: const Icon(Icons.verified_user_rounded, size: 18, color: ChhayaColors.success)),
                      const SizedBox(width: ChhayaSpacing.space3),
                      Text('Chhaya ID Generated', style: ChhayaTypography.headlineMedium.copyWith(fontSize: 13, color: ChhayaColors.success)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _generatedId!.publicKey));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                          ChhayaHaptics.selection();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space3, vertical: ChhayaSpacing.space1),
                          decoration: BoxDecoration(color: ChhayaColors.fillTertiary, borderRadius: BorderRadius.circular(ChhayaRadius.pill)),
                          child: Row(children: [const Icon(Icons.copy_rounded, size: 14, color: ChhayaColors.labelSecondary), const SizedBox(width: ChhayaSpacing.space1), Text('Copy', style: ChhayaTypography.labelMedium.copyWith(fontSize: 11))]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ChhayaSpacing.space3),
                  Container(
                    padding: const EdgeInsets.all(ChhayaSpacing.space3),
                    decoration: BoxDecoration(color: ChhayaColors.primaryBackground, borderRadius: BorderRadius.circular(ChhayaRadius.xl), border: Border.all(color: ChhayaColors.glassBorder.withValues(alpha: 0.12))),
                    child: Text(_generatedId!.publicKey, style: ChhayaTypography.code.copyWith(color: ChhayaColors.success, fontSize: 11, height: 1.5)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: ChhayaSpacing.space4),
          if (_generatedId != null && _generatedPhrase == null)
            ChhayaPrimaryButton(label: 'Create Account', icon: Icons.shield_rounded, isLoading: _creating, onPressed: _handleCreateAccount)
          else if (_generatedPhrase != null)
            _buildPhraseReveal()
          else
            Opacity(
              opacity: 0.5,
              child: ChhayaPrimaryButton(label: 'Create Account', onPressed: () {}),
            ),
          if (_generatedPhrase == null)
            Padding(
              padding: const EdgeInsets.only(top: ChhayaSpacing.space3),
              child: Center(child: Text('You\'ll get a 12-word recovery phrase next', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.labelQuaternary))),
            ),
        ],
      ),
    );
  }

  Widget _buildPhraseReveal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(ChhayaSpacing.space4),
          decoration: BoxDecoration(color: ChhayaColors.warning.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(ChhayaRadius.xl), border: Border.all(color: ChhayaColors.warning.withValues(alpha: 0.22))),
          child: Row(
            children: [
              const Icon(Icons.warning_rounded, size: 20, color: ChhayaColors.warning),
              const SizedBox(width: ChhayaSpacing.space3),
              Expanded(child: Text('Write these 12 words down. They restore your account.', style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.warning, fontWeight: FontWeight.w600, fontSize: 12))),
            ],
          ),
        ),
        const SizedBox(height: ChhayaSpacing.space4),
        Container(
          padding: const EdgeInsets.all(ChhayaSpacing.space4),
          decoration: BoxDecoration(color: ChhayaColors.cardSurface, borderRadius: BorderRadius.circular(ChhayaRadius.xl), border: Border.all(color: ChhayaColors.opaqueSeparator.withValues(alpha: 0.4))),
          child: Wrap(
            spacing: ChhayaSpacing.space2,
            runSpacing: ChhayaSpacing.space2,
            children: List.generate(_generatedPhrase!.length, (i) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space3, vertical: ChhayaSpacing.space2),
                decoration: BoxDecoration(color: ChhayaColors.secondaryBackground, borderRadius: BorderRadius.circular(ChhayaRadius.xl), border: Border.all(color: ChhayaColors.separator)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${i + 1}.', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.accent, fontWeight: FontWeight.w700)),
                    const SizedBox(width: ChhayaSpacing.space2),
                    Text(_generatedPhrase![i], style: ChhayaTypography.bodyMedium.copyWith(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'JetBrains Mono')),
                  ],
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: ChhayaSpacing.space3),
        Row(
          children: [
            Expanded(
              child: ChhayaSecondaryButton(
                label: _phraseCopied ? 'Copied!' : 'Copy Phrase',
                icon: _phraseCopied ? Icons.check_rounded : Icons.copy_rounded,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _generatedPhrase!.join(' ')));
                  setState(() => _phraseCopied = true);
                  ChhayaHaptics.success();
                  Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _phraseCopied = false); });
                },
                height: 48,
              ),
            ),
            const SizedBox(width: ChhayaSpacing.space3),
            Expanded(
              child: ChhayaPrimaryButton(label: 'Continue →', onPressed: _confirmPhraseAndEnter, height: 48),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pageLogin() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(ChhayaSpacing.space5, ChhayaSpacing.space2, ChhayaSpacing.space5, ChhayaSpacing.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: ChhayaSpacing.space2),
          Row(
            children: [
              ChhayaIconButton(icon: Icons.arrow_back_rounded, onPressed: () => _pageCtrl.animateToPage(2, duration: ChhayaAnimation.normal, curve: ChhayaAnimation.springCurve), size: 40, background: ChhayaColors.cardSurface),
              const SizedBox(width: ChhayaSpacing.space3),
              Text('Welcome Back', style: ChhayaTypography.displaySmall.copyWith(fontSize: 20)),
            ],
          ),
          const SizedBox(height: ChhayaSpacing.space2),
          Text('Restore your Chhaya account securely', style: ChhayaTypography.bodySmall.copyWith(color: ChhayaColors.labelSecondary)),
          const SizedBox(height: ChhayaSpacing.space5),
          Text('Recovery Phrase *', style: ChhayaTypography.labelLarge.copyWith(color: ChhayaColors.labelSecondary, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: ChhayaSpacing.space2),
          TextField(
            controller: _loginPhraseCtrl,
            maxLines: 3,
            minLines: 2,
            obscureText: _loginObscure,
            style: ChhayaTypography.bodyMedium.copyWith(fontFamily: 'JetBrains Mono', fontSize: 13, height: 1.5),
            decoration: InputDecoration(
              hintText: '12 words separated by spaces  •  e.g. abandon ability able ...',
              hintStyle: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.labelQuaternary),
              filled: true,
              fillColor: ChhayaColors.inputSurface,
              suffixIcon: IconButton(
                icon: Icon(_loginObscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18, color: ChhayaColors.labelTertiary),
                onPressed: () => setState(() => _loginObscure = !_loginObscure),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: BorderSide(color: ChhayaColors.glassBorder.withValues(alpha: 0.12))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: BorderSide(color: ChhayaColors.glassBorder.withValues(alpha: 0.12))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: const BorderSide(color: ChhayaColors.accent, width: 1.5)),
              contentPadding: const EdgeInsets.all(ChhayaSpacing.space4),
            ),
          ),
          const SizedBox(height: ChhayaSpacing.space2),
          Text('Must be exactly 12 words. Keep it private.', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.labelQuaternary)),
          const SizedBox(height: ChhayaSpacing.space4),
          Text('Encrypted Backup (optional)', style: ChhayaTypography.labelLarge.copyWith(color: ChhayaColors.labelSecondary, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: ChhayaSpacing.space2),
          TextField(
            controller: _loginBackupCtrl,
            maxLines: 2,
            style: ChhayaTypography.code.copyWith(fontSize: 11, color: ChhayaColors.labelSecondary),
            decoration: InputDecoration(
              hintText: 'Paste backup string if you have one',
              hintStyle: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.labelQuaternary),
              filled: true,
              fillColor: ChhayaColors.inputSurface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: BorderSide(color: ChhayaColors.glassBorder.withValues(alpha: 0.12))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: BorderSide(color: ChhayaColors.glassBorder.withValues(alpha: 0.12))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: const BorderSide(color: ChhayaColors.accent, width: 1.5)),
              contentPadding: const EdgeInsets.all(ChhayaSpacing.space4),
            ),
          ),
          const SizedBox(height: ChhayaSpacing.space5),
          ChhayaPrimaryButton(label: 'Log In & Restore', icon: Icons.lock_open_rounded, isLoading: _loginLoading, onPressed: _handleLogin),
          const SizedBox(height: ChhayaSpacing.space3),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _isLoginMode = false),
              child: Text('Don\'t have an account? Create one', style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.accent, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: ChhayaSpacing.space2),
          Container(
            padding: const EdgeInsets.all(ChhayaSpacing.space3),
            decoration: BoxDecoration(color: ChhayaColors.cardSurface, borderRadius: BorderRadius.circular(ChhayaRadius.xl), border: Border.all(color: ChhayaColors.separator)),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: ChhayaColors.labelTertiary),
                const SizedBox(width: ChhayaSpacing.space3),
                Expanded(child: Text('Log in is local & encrypted. No server sees your phrase.', style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.labelTertiary, fontSize: 11))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Blinking terminal block cursor. Static (visible) under reduced motion.
class _BlinkCursor extends StatefulWidget {
  final bool disabled;
  const _BlinkCursor({required this.disabled});

  @override
  State<_BlinkCursor> createState() => _BlinkCursorState();
}

class _BlinkCursorState extends State<_BlinkCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    );
    if (!widget.disabled) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.disabled) {
      return Container(width: 8, height: 14, color: ChhayaColors.accent);
    }
    return FadeTransition(
      opacity: _ctrl.drive(
        Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
      ),
      child: Container(width: 8, height: 14, color: ChhayaColors.accent),
    );
  }
}