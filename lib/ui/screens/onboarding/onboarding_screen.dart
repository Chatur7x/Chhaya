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

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;
  ChhayaId? _generatedId;
  bool _creating = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageCtrl.animateToPage(_currentPage + 1, duration: ChhayaAnimation.normal, curve: ChhayaAnimation.springCurve);
    }
  }

  void _generateId() {
    setState(() => _generatedId = ChhayaId.generate());
    ChhayaHaptics.medium();
  }

  Future<void> _getStarted() async {
    if (_creating) return;
    setState(() => _creating = true);

    try {
      final auth = ref.read(authServiceProvider);
      final profile = await auth.createAccount(displayName: 'Chhaya User');
      ref.read(currentUserProvider.notifier).state = profile;

      final db = ref.read(localDatabaseProvider);
      final convos = await db.getAllConversations();
      final contacts = await db.getAllContacts();
      ref.read(conversationsProvider.notifier).setConversations(convos);
      ref.read(contactsProvider.notifier).setContacts(contacts);

      if (mounted) Navigator.of(context).pushReplacementNamed(ChhayaRouter.home);
    } catch (e) {
      setState(() => _creating = false);
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Error'),
            content: Text(e.toString()),
            actions: [TextButton(child: const Text('OK'), onPressed: () => Navigator.pop(context))],
          ),
        );
      }
    }
  }

  void _showRestoreBackup() {
    final backupCtrl = TextEditingController();
    final phraseCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore from Backup'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your backup string and recovery phrase.', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(controller: backupCtrl, decoration: const InputDecoration(hintText: 'Paste backup here'), maxLines: 2),
              const SizedBox(height: 8),
              TextField(controller: phraseCtrl, decoration: const InputDecoration(hintText: '12-word recovery phrase')),
            ],
          ),
        ),
        actions: [
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
          TextButton(
            child: const Text('Restore'),
            onPressed: () async {
              Navigator.pop(context);
              if (backupCtrl.text.trim().isEmpty || phraseCtrl.text.trim().isEmpty) return;
              try {
                final auth = ref.read(authServiceProvider);
                final words = phraseCtrl.text.trim().split(' ');
                final success = await auth.restoreFromBackup(backupCtrl.text.trim(), words);
                if (success) {
                  final profile = auth.currentUser;
                  if (profile != null) {
                    ref.read(currentUserProvider.notifier).state = profile;
                    final db = ref.read(localDatabaseProvider);
                    final convos = await db.getAllConversations();
                    final contacts = await db.getAllContacts();
                    ref.read(conversationsProvider.notifier).setConversations(convos);
                    ref.read(contactsProvider.notifier).setContacts(contacts);
                    if (mounted) Navigator.of(context).pushReplacementNamed(ChhayaRouter.home);
                  }
                } else {
                  if (mounted) {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Restore Failed'),
                        content: const Text('Invalid backup or recovery phrase.'),
                        actions: [TextButton(child: const Text('OK'), onPressed: () => Navigator.pop(context))],
                      ),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Restore Failed'),
                      content: Text(e.toString()),
                      actions: [TextButton(child: const Text('OK'), onPressed: () => Navigator.pop(context))],
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _currentPage = i),
                physics: const BouncingScrollPhysics(),
                children: [_page1(), _page2(), _page3()],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: DotsIndicator(count: 3, current: _currentPage),
            ),
          ],
        ),
      ),
    );
  }

  Widget _page1() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: ChhayaColors.accentGradient,
              boxShadow: [BoxShadow(color: ChhayaColors.accentBlue.withValues(alpha: 0.4), blurRadius: 40, spreadRadius: 5)],
            ),
            child: const Icon(Icons.shield, size: 60, color: ChhayaColors.labelPrimary),
          ),
          const SizedBox(height: 40),
          Text('Welcome to Chhaya', style: ChhayaTypography.largeTitle),
          const SizedBox(height: 12),
          Text('Privacy Redefined', style: ChhayaTypography.title3.copyWith(color: ChhayaColors.accentBlue)),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ChhayaPrimaryButton(
              label: 'Continue',
              onPressed: _nextPage,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _showRestoreBackup,
            child: Text('Restore from Backup', style: ChhayaTypography.body.copyWith(color: ChhayaColors.labelSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _page2() {
    final features = [
      {'icon': Icons.lock, 'title': 'End-to-End Encrypted', 'desc': 'Double Ratchet protocol with forward secrecy', 'color': ChhayaColors.accentGreen},
      {'icon': Icons.person_off, 'title': 'No Phone Number', 'desc': 'Anonymous Chhaya ID identity', 'color': ChhayaColors.accentBlue},
      {'icon': Icons.public, 'title': 'Decentralized', 'desc': 'Onion-routed through 3 anonymous hops', 'color': ChhayaColors.accentPurple},
      {'icon': Icons.photo, 'title': 'Steganographic Messaging', 'desc': 'Hide messages inside images', 'color': ChhayaColors.accentOrange},
    ];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Why Chhaya?', style: ChhayaTypography.title1),
          const SizedBox(height: 24),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassContainer(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: (f['color'] as Color).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                  child: Icon(f['icon'] as IconData, color: f['color'] as Color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f['title'] as String, style: ChhayaTypography.headline),
                  Text(f['desc'] as String, style: ChhayaTypography.caption1.copyWith(color: ChhayaColors.labelTertiary)),
                ])),
              ]),
            ),
          )),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ChhayaPrimaryButton(
              label: 'Next',
              onPressed: _nextPage,
            ),
          ),
        ],
      ),
    );
  }

  Widget _page3() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Your Identity', style: ChhayaTypography.title1),
          const SizedBox(height: 8),
          Text('Generate your unique Chhaya ID', style: ChhayaTypography.body.copyWith(color: ChhayaColors.labelSecondary)),
          const SizedBox(height: 24),

          if (_generatedId != null)
            GlassContainer(
              child: Column(children: [
                Text('Your Chhaya ID', style: ChhayaTypography.footnote.copyWith(color: ChhayaColors.labelTertiary)),
                const SizedBox(height: 8),
                Text(
                  _generatedId!.publicKey,
                  style: ChhayaTypography.caption1.copyWith(fontFamily: 'Courier', color: ChhayaColors.accentGreen),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _generatedId!.publicKey));
                    ChhayaHaptics.selection();
                  },
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.copy, size: 16, color: ChhayaColors.accentBlue),
                    const SizedBox(width: 4),
                    Text('Copy ID', style: ChhayaTypography.caption1.copyWith(color: ChhayaColors.accentBlue)),
                  ]),
                ),
              ]),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ChhayaSecondaryButton(
                label: 'Generate Chhaya ID',
                onPressed: _generateId,
              ),
            ),

          const SizedBox(height: 32),

          if (_generatedId != null)
            SizedBox(
              width: double.infinity,
              child: ChhayaPrimaryButton(
                label: 'Get Started',
                onPressed: _getStarted,
                isLoading: _creating,
              ),
            ),
        ],
      ),
    );
  }
}

class DotsIndicator extends StatelessWidget {
  final int count;
  final int current;

  const DotsIndicator({super.key, required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) => AnimatedContainer(
        duration: ChhayaAnimation.fast,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: i == current ? 24 : 8,
        height: 8,
        decoration: BoxDecoration(
          color: i == current ? ChhayaColors.accentBlue : ChhayaColors.fillTertiary,
          borderRadius: BorderRadius.circular(4),
        ),
      )),
    );
  }
}
