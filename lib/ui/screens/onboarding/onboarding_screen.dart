import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/chhaya_theme.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/chhaya_brand_mark.dart';
import '../../widgets/chhaya_button.dart';
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
      backgroundColor: ChhayaPalette.of(context).primaryBackground,
      body: Stack(
        children: [
          // Aurora glow background
          Positioned(
            top: -120,
            left: -80,
            right: -80,
            height: 380,
            child: Container(
              decoration: BoxDecoration(gradient: ChhayaPalette.of(context).glowGradient),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(padding:const EdgeInsets.symmetric(horizontal:24,vertical:8),
                  child:Row(children:[
                    Icon(Icons.lock_outline,size:20,color:ChhayaPalette.of(context).accent),
                    const SizedBox(width:8),
                    Expanded(child:Text('Your space. Your identity.',style:ChhayaType.of(context).caption)),
                    if(_currentPage<3) TextButton(onPressed:()=>_goToAuth(false),child:const Text('Skip')),
                  ]),
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
            color: isActive ? ChhayaPalette.of(context).accent : isPast ? ChhayaPalette.of(context).info.withValues(alpha: 0.5) : ChhayaPalette.of(context).fillTertiary,
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
        Row(children:[
          const ChhayaBrandMark(size:56),
          const SizedBox(width:20),
          Expanded(child:Text('CHHAYA',style:ChhayaType.of(context).displaySmall.copyWith(color:ChhayaPalette.of(context).accent))),
        ]),
        const SizedBox(height:40),
        Text('A quieter place\nto stay close.',style:ChhayaType.of(context).displayL),
        const SizedBox(height:20),
        Text('No phone number. No email. Just an identity you control, and the people you choose.',
          style:ChhayaType.of(context).bodyLarge.copyWith(color:ChhayaPalette.of(context).inkMuted)),
        const SizedBox(height:32),
        ChhayaPrimaryButton(label:'Get Started',icon:Icons.arrow_forward_rounded,onPressed:_nextPage),
        const SizedBox(height:12),
        Center(child:ChhayaGhostButton(label:'Restore an account',onPressed:()=>_goToAuth(true))),
      ],
    )),
  );

  Widget _pageFeatures() => ListView(padding:const EdgeInsets.all(28),children:[
    Text('Make it personal.\nKeep it private.',style:ChhayaType.of(context).displayMedium),
    const SizedBox(height:24),
    for(final feature in [
      (Icons.person_outline,'Your own identity','Create an account without a phone number or email.'),
      (Icons.verified_user_outlined,'Know who you’re talking to','Compare a full ID or scan a QR code before messaging.'),
      (Icons.lock_outline,'Encrypted direct messages','Messages are encrypted on your device before sending.'),
      (Icons.dns_outlined,'Connect on your terms','Both people connect to the same deployed Chhaya server.'),
    ]) Padding(padding:const EdgeInsets.only(bottom:24),child:Row(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
        Icon(feature.$1,size:24,color:ChhayaPalette.of(context).accent),
        const SizedBox(width:16),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(feature.$2,style:ChhayaType.of(context).title),
          const SizedBox(height:8),
          Text(feature.$3,style:ChhayaType.of(context).bodyLarge.copyWith(color:ChhayaPalette.of(context).inkMuted)),
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
          Text('Welcome', style: ChhayaType.of(context).displaySmall),
          const SizedBox(height: ChhayaSpacing.space2),
          Text('Choose how you want to enter Chhaya', style: ChhayaType.of(context).bodySmall.copyWith(color: ChhayaPalette.of(context).labelSecondary)),
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
                  decoration: BoxDecoration(gradient: ChhayaPalette.of(context).accentGradient, borderRadius: BorderRadius.circular(ChhayaRadius.xl)),
                  child: Icon(Icons.person_add_rounded, color: ChhayaPalette.of(context).onAccent, size: 26),
                ),
                const SizedBox(width: ChhayaSpacing.space4),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Create New Account', style: ChhayaType.of(context).headlineMedium),
                    const SizedBox(height: ChhayaSpacing.space1),
                    Text('Generate Chhaya ID + recovery phrase', style: ChhayaType.of(context).labelMedium.copyWith(color: ChhayaPalette.of(context).labelTertiary)),
                  ]),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 14, color: ChhayaPalette.of(context).labelTertiary),
              ],
            ),
          ),
          const SizedBox(height: ChhayaSpacing.space4),
          ChhayaCard(
            onTap: () => _goToAuth(true),
            padding: const EdgeInsets.all(ChhayaSpacing.space5),
            radius: ChhayaRadius.xxl,
            color: ChhayaPalette.of(context).secondaryBackground,
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: ChhayaPalette.of(context).info.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(ChhayaRadius.xl), border: Border.all(color: ChhayaPalette.of(context).info.withValues(alpha: 0.25))),
                  child: Icon(Icons.login_rounded, color: ChhayaPalette.of(context).info, size: 26),
                ),
                const SizedBox(width: ChhayaSpacing.space4),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('I Have an Account', style: ChhayaType.of(context).headlineMedium),
                    const SizedBox(height: ChhayaSpacing.space1),
                    Text('Restore with phrase or backup', style: ChhayaType.of(context).labelMedium.copyWith(color: ChhayaPalette.of(context).labelTertiary)),
                  ]),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 14, color: ChhayaPalette.of(context).labelTertiary),
              ],
            ),
          ),
          const SizedBox(height: ChhayaSpacing.space5),
          Text('Save your recovery words somewhere only you can access.', style: ChhayaType.of(context).labelSmall.copyWith(color: ChhayaPalette.of(context).labelQuaternary)),
        ],
      ),
    );
  }

  Widget _pageSignup() => ListView(padding:const EdgeInsets.all(24),children:[
    Align(alignment:AlignmentDirectional.centerStart,child:IconButton(
      tooltip:'Back',icon:const Icon(Icons.arrow_back),
      onPressed:()=>_pageCtrl.animateToPage(2,duration:ChhayaAnimation.normal,curve:Curves.easeOut))),
    const SizedBox(height:16),
    Text('Make yourself at home.',style:ChhayaType.of(context).displayMedium),
    const SizedBox(height:16),
    Text('Choose a name your contacts will recognize. Your identity and recovery words are created together.',
      style:ChhayaType.of(context).bodyLarge.copyWith(color:ChhayaPalette.of(context).inkMuted)),
    const SizedBox(height:24),
    if(_generatedPhrase==null) ...[
      ChhayaInput(controller:_nameCtrl,hint:'Your name',label:'Display name',
        textCapitalization:TextCapitalization.words,prefixIcon:Icons.person_outline),
      const SizedBox(height:24),
      ChhayaPrimaryButton(label:'Create account',isLoading:_creating,onPressed:_handleCreateAccount),
    ] else _buildPhraseReveal(),
  ]);

  Widget _buildPhraseReveal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(ChhayaSpacing.space4),
          decoration: BoxDecoration(color: ChhayaPalette.of(context).warning.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(ChhayaRadius.xl), border: Border.all(color: ChhayaPalette.of(context).warning.withValues(alpha: 0.22))),
          child: Row(
            children: [
              Icon(Icons.warning_rounded, size: 20, color: ChhayaPalette.of(context).warning),
              const SizedBox(width: ChhayaSpacing.space3),
              Expanded(child: Text('Write these 12 words down. They restore your account.', style: ChhayaType.of(context).labelMedium.copyWith(color: ChhayaPalette.of(context).warning, fontWeight: FontWeight.w600, fontSize: 12))),
            ],
          ),
        ),
        const SizedBox(height: ChhayaSpacing.space4),
        Container(
          padding: const EdgeInsets.all(ChhayaSpacing.space4),
          decoration: BoxDecoration(color: ChhayaPalette.of(context).cardSurface, borderRadius: BorderRadius.circular(ChhayaRadius.xl), border: Border.all(color: ChhayaPalette.of(context).opaqueSeparator.withValues(alpha: 0.4))),
          child: Wrap(
            spacing: ChhayaSpacing.space2,
            runSpacing: ChhayaSpacing.space2,
            children: List.generate(_generatedPhrase!.length, (i) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space3, vertical: ChhayaSpacing.space2),
                decoration: BoxDecoration(color: ChhayaPalette.of(context).secondaryBackground, borderRadius: BorderRadius.circular(ChhayaRadius.xl), border: Border.all(color: ChhayaPalette.of(context).separator)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${i + 1}.', style: ChhayaType.of(context).labelSmall.copyWith(color: ChhayaPalette.of(context).accent, fontWeight: FontWeight.w700)),
                    const SizedBox(width: ChhayaSpacing.space2),
                    Text(_generatedPhrase![i], style: ChhayaType.of(context).bodyMedium.copyWith(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'RobotoMono')),
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
              ChhayaIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onPressed: () => _pageCtrl.animateToPage(2, duration: ChhayaAnimation.normal, curve: ChhayaAnimation.springCurve), size: 40, background: ChhayaPalette.of(context).cardSurface),
              const SizedBox(width: ChhayaSpacing.space3),
              Expanded(child:Text('Welcome Back', style: ChhayaType.of(context).displaySmall.copyWith(fontSize: 20))),
            ],
          ),
          const SizedBox(height: ChhayaSpacing.space2),
          Text('Restore your Chhaya account securely', style: ChhayaType.of(context).bodySmall.copyWith(color: ChhayaPalette.of(context).labelSecondary)),
          const SizedBox(height: ChhayaSpacing.space5),
          Text('Recovery Phrase *', style: ChhayaType.of(context).labelLarge.copyWith(color: ChhayaPalette.of(context).labelSecondary, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: ChhayaSpacing.space2),
          TextField(
            controller: _loginPhraseCtrl,
            maxLines: _loginObscure ? 1 : 3,
            minLines: _loginObscure ? 1 : 2,
            obscureText: _loginObscure,
            autocorrect: false,
            enableSuggestions: false,
            style: ChhayaType.of(context).bodyMedium.copyWith(fontFamily: 'RobotoMono', fontSize: 13, height: 1.5),
            decoration: InputDecoration(
              hintText: '12 words separated by spaces  •  e.g. abandon ability able ...',
              hintStyle: ChhayaType.of(context).labelMedium.copyWith(color: ChhayaPalette.of(context).labelQuaternary),
              filled: true,
              fillColor: ChhayaPalette.of(context).inputSurface,
              suffixIcon: IconButton(
                tooltip: _loginObscure ? 'Show recovery phrase' : 'Hide recovery phrase',
                icon: Icon(_loginObscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18, color: ChhayaPalette.of(context).labelTertiary),
                onPressed: () => setState(() => _loginObscure = !_loginObscure),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: BorderSide(color: ChhayaPalette.of(context).glassBorder.withValues(alpha: 0.12))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: BorderSide(color: ChhayaPalette.of(context).glassBorder.withValues(alpha: 0.12))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: BorderSide(color: ChhayaPalette.of(context).accent, width: 1.5)),
              contentPadding: const EdgeInsets.all(ChhayaSpacing.space4),
            ),
          ),
          const SizedBox(height: ChhayaSpacing.space2),
          Text('Must be exactly 12 words. Keep it private.', style: ChhayaType.of(context).labelSmall.copyWith(color: ChhayaPalette.of(context).labelQuaternary)),
          const SizedBox(height: ChhayaSpacing.space4),
          Text('Encrypted Backup (optional)', style: ChhayaType.of(context).labelLarge.copyWith(color: ChhayaPalette.of(context).labelSecondary, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: ChhayaSpacing.space2),
          TextField(
            controller: _loginBackupCtrl,
            maxLines: 2,
            style: ChhayaType.of(context).code.copyWith(fontSize: 11, color: ChhayaPalette.of(context).labelSecondary),
            decoration: InputDecoration(
              hintText: 'Paste backup string if you have one',
              hintStyle: ChhayaType.of(context).labelMedium.copyWith(color: ChhayaPalette.of(context).labelQuaternary),
              filled: true,
              fillColor: ChhayaPalette.of(context).inputSurface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: BorderSide(color: ChhayaPalette.of(context).glassBorder.withValues(alpha: 0.12))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: BorderSide(color: ChhayaPalette.of(context).glassBorder.withValues(alpha: 0.12))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: BorderSide(color: ChhayaPalette.of(context).accent, width: 1.5)),
              contentPadding: const EdgeInsets.all(ChhayaSpacing.space4),
            ),
          ),
          const SizedBox(height: ChhayaSpacing.space5),
          ChhayaPrimaryButton(label: 'Log In & Restore', icon: Icons.lock_open_rounded, isLoading: _loginLoading, onPressed: _handleLogin),
          const SizedBox(height: ChhayaSpacing.space3),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _isLoginMode = false),
              child: Text('Don\'t have an account? Create one', style: ChhayaType.of(context).labelMedium.copyWith(color: ChhayaPalette.of(context).accent, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: ChhayaSpacing.space2),
          Container(
            padding: const EdgeInsets.all(ChhayaSpacing.space3),
            decoration: BoxDecoration(color: ChhayaPalette.of(context).cardSurface, borderRadius: BorderRadius.circular(ChhayaRadius.xl), border: Border.all(color: ChhayaPalette.of(context).separator)),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: ChhayaPalette.of(context).labelTertiary),
                const SizedBox(width: ChhayaSpacing.space3),
                Expanded(child: Text('Log in is local & encrypted. No server sees your phrase.', style: ChhayaType.of(context).labelMedium.copyWith(color: ChhayaPalette.of(context).labelTertiary, fontSize: 11))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
