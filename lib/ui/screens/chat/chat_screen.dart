import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import '../../theme/chhaya_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/glass_container.dart';
import '../../../core/router/chhaya_router.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/models/message.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String contactName;
  final String? contactAvatar;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.contactName,
    this.contactAvatar,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();
  List<Message> _messages = [];
  bool _loading = true;
  bool _isTyping = false;
  bool _hasText = false;
  bool _steganoMode = false;
  Duration? _currentTtl;
  final Map<String, Timer> _ttlTimers = {};

  final Map<String, int> _pollVotes = {};
  late AnimationController _typingDotCtrl;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _msgCtrl.addListener(() {
      final ht = _msgCtrl.text.trim().isNotEmpty;
      if (ht != _hasText) setState(() => _hasText = ht);
    });
    final db = ref.read(localDatabaseProvider);
    final ttlSecs = db.getConversationTtl(widget.conversationId);
    if (ttlSecs > 0) _currentTtl = Duration(seconds: ttlSecs);

    _typingDotCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _typingDotCtrl.dispose();
    for (final t in _ttlTimers.values) t.cancel();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final db = ref.read(localDatabaseProvider);
    final list = await db.getMessages(widget.conversationId);
    final now = DateTime.now();
    final active = <Message>[];
    for (final m in list) {
      if (m.ttl != null) {
        final exp = m.timestamp.add(m.ttl!);
        if (exp.isBefore(now)) {
          await db.deleteMessage(m.id);
        } else {
          active.add(m);
          _startTtl(m, exp.difference(now));
        }
      } else {
        active.add(m);
      }
    }
    if (mounted) {
      setState(() { _messages = active; _loading = false; });
      _scrollToBottom(immediate: true);
    }
  }

  void _startTtl(Message msg, Duration dur) {
    _ttlTimers[msg.id]?.cancel();
    _ttlTimers[msg.id] = Timer(dur, () async {
      await ref.read(localDatabaseProvider).deleteMessage(msg.id);
      if (mounted) setState(() => _messages.removeWhere((m) => m.id == msg.id));
      _ttlTimers.remove(msg.id);
    });
  }

  void _scrollToBottom({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        if (immediate) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        else _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: ChhayaAnimation.normal, curve: ChhayaAnimation.springCurve);
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    if (_steganoMode) {
      await _sendGeneric('STEG:${base64Encode(utf8.encode(text))}', MessageType.image);
    } else {
      await _sendGeneric(text, MessageType.text);
    }
  }

  Future<void> _sendGeneric(String content, MessageType type) async {
    ChhayaHaptics.light();
    final db = ref.read(localDatabaseProvider);
    final router = ref.read(onionRouterProvider);

    final msg = Message(
      id: const Uuid().v4(),
      conversationId: widget.conversationId,
      senderId: 'me',
      content: content,
      type: type,
      timestamp: DateTime.now(),
      isSent: true,
      isDelivered: false,
      isRead: false,
      ttl: _currentTtl,
    );

    setState(() => _messages.add(msg));
    _scrollToBottom();
    await db.addMessage(msg);


    final convos = ref.read(conversationsProvider);
    final idx = convos.indexWhere((c) => c.id == widget.conversationId);
    if (idx != -1) {
      final updated = convos[idx].copyWith(lastMessage: msg, unreadCount: 0);
      ref.read(conversationsProvider.notifier).updateConversation(updated);
      await db.updateConversation(updated);
    }

    if (_currentTtl != null) _startTtl(msg, _currentTtl!);


    final success = await router.routeMessage(msg, Uint8List.fromList([1, 2, 3]));
    if (success) {
      final delivered = msg.copyWith(isDelivered: true, isRead: true);
      await db.addMessage(delivered);
      if (mounted) {
        setState(() {
          final i = _messages.indexWhere((m) => m.id == msg.id);
          if (i != -1) _messages[i] = delivered;
        });
      }
      _triggerReply();
    }
  }

  void _triggerReply() {
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) { setState(() => _isTyping = true); _scrollToBottom(); }
      Timer(const Duration(seconds: 2), () async {
        if (mounted) setState(() => _isTyping = false);
        final replies = [
          "Onion routing confirmed ✅ Tunnel secure.",
          "Layer 1 decrypted. Double Ratchet keys advanced. 🔑",
          "File chunks distributed across 3 swarm nodes.",
          "Message will self-destruct shortly ⏱️",
          "Received! Verifying signature... ✅",
        ];
        final reply = Message(
          id: const Uuid().v4(),
          conversationId: widget.conversationId,
          senderId: 'contact',
          content: replies[DateTime.now().second % replies.length],
          timestamp: DateTime.now(),
          isSent: true, isDelivered: true, isRead: true,
          ttl: _currentTtl,
        );

        final db = ref.read(localDatabaseProvider);
        await db.addMessage(reply);
        final convos = ref.read(conversationsProvider);
        final idx = convos.indexWhere((c) => c.id == widget.conversationId);
        if (idx != -1) {
          final updated = convos[idx].copyWith(lastMessage: reply);
          ref.read(conversationsProvider.notifier).updateConversation(updated);
          await db.updateConversation(updated);
        }
        if (_currentTtl != null) _startTtl(reply, _currentTtl!);
        if (mounted) { setState(() => _messages.add(reply)); _scrollToBottom(); ChhayaHaptics.medium(); }
      });
    });
  }

  void _showTtlSelector() {
    final options = {
      'Off': 0, '5 seconds': 5, '30 seconds': 30,
      '1 minute': 60, '1 hour': 3600, '1 day': 86400, '1 week': 604800,
    };
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Disappearing Messages'),
        actions: options.entries.map((e) => CupertinoActionSheetAction(
          onPressed: () async {
            Navigator.pop(context);
            final db = ref.read(localDatabaseProvider);
            await db.setConversationTtl(widget.conversationId, e.value);
            setState(() => _currentTtl = e.value == 0 ? null : Duration(seconds: e.value));
            ChhayaHaptics.selection();
          },
          child: Text(e.key, style: TextStyle(color: e.value == (_currentTtl?.inSeconds ?? 0) ? ChhayaColors.accentBlue : ChhayaColors.labelPrimary)),
        )).toList(),
        cancelButton: CupertinoActionSheetAction(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
      ),
    );
  }

  void _showAttachments() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            child: const Text('📷 Camera'),
            onPressed: () { Navigator.pop(context); _sendGeneric('📷 Photo attached', MessageType.image); },
          ),
          CupertinoActionSheetAction(
            child: const Text('🖼 Photo Library'),
            onPressed: () { Navigator.pop(context); _sendGeneric('🖼 Image from library', MessageType.image); },
          ),
          CupertinoActionSheetAction(
            child: const Text('📎 File'),
            onPressed: () async {
              Navigator.pop(context);
              final result = await FilePicker.platform.pickFiles();
              if (result != null) _sendGeneric('📎 ${result.files.first.name}', MessageType.file);
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('📊 Create Poll'),
            onPressed: () { Navigator.pop(context); _showCreatePoll(); },
          ),
          CupertinoActionSheetAction(
            child: Text(_steganoMode ? '🔓 Stegano Mode: ON' : '🔒 Stegano Mode: OFF'),
            onPressed: () {
              Navigator.pop(context);
              setState(() => _steganoMode = !_steganoMode);
              ChhayaHaptics.selection();
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
      ),
    );
  }

  void _showCreatePoll() {
    final qCtrl = TextEditingController();
    final o1Ctrl = TextEditingController();
    final o2Ctrl = TextEditingController();
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Create Poll'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(children: [
            CupertinoTextField(controller: qCtrl, placeholder: 'Question'),
            const SizedBox(height: 8),
            CupertinoTextField(controller: o1Ctrl, placeholder: 'Option 1'),
            const SizedBox(height: 8),
            CupertinoTextField(controller: o2Ctrl, placeholder: 'Option 2'),
          ]),
        ),
        actions: [
          CupertinoDialogAction(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
          CupertinoDialogAction(
            child: const Text('Send'),
            onPressed: () {
              Navigator.pop(context);
              if (qCtrl.text.trim().isEmpty) return;
              final pollJson = jsonEncode({
                'question': qCtrl.text.trim(),
                'options': [o1Ctrl.text.trim().isEmpty ? 'Yes' : o1Ctrl.text.trim(), o2Ctrl.text.trim().isEmpty ? 'No' : o2Ctrl.text.trim()],
                'votes': [0, 0],
              });
              _sendGeneric(pollJson, MessageType.poll);
            },
          ),
        ],
      ),
    );
  }

  void _showMessageActions(Message msg) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            child: const Text('👍 Agree'),
            onPressed: () {
              Navigator.pop(context);
              _toggleReaction(msg, true);
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('👎 Disagree'),
            onPressed: () {
              Navigator.pop(context);
              _toggleReaction(msg, false);
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('📋 Copy'),
            onPressed: () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: msg.content));
              ChhayaHaptics.selection();
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('↩️ Reply'),
            onPressed: () {
              Navigator.pop(context);
              _msgCtrl.text = '↩️ ${msg.content.length > 30 ? msg.content.substring(0, 30) : msg.content}... ';
              _focusNode.requestFocus();
            },
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            child: const Text('🗑 Delete'),
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(localDatabaseProvider).deleteMessage(msg.id);
              setState(() => _messages.removeWhere((m) => m.id == msg.id));
              ChhayaHaptics.medium();
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
      ),
    );
  }

  void _toggleReaction(Message msg, bool isAgree) async {
    final db = ref.read(localDatabaseProvider);
    List<String> agree = List.from(msg.agreeUsers);
    List<String> disagree = List.from(msg.disagreeUsers);

    if (isAgree) {
      disagree.remove('me');
      if (agree.contains('me')) agree.remove('me');
      else agree.add('me');
    } else {
      agree.remove('me');
      if (disagree.contains('me')) disagree.remove('me');
      else disagree.add('me');
    }

    final updated = msg.copyWith(agreeUsers: agree, disagreeUsers: disagree);
    await db.addMessage(updated);
    setState(() {
      final i = _messages.indexWhere((m) => m.id == msg.id);
      if (i != -1) _messages[i] = updated;
    });
    ChhayaHaptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.read(localDatabaseProvider);
    final readReceipts = db.getReadReceiptsEnabled();

    return CupertinoPageScaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: ChhayaColors.primaryBackground.withValues(alpha: 0.92),
        border: null,
        middle: GestureDetector(
          onTap: () => Navigator.of(context).pushNamed(ChhayaRouter.profile, arguments: {'contactId': null}),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AvatarWidget(name: widget.contactName, size: 30),
            const SizedBox(width: 8),
            Text(widget.contactName, style: ChhayaTypography.headline),
          ]),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _showTtlSelector,
              child: Icon(
                _currentTtl != null ? CupertinoIcons.clock_fill : CupertinoIcons.clock,
                color: _currentTtl != null ? ChhayaColors.accentOrange : ChhayaColors.accentBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).pushNamed(ChhayaRouter.call, arguments: {'contactName': widget.contactName, 'isVideo': false}),
              child: const Icon(CupertinoIcons.phone_fill, color: ChhayaColors.accentBlue, size: 20),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).pushNamed(ChhayaRouter.call, arguments: {'contactName': widget.contactName, 'isVideo': true}),
              child: const Icon(CupertinoIcons.videocam_fill, color: ChhayaColors.accentBlue, size: 20),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_steganoMode)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                color: ChhayaColors.accentPurple.withValues(alpha: 0.2),
                child: Text('🔒 Steganographic Mode Active', textAlign: TextAlign.center, style: ChhayaTypography.caption1.copyWith(color: ChhayaColors.accentPurple)),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator())
                  : ListView.builder(
                      controller: _scrollCtrl,
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: _messages.length + (_isTyping ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i == _messages.length && _isTyping) return _buildTypingIndicator();
                        return _buildBubble(_messages[i], readReceipts);
                      },
                    ),
            ),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(Message msg, bool readReceipts) {
    final isMine = msg.senderId == 'me';


    if (msg.type == MessageType.image && msg.content.startsWith('STEG:')) {
      return _buildStegBubble(msg, isMine);
    }


    if (msg.type == MessageType.poll) {
      return _buildPollCard(msg);
    }

    return GestureDetector(
      onLongPress: () => _showMessageActions(msg),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMine ? ChhayaColors.bubbleSent : ChhayaColors.bubbleReceived,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMine ? 18 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(msg.content, style: ChhayaTypography.body.copyWith(fontSize: 16)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(DateFormat.Hm().format(msg.timestamp), style: ChhayaTypography.caption2.copyWith(color: isMine ? ChhayaColors.labelPrimary.withValues(alpha: 0.6) : ChhayaColors.labelTertiary)),
                      if (isMine) ...[
                        const SizedBox(width: 4),
                        Icon(
                          CupertinoIcons.checkmark_alt,
                          size: 12,
                          color: (msg.isRead && readReceipts) ? ChhayaColors.accentBlue : ChhayaColors.labelTertiary,
                        ),
                        Icon(
                          CupertinoIcons.checkmark_alt,
                          size: 12,
                          color: (msg.isRead && readReceipts) ? ChhayaColors.accentBlue : ChhayaColors.labelTertiary,
                        ),
                      ],
                      if (_currentTtl != null) ...[
                        const SizedBox(width: 4),
                        Icon(CupertinoIcons.clock, size: 10, color: ChhayaColors.accentOrange.withValues(alpha: 0.7)),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            if (msg.agreeUsers.isNotEmpty || msg.disagreeUsers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (msg.agreeUsers.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: ChhayaColors.accentGreen.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                        child: Text('👍 ${msg.agreeUsers.length}', style: const TextStyle(fontSize: 11)),
                      ),
                    if (msg.disagreeUsers.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: ChhayaColors.accentRed.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                          child: Text('👎 ${msg.disagreeUsers.length}', style: const TextStyle(fontSize: 11)),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStegBubble(Message msg, bool isMine) {
    return GestureDetector(
      onTap: () {
        final encoded = msg.content.substring(5);
        try {
          final decoded = utf8.decode(base64Decode(encoded));
          showCupertinoDialog(
            context: context,
            builder: (_) => CupertinoAlertDialog(
              title: const Text('🔓 Hidden Message'),
              content: Text(decoded),
              actions: [CupertinoDialogAction(child: const Text('Close'), onPressed: () => Navigator.pop(context))],
            ),
          );
        } catch (_) {}
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 180,
            height: 120,
            decoration: BoxDecoration(
              color: ChhayaColors.tertiaryBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ChhayaColors.accentPurple.withValues(alpha: 0.3)),
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.lock_fill, size: 32, color: ChhayaColors.accentPurple),
                  SizedBox(height: 4),
                  Text('🔒 Steganographic', style: TextStyle(color: ChhayaColors.accentPurple, fontSize: 12)),
                  Text('Tap to reveal', style: TextStyle(color: ChhayaColors.labelTertiary, fontSize: 10)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPollCard(Message msg) {
    Map<String, dynamic> poll;
    try {
      poll = jsonDecode(msg.content) as Map<String, dynamic>;
    } catch (_) {
      return const SizedBox.shrink();
    }
    final question = poll['question'] as String? ?? '';
    final options = (poll['options'] as List<dynamic>?)?.cast<String>() ?? [];
    final votes = (poll['votes'] as List<dynamic>?)?.cast<int>() ?? List.filled(options.length, 0);
    final totalVotes = votes.fold<int>(0, (a, b) => a + b);
    final myVote = _pollVotes[msg.id];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📊 $question', style: ChhayaTypography.headline),
            const SizedBox(height: 12),
            ...List.generate(options.length, (i) {
              final pct = totalVotes > 0 ? (votes[i] / totalVotes * 100).round() : 0;
              final selected = myVote == i;
              return GestureDetector(
                onTap: myVote != null ? null : () {
                  votes[i]++;
                  _pollVotes[msg.id] = i;
                  final updated = msg.copyWith(content: jsonEncode({...poll, 'votes': votes}));
                  ref.read(localDatabaseProvider).addMessage(updated);
                  setState(() {
                    final idx = _messages.indexWhere((m) => m.id == msg.id);
                    if (idx != -1) _messages[idx] = updated;
                  });
                  ChhayaHaptics.selection();

                  Timer(const Duration(seconds: 2), () {
                    final peerChoice = (i + 1) % options.length;
                    votes[peerChoice]++;
                    final peerUpdated = msg.copyWith(content: jsonEncode({...poll, 'votes': votes}));
                    ref.read(localDatabaseProvider).addMessage(peerUpdated);
                    if (mounted) setState(() {
                      final idx = _messages.indexWhere((m) => m.id == msg.id);
                      if (idx != -1) _messages[idx] = peerUpdated;
                    });
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? ChhayaColors.accentBlue.withValues(alpha: 0.15) : ChhayaColors.fillTertiary,
                    borderRadius: BorderRadius.circular(10),
                    border: selected ? Border.all(color: ChhayaColors.accentBlue, width: 1) : null,
                  ),
                  child: Row(children: [
                    Expanded(child: Text(options[i], style: ChhayaTypography.body)),
                    if (myVote != null) Text('$pct%', style: ChhayaTypography.caption1.copyWith(color: ChhayaColors.accentBlue)),
                  ]),
                ),
              );
            }),
            if (totalVotes > 0)
              Text('$totalVotes vote${totalVotes > 1 ? 's' : ''}', style: ChhayaTypography.caption1),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: ChhayaColors.bubbleReceived,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (int i = 0; i < 3; i++)
              AnimatedBuilder(
                animation: _typingDotCtrl,
                builder: (_, __) {
                  final offset = ((_typingDotCtrl.value * 3 - i).clamp(0.0, 1.0) * 3.14159);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ChhayaColors.labelTertiary.withValues(alpha: 0.4 + 0.6 * (offset > 1.5 ? 0 : offset / 1.5)),
                    ),
                  );
                },
              ),
          ]),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: ChhayaColors.secondaryBackground.withValues(alpha: 0.85),
        border: Border(top: BorderSide(color: ChhayaColors.separator, width: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CupertinoButton(
            padding: const EdgeInsets.all(6),
            minimumSize: Size.zero,
            onPressed: _showAttachments,
            child: Icon(_hasText ? CupertinoIcons.plus : CupertinoIcons.camera_fill, color: ChhayaColors.accentBlue, size: 24),
          ),
          Expanded(
            child: CupertinoTextField(
              controller: _msgCtrl,
              focusNode: _focusNode,
              placeholder: 'Chhaya Message',
              placeholderStyle: ChhayaTypography.body.copyWith(color: ChhayaColors.labelTertiary, fontSize: 16),
              style: ChhayaTypography.body.copyWith(fontSize: 16),
              decoration: BoxDecoration(color: ChhayaColors.tertiaryBackground, borderRadius: BorderRadius.circular(18)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: _hasText
                ? CupertinoButton(
                    key: const ValueKey('send'),
                    padding: const EdgeInsets.all(4),
                    minimumSize: Size.zero,
                    onPressed: _sendMessage,
                    child: Container(
                      width: 32, height: 32,
                      decoration: const BoxDecoration(color: ChhayaColors.accentBlue, shape: BoxShape.circle),
                      child: const Icon(CupertinoIcons.arrow_up, color: CupertinoColors.white, size: 18),
                    ),
                  )
                : CupertinoButton(
                    key: const ValueKey('mic'),
                    padding: const EdgeInsets.all(4),
                    minimumSize: Size.zero,
                    onPressed: () => _sendGeneric("🎤 Voice message (0:08)", MessageType.voice),
                    child: const Icon(CupertinoIcons.mic_fill, color: ChhayaColors.accentBlue, size: 24),
                  ),
          ),
        ],
      ),
    );
  }
}
