import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/chhaya_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/chhaya_button.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/message.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/router/chhaya_router.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String contactName;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.contactName,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with TickerProviderStateMixin {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Message> _messages = [];
  bool _loading = true;
  bool _isTyping = false;
  bool _otherTyping = false;
  bool _steganoMode = false;
  int _ttlMinutes = 0;
  Timer? _autoReplyTimer;

  late AnimationController _fabCtrl;
  late Animation<double> _fabScale;

  @override
  void initState() {
    super.initState();
    _fabCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _fabScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fabCtrl, curve: ChhayaAnimation.springCurve),
    );
    _msgCtrl.addListener(() {
      final hasText = _msgCtrl.text.trim().isNotEmpty;
      if (hasText != _isTyping) {
        setState(() => _isTyping = hasText);
        if (hasText) _fabCtrl.forward();
      }
    });
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final db = ref.read(localDatabaseProvider);
    final msgs = await db.getMessages(widget.conversationId);
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _autoReplyTimer?.cancel();
    _fabCtrl.dispose();
    super.dispose();
  }

  bool _isSent(Message m) => m.senderId == 'me';

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: ChhayaAnimation.normal,
      curve: ChhayaAnimation.springCurve,
    );
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    final msg = Message(
      id: 'm_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: widget.conversationId,
      senderId: 'me',
      content: text,
      timestamp: DateTime.now(),
      isSent: true,
      isDelivered: true,
      ttl: _ttlMinutes > 0 ? Duration(minutes: _ttlMinutes) : null,
    );

    final db = ref.read(localDatabaseProvider);
    await db.addMessage(msg);

    setState(() => _messages = [..._messages, msg]);
    _msgCtrl.clear();
    setState(() => _isTyping = false);
    _fabCtrl.reverse();
    ChhayaHaptics.medium();
    _scrollToBottom();
    _scheduleAutoReply();
  }

  void _scheduleAutoReply() {
    _autoReplyTimer?.cancel();
    _autoReplyTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _otherTyping = true);
      _scrollToBottom();

      _autoReplyTimer = Timer(const Duration(milliseconds: 2200), () async {
        if (!mounted) return;
        setState(() => _otherTyping = false);
        final contactId = _contactId();
        final reply = Message(
          id: 'm_${DateTime.now().millisecondsSinceEpoch}',
          conversationId: widget.conversationId,
          senderId: contactId,
          content: _autoReplyText(),
          timestamp: DateTime.now(),
          isRead: true,
          isDelivered: true,
        );
        final db = ref.read(localDatabaseProvider);
        await db.addMessage(reply);
        if (!mounted) return;
        setState(() => _messages = [..._messages, reply]);
        _scrollToBottom();
      });
    });
  }

  String _contactId() {
    final convos = ref.read(conversationsProvider);
    final convo = convos.where((c) => c.id == widget.conversationId).firstOrNull;
    if (convo != null && convo.participants.isNotEmpty) return convo.participants.first.id;
    return 'contact';
  }

  String _autoReplyText() {
    const replies = [
      'Got it, thanks!',
      'Sounds good to me.',
      'Onion-routed and received 👍',
      'Let me check and get back to you.',
      'Agreed.',
      'Perfect.',
      'Can we talk about this later?',
      'Interesting — tell me more.',
    ];
    return replies[Random().nextInt(replies.length)];
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final conversations = ref.watch(conversationsProvider);
    final convo = conversations.where((c) => c.id == widget.conversationId).firstOrNull;

    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, convo),
            if (_steganoMode) _buildSteganoBanner(disableAnimations),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: ChhayaColors.accent))
                  : _messages.isEmpty
                      ? _buildEmptyChat()
                      : ListView.builder(
                          controller: _scrollCtrl,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                            ChhayaSpacing.space4,
                            ChhayaSpacing.space3,
                            ChhayaSpacing.space4,
                            ChhayaSpacing.space4,
                          ),
                          itemCount: _messages.length + (_otherTyping ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (i == _messages.length) return _buildTypingIndicator(disableAnimations);
                            return _buildMessageBubble(_messages[i], i);
                          },
                        ),
            ),
            _buildInputBar(disableAnimations),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, Conversation? convo) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ChhayaSpacing.space3,
        vertical: ChhayaSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: ChhayaColors.primaryBackground.withValues(alpha: 0.82),
        border: const Border(
          bottom: BorderSide(color: ChhayaColors.separator, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          ChhayaIconButton(
            icon: Icons.arrow_back_rounded,
            onPressed: () => Navigator.of(context).pop(),
            size: 38,
            background: ChhayaColors.cardSurface,
          ),
          const SizedBox(width: ChhayaSpacing.space2),
          AvatarWidget(
            name: widget.contactName,
            size: 36,
            statusColor: convo?.participants.firstOrNull?.isOnline == true
                ? ChhayaColors.online
                : null,
          ),
          const SizedBox(width: ChhayaSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.contactName,
                  style: ChhayaTypography.headlineMedium.copyWith(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  _ttlMinutes > 0
                      ? 'Disappearing · $_ttlLabel'
                      : 'Onion-secured',
                  style: ChhayaTypography.labelSmall.copyWith(
                    color: _ttlMinutes > 0
                        ? ChhayaColors.warning
                        : ChhayaColors.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          ChhayaIconButton(
            icon: Icons.timer_outlined,
            onPressed: _showTtlSheet,
            size: 36,
            background: _ttlMinutes > 0
                ? ChhayaColors.warning.withValues(alpha: 0.15)
                : ChhayaColors.cardSurface,
            color: _ttlMinutes > 0 ? ChhayaColors.warning : ChhayaColors.labelPrimary,
          ),
          const SizedBox(width: ChhayaSpacing.space1),
          ChhayaIconButton(
            icon: Icons.call_rounded,
            onPressed: () => Navigator.of(context).pushNamed(
              ChhayaRouter.call,
              arguments: {'contactName': widget.contactName, 'isVideo': false},
            ),
            size: 36,
            background: ChhayaColors.cardSurface,
          ),
          const SizedBox(width: ChhayaSpacing.space1),
          ChhayaIconButton(
            icon: Icons.videocam_rounded,
            onPressed: () => Navigator.of(context).pushNamed(
              ChhayaRouter.call,
              arguments: {'contactName': widget.contactName, 'isVideo': true},
            ),
            size: 36,
            background: ChhayaColors.cardSurface,
          ),
        ],
      ),
    );
  }

  String get _ttlLabel {
    if (_ttlMinutes >= 1440) return '${_ttlMinutes ~/ 1440}d';
    if (_ttlMinutes >= 60) return '${_ttlMinutes ~/ 60}h';
    return '$_ttlMinutes min';
  }

  Widget _buildSteganoBanner(bool disableAnimations) {
    return AnimatedContainer(
      duration: disableAnimations ? Duration.zero : ChhayaAnimation.normal,
      curve: ChhayaAnimation.springCurve,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: ChhayaSpacing.space4,
        vertical: ChhayaSpacing.space2,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ChhayaColors.accent.withValues(alpha: 0.18),
            ChhayaColors.info.withValues(alpha: 0.12),
          ],
        ),
        border: const Border(
          bottom: BorderSide(color: ChhayaColors.borderMed, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.visibility_off_rounded, size: 14, color: ChhayaColors.accent),
          const SizedBox(width: ChhayaSpacing.space1),
          Text(
            'STEGANO MODE — messages hidden in images',
            style: ChhayaTypography.labelSmall.copyWith(
              color: ChhayaColors.accent,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ChhayaSpacing.space8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: ChhayaColors.cardSurface,
                borderRadius: BorderRadius.circular(ChhayaRadius.xxl),
                border: Border.all(color: ChhayaColors.glassBorder.withValues(alpha: 0.12)),
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 36,
                color: ChhayaColors.accent.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: ChhayaSpacing.space5),
            Text(
              'End-to-End Encrypted',
              style: ChhayaTypography.headlineMedium.copyWith(fontSize: 15),
            ),
            const SizedBox(height: ChhayaSpacing.space1),
            Text(
              'Messages are onion-routed and encrypted\nwith AES-256-GCM + Double Ratchet.',
              textAlign: TextAlign.center,
              style: ChhayaTypography.bodySmall.copyWith(
                color: ChhayaColors.labelTertiary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Message msg, int index) {
    final isSent = _isSent(msg);
    final showTail = index == 0 || _isSent(_messages[index - 1]) != isSent;
    final timeStr = _formatTime(msg.timestamp);
    final isStegano = _steganoMode && isSent && index == _messages.length - 1;

    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: showTail ? ChhayaSpacing.space3 : ChhayaSpacing.space1,
          left: isSent ? ChhayaSpacing.space8 : 0,
          right: isSent ? 0 : ChhayaSpacing.space8,
        ),
        child: Column(
          crossAxisAlignment: isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ChhayaSpacing.space4,
                vertical: ChhayaSpacing.space3,
              ),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.74,
              ),
              decoration: BoxDecoration(
                gradient: isSent && !isStegano ? ChhayaColors.accentGradient : null,
                color: isSent ? (isStegano ? ChhayaColors.cardSurfaceElevated : null) : ChhayaColors.bubbleReceived,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(ChhayaRadius.lg),
                  topRight: const Radius.circular(ChhayaRadius.lg),
                  bottomLeft: Radius.circular(isSent ? ChhayaRadius.lg : ChhayaRadius.sm),
                  bottomRight: Radius.circular(isSent ? ChhayaRadius.sm : ChhayaRadius.lg),
                ),
                border: isSent && !isStegano
                    ? null
                    : Border.all(
                        color: isStegano
                            ? ChhayaColors.info.withValues(alpha: 0.3)
                            : ChhayaColors.separator,
                        width: 0.6,
                      ),
                boxShadow: isSent && !isStegano && !disableAnimationsSafe
                    ? ChhayaShadows.glowBlue
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isStegano)
                    const Padding(
                      padding: EdgeInsets.only(bottom: ChhayaSpacing.space1),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility_off_rounded, size: 12, color: ChhayaColors.accent),
                          SizedBox(width: 4),
                          Text(
                            'STEGANO',
                            style: TextStyle(
                              color: ChhayaColors.accent,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    msg.content,
                    style: ChhayaTypography.bodyMedium.copyWith(
                      color: isSent && !isStegano ? ChhayaColors.bubbleSentText : ChhayaColors.bubbleReceivedText,
                      fontSize: 14.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ChhayaSpacing.space1),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (msg.ttl != null)
                  const Padding(
                    padding: EdgeInsets.only(right: ChhayaSpacing.space1),
                    child: Icon(Icons.timer_outlined, size: 11, color: ChhayaColors.labelQuaternary),
                  ),
                Text(
                  timeStr,
                  style: ChhayaTypography.labelSmall.copyWith(
                    color: isSent
                        ? ChhayaColors.labelPrimary.withValues(alpha: 0.6)
                        : ChhayaColors.labelTertiary,
                    fontSize: 10,
                  ),
                ),
                if (isSent) ...[
                  const SizedBox(width: 3),
                  Icon(
                    msg.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 13,
                    color: msg.isRead
                        ? ChhayaColors.accent
                        : ChhayaColors.labelPrimary.withValues(alpha: 0.5),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get disableAnimationsSafe =>
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  Widget _buildTypingIndicator(bool disableAnimations) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: ChhayaSpacing.space3),
        padding: const EdgeInsets.symmetric(
          horizontal: ChhayaSpacing.space4,
          vertical: ChhayaSpacing.space3,
        ),
        decoration: BoxDecoration(
          color: ChhayaColors.bubbleReceived,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(ChhayaRadius.lg),
            topRight: Radius.circular(ChhayaRadius.lg),
            bottomRight: Radius.circular(ChhayaRadius.lg),
            bottomLeft: Radius.circular(ChhayaRadius.sm),
          ),
          border: Border.all(color: ChhayaColors.separator, width: 0.6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return AnimatedContainer(
              duration: disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 500),
              margin: EdgeInsets.only(right: i < 2 ? 5 : 0),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: ChhayaColors.accent.withValues(alpha: 0.3 + (i * 0.25)),
                shape: BoxShape.circle,
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildInputBar(bool disableAnimations) {
    return Container(
      padding: EdgeInsets.only(
        left: ChhayaSpacing.space3,
        right: ChhayaSpacing.space3,
        top: ChhayaSpacing.space2,
        bottom: MediaQuery.of(context).viewInsets.bottom + ChhayaSpacing.space3,
      ),
      decoration: const BoxDecoration(
        color: ChhayaColors.secondaryBackground,
        border: Border(
          top: BorderSide(color: ChhayaColors.separator, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ChhayaIconButton(
            icon: Icons.add_rounded,
            onPressed: _showAttachmentSheet,
            size: 42,
            background: ChhayaColors.cardSurface,
          ),
          const SizedBox(width: ChhayaSpacing.space2),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: ChhayaColors.inputSurface,
                borderRadius: BorderRadius.circular(ChhayaRadius.xl),
                border: Border.all(
                  color: _isTyping
                      ? ChhayaColors.accent.withValues(alpha: 0.4)
                      : ChhayaColors.glassBorder.withValues(alpha: 0.12),
                  width: _isTyping ? 1.2 : 1,
                ),
              ),
              child: TextField(
                controller: _msgCtrl,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: ChhayaTypography.bodyMedium.copyWith(fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: _steganoMode ? 'Hidden message…' : 'Message…',
                  hintStyle: ChhayaTypography.bodyMedium.copyWith(
                    color: ChhayaColors.labelQuaternary,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: ChhayaSpacing.space4,
                    vertical: ChhayaSpacing.space3,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: ChhayaSpacing.space2),
          AnimatedBuilder(
            animation: _fabScale,
            builder: (context, child) {
              return Transform.scale(
                scale: disableAnimations ? 1.0 : _fabScale.value,
                child: child!,
              );
            },
            child: ChhayaIconButton(
              icon: _isTyping ? Icons.arrow_upward_rounded : Icons.mic_rounded,
              onPressed: _isTyping ? _sendMessage : () {},
              size: 42,
              background: ChhayaColors.accent,
              color: ChhayaColors.onAccent,
            ),
          ),
        ],
      ),
    );
  }

  void _showTtlSheet() {
    const options = [0, 1, 5, 30, 60, 1440];
    showModalBottomSheet(
      context: context,
      backgroundColor: ChhayaColors.sheetBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(ChhayaSpacing.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Disappearing Messages', style: ChhayaTypography.displaySmall.copyWith(fontSize: 18)),
            const SizedBox(height: ChhayaSpacing.space1),
            Text('Auto-delete after timer expires', style: ChhayaTypography.labelMedium),
            const SizedBox(height: ChhayaSpacing.space4),
            ...options.map((m) {
              final label = m == 0
                  ? 'Off'
                  : m == 1440
                      ? '24 hours'
                      : '$m minute${m > 1 ? 's' : ''}';
              final selected = _ttlMinutes == m;
              return ListTile(
                dense: true,
                title: Text(label, style: ChhayaTypography.bodyMedium),
                trailing: selected
                    ? const Icon(Icons.check_circle_rounded, color: ChhayaColors.accent, size: 20)
                    : null,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChhayaRadius.md)),
                onTap: () {
                  setState(() => _ttlMinutes = m);
                  ChhayaHaptics.selection();
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: ChhayaColors.sheetBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(ChhayaSpacing.space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Attach', style: ChhayaTypography.headlineMedium),
              const SizedBox(height: ChhayaSpacing.space4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _attachAction(Icons.camera_alt_rounded, 'Camera', ChhayaColors.accent, () {}),
                  _attachAction(Icons.photo_rounded, 'Gallery', ChhayaColors.success, () {}),
                  _attachAction(Icons.insert_drive_file_rounded, 'File', ChhayaColors.info, () {}),
                  _attachAction(Icons.how_to_vote_rounded, 'Poll', ChhayaColors.warning, () {}),
                ],
              ),
              const SizedBox(height: ChhayaSpacing.space4),
              Container(
                decoration: BoxDecoration(
                  color: ChhayaColors.cardSurface,
                  borderRadius: BorderRadius.circular(ChhayaRadius.lg),
                  border: Border.all(color: ChhayaColors.separator),
                ),
                child: SwitchListTile(
                  secondary: const Icon(Icons.visibility_off_rounded, color: ChhayaColors.accent, size: 20),
                  title: Text('Stegano Mode', style: ChhayaTypography.bodyMedium),
                  subtitle: Text(
                    'Hide messages inside images',
                    style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.labelTertiary),
                  ),
                  value: _steganoMode,
                  onChanged: (v) {
                    setSheetState(() => _steganoMode = v);
                    setState(() => _steganoMode = v);
                    ChhayaHaptics.selection();
                  },
                  activeTrackColor: ChhayaColors.accent.withValues(alpha: 0.3),
                  activeThumbColor: ChhayaColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            ChhayaHaptics.light();
            Navigator.pop(context);
            onTap();
          },
          customBorder: const CircleBorder(),
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
        ),
        const SizedBox(height: ChhayaSpacing.space1),
        Text(label, style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.labelTertiary)),
      ],
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}