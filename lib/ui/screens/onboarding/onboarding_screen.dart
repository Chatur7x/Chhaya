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
      if (!mounted) return;
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

  Widget _pageWelcome() => SingleChildScrollView(
    padding:const EdgeInsets.fromLTRB(28,32,28,24),
    child:FadeTransition(opacity:disableAnimations?const AlwaysStoppedAnimation(1.0):_heroFadeAnim,child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
        Container(width:72,height:72,decoration:BoxDecoration(
          color:ChhayaColors.coralTint,borderRadius:BorderRadius.circular(20)),
          child:const Icon(Icons.chat_bubble_outline_rounded,size:36,color:ChhayaColors.accent)),
        const SizedBox(height:32),
        Text('CHHAYA',style:ChhayaTypography.title.copyWith(color:ChhayaColors.accent)),
        const SizedBox(height:16),
        Text('A quieter place\nto stay close.',style:ChhayaTypography.displayL),
        const SizedBox(height:20),
        Text('No phone number. No email. Just an identity you control, and the people you choose.',
          style:ChhayaTypography.bodyLarge.copyWith(color:ChhayaColors.inkMuted)),
        const SizedBox(height:32),
        ChhayaPrimaryButton(label:'Get Started',icon:Icons.arrow_forward_rounded,onPressed:_nextPage),
        const SizedBox(height:12),
        Center(child:ChhayaGhostButton(label:'Restore an account',onPressed:()=>_goToAuth(true))),
      ],
    )),
  );

  Widget _pageFeatures() => ListView(padding:const EdgeInsets.all(28),children:[
    Text('Make it personal.\nKeep it private.',style:ChhayaTypography.displayMedium),
    const SizedBox(height:24),
    for(final feature in [
      (Icons.person_outline,'Your own identity','Create an account without a phone number or email.'),
      (Icons.verified_user_outlined,'Know who you’re talking to','Compare a full ID or scan a QR code before messaging.'),
      (Icons.lock_outline,'Encrypted direct messages','Messages are encrypted on your device before sending.'),
      (Icons.dns_outlined,'Connect on your terms','Both people connect to the same deployed Chhaya server.'),
    ]) Padding(padding:const EdgeInsets.only(bottom:24),child:Row(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
        Icon(feature.$1,size:24,color:ChhayaColors.accent),
        const SizedBox(width:16),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(feature.$2,style:ChhayaTypography.title),
          const SizedBox(height:8),
          Text(feature.$3,style:ChhayaTypography.bodyLarge.copyWith(color:ChhayaColors.inkMuted)),
        ])),
      ],
    )),
    ChhayaPrimaryButton(label:'Continue',onPressed:_nextPage),
  ]);

  Widget _pageAuthChoice() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(ChhayaSpacing.space5, ChhayaSpacing.space4, ChhayaSpacing.space5, ChhayaSpacing.space5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
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
