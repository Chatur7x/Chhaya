import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
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
    for (final t in _ttlTimers.values) {
      t.cancel();
    }
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
        if (immediate) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        } else {
          _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: ChhayaAnimation.normal, curve: ChhayaAnimation.springCurve);
        }
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
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Disappearing Messages', style: ChhayaTypography.headline.copyWith(color: scheme.onSurface)),
              ),
              ...options.entries.map((e) => ListTile(
                title: Text(e.key, style: TextStyle(
                  color: e.value == (_currentTtl?.inSeconds ?? 0) ? ChhayaColors.accentBlue : scheme.onSurface,
                )),
                trailing: e.value == (_currentTtl?.inSeconds ?? 0)
                    ? const Icon(Icons.check, color: ChhayaColors.accentBlue)
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  final db = ref.read(localDatabaseProvider);
                  await db.setConversationTtl(widget.conversationId, e.value);
                  setState(() => _currentTtl = e.value == 0 ? null : Duration(seconds: e.value));
                  ChhayaHaptics.selection();
                },
              )),
            ],
          ),
        ),
      ),
    );
  }

  void _showAttachments() {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: ChhayaColors.accentBlue),
                title: Text('Camera', style: TextStyle(color: scheme.onSurface)),
                onTap: () { Navigator.pop(context); _sendGeneric('📷 Photo attached', MessageType.image); },
              ),
              ListTile(
                leading: const Icon(Icons.photo, color: ChhayaColors.accentBlue),
                title: Text('Photo Library', style: TextStyle(color: scheme.onSurface)),
                onTap: () { Navigator.pop(context); _sendGeneric('🖼 Image from library', MessageType.image); },
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file, color: ChhayaColors.accentBlue),
                title: Text('File', style: TextStyle(color: scheme.onSurface)),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await FilePicker.platform.pickFiles();
                  if (result != null) _sendGeneric('📎 ${result.files.first.name}', MessageType.file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.poll, color: ChhayaColors.accentBlue),
                title: Text('Create Poll', style: TextStyle(color: scheme.onSurface)),
                onTap: () { Navigator.pop(context); _showCreatePoll(); },
              ),
              ListTile(
                leading: Icon(_steganoMode ? Icons.lock_open : Icons.lock, color: ChhayaColors.accentPurple),
                title: Text(_steganoMode ? 'Stegano Mode: ON' : 'Stegano Mode: OFF', style: TextStyle(color: scheme.onSurface)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _steganoMode = !_steganoMode);
                  ChhayaHaptics.selection();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreatePoll() {
    final qCtrl = TextEditingController();
    final o1Ctrl = TextEditingController();
    final o2Ctrl = TextEditingController();
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: scheme.surfaceContainerHigh,
        title: Text('Create Poll', style: ChhayaTypography.headline.copyWith(color: scheme.onSurface)),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: qCtrl, decoration: const InputDecoration(hintText: 'Question')),
              const SizedBox(height: 8),
              TextField(controller: o1Ctrl, decoration: const InputDecoration(hintText: 'Option 1')),
              const SizedBox(height: 8),
              TextField(controller: o2Ctrl, decoration: const InputDecoration(hintText: 'Option 2')),
            ],
          ),
        ),
        actions: [
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
          FilledButton(
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
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.thumb_up, color: ChhayaColors.accentGreen),
                title: Text('Agree', style: TextStyle(color: scheme.onSurface)),
                onTap: () {
                  Navigator.pop(context);
                  _toggleReaction(msg, true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.thumb_down, color: ChhayaColors.accentRed),
                title: Text('Disagree', style: TextStyle(color: scheme.onSurface)),
                onTap: () {
                  Navigator.pop(context);
                  _toggleReaction(msg, false);
                },
              ),
              ListTile(
                leading: Icon(Icons.copy, color: scheme.onSurfaceVariant),
                title: Text('Copy', style: TextStyle(color: scheme.onSurface)),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: msg.content));
                  ChhayaHaptics.selection();
                },
              ),
              ListTile(
                leading: Icon(Icons.reply, color: scheme.onSurfaceVariant),
                title: Text('Reply', style: TextStyle(color: scheme.onSurface)),
                onTap: () {
                  Navigator.pop(context);
                  _msgCtrl.text = '↩️ ${msg.content.length > 30 ? msg.content.substring(0, 30) : msg.content}... ';
                  _focusNode.requestFocus();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: ChhayaColors.accentRed),
                title: Text('Delete', style: TextStyle(color: ChhayaColors.accentRed)),
                onTap: () async {
                  Navigator.pop(context);
                  await ref.read(localDatabaseProvider).deleteMessage(msg.id);
                  setState(() => _messages.removeWhere((m) => m.id == msg.id));
                  ChhayaHaptics.medium();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleReaction(Message msg, bool isAgree) async {
    final db = ref.read(localDatabaseProvider);
    List<String> agree = List.from(msg.agreeUsers);
    List<String> disagree = List.from(msg.disagreeUsers);

    if (isAgree) {
      disagree.remove('me');
      if (agree.contains('me')) {
        agree.remove('me');
      } else {
        agree.add('me');
      }
    } else {
      agree.remove('me');
      if (disagree.contains('me')) {
        disagree.remove('me');
      } else {
        disagree.add('me');
      }
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: ChhayaColors.primaryBackground.withValues(alpha: 0.92),
        elevation: 0,
        title: GestureDetector(
          onTap: () => Navigator.of(context).pushNamed(ChhayaRouter.profile, arguments: {'contactId': null}),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AvatarWidget(name: widget.contactName, size: 30),
            const SizedBox(width: 8),
            Text(widget.contactName, style: ChhayaTypography.headline),
          ]),
        ),
        actions: [
          IconButton(
            onPressed: _showTtlSelector,
            icon: Icon(
              _currentTtl != null ? Icons.timer : Icons.timer_outlined,
              color: _currentTtl != null ? ChhayaColors.accentOrange : ChhayaColors.accentBlue,
              size: 20,
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed(ChhayaRouter.call, arguments: {'contactName': widget.contactName, 'isVideo': false}),
            icon: const Icon(Icons.phone, color: ChhayaColors.accentBlue, size: 20),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed(ChhayaRouter.call, arguments: {'contactName': widget.contactName, 'isVideo': true}),
            icon: const Icon(Icons.videocam, color: ChhayaColors.accentBlue, size: 20),
          ),
        ],
      ),
      body: SafeArea(
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
                  ? Center(child: CircularProgressIndicator(color: scheme.primary))
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
                          Icons.done_all,
                          size: 12,
                          color: (msg.isRead && readReceipts) ? ChhayaColors.accentBlue : ChhayaColors.labelTertiary,
                        ),
                      ],
                      if (_currentTtl != null) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.timer, size: 10, color: ChhayaColors.accentOrange.withValues(alpha: 0.7)),
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
          final scheme = Theme.of(context).colorScheme;
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: scheme.surfaceContainerHigh,
              title: Text('🔓 Hidden Message', style: ChhayaTypography.headline.copyWith(color: scheme.onSurface)),
              content: Text(decoded, style: TextStyle(color: scheme.onSurface)),
              actions: [TextButton(child: const Text('Close'), onPressed: () => Navigator.pop(context))],
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
                  Icon(Icons.lock, size: 32, color: ChhayaColors.accentPurple),
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
                    if (idx != -1) {
                      _messages[idx] = updated;
                    }
                  });
                  ChhayaHaptics.selection();

                  Timer(const Duration(seconds: 2), () {
                    final peerChoice = (i + 1) % options.length;
                    votes[peerChoice]++;
                    final peerUpdated = msg.copyWith(content: jsonEncode({...poll, 'votes': votes}));
                    ref.read(localDatabaseProvider).addMessage(peerUpdated);
                    if (mounted) {
                      setState(() {
                        final idx = _messages.indexWhere((m) => m.id == msg.id);
                        if (idx != -1) {
                          _messages[idx] = peerUpdated;
                        }
                      });
                    }
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
          IconButton(
            onPressed: _showAttachments,
            icon: Icon(_hasText ? Icons.add : Icons.camera_alt, color: ChhayaColors.accentBlue, size: 24),
          ),
          Expanded(
            child: TextField(
              controller: _msgCtrl,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: 'Chhaya Message',
                hintStyle: ChhayaTypography.body.copyWith(color: ChhayaColors.labelTertiary, fontSize: 16),
                filled: true,
                fillColor: ChhayaColors.tertiaryBackground,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              style: ChhayaTypography.body.copyWith(fontSize: 16),
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
                ? IconButton(
                    key: const ValueKey('send'),
                    onPressed: _sendMessage,
                    icon: Container(
                      width: 32, height: 32,
                      decoration: const BoxDecoration(color: ChhayaColors.accentBlue, shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_upward, color: ChhayaColors.labelPrimary, size: 18),
                    ),
                  )
                : IconButton(
                    key: const ValueKey('mic'),
                    onPressed: () => _sendGeneric("🎤 Voice message (0:08)", MessageType.voice),
                    icon: const Icon(Icons.mic, color: ChhayaColors.accentBlue, size: 24),
                  ),
          ),
        ],
      ),
    );
  }
}
