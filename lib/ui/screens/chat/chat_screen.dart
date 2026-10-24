import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/cupertino.dart' show CupertinoContextMenuAction;
import '../../../core/models/message_attachment.dart';
import '../../../services/messaging/attachment_service.dart';
import '../../../services/messaging/messaging_service.dart';
import '../../../services/call/call_service.dart';
import '../../widgets/message_attachment_view.dart';
import '../../widgets/voice_recorder_sheet.dart';
import '../../widgets/chhaya_context_menu.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/chhaya_theme.dart';
import '../../widgets/avatar_widget.dart';
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

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  static const _messageRefreshInterval = Duration(seconds: 15);
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Message> _messages = [];
  bool _loading = true;
  bool _isTyping = false;
  bool _otherTyping = false;
  bool _supportsTyping = false;
  Timer? _typingKeepAliveTimer;
  Timer? _typingStopTimer;
  Timer? _otherTypingTimer;
  StreamSubscription<TypingUpdate>? _typingSubscription;
  Future<void> _typingSignalTail = Future.value();
  bool _localTypingActive = false;
  final bool _steganoMode = false;
  int _ttlMinutes = 0;
  Timer? _refreshTimer;
  bool _sending=false;
  bool _refreshing=false;
  Message? _replyTo;
  MessageAttachment? _attachment;
  String? _loadError;
  final _animatedMessages = <String>{};


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _msgCtrl.addListener(_handleDraftChanged);
    _listenForTyping();
    _loadMessages();
    // Foreground sync runs independently; avoid rereading SQLCipher every 2 seconds.
    _refreshTimer=Timer.periodic(_messageRefreshInterval,(_)=>_loadMessages());
  }

  void _listenForTyping() {
    final conversation = ref.read(conversationsProvider)
        .where((item) => item.id == widget.conversationId).firstOrNull;
    if (conversation == null || conversation.isGroup) return;
    _supportsTyping = true;
    _typingSubscription = ref.read(callServiceProvider).typing.listen((update) {
      if (!mounted || !_supportsTyping ||
          update.conversationId != widget.conversationId ||
          !conversation.participants.any((contact) => contact.id == update.senderId)) {
        return;
      }
      if (!ref.read(localDatabaseProvider).getTypingIndicatorsEnabled()) {
        _clearRemoteTyping();
        return;
      }
      _otherTypingTimer?.cancel();
      if (_otherTyping != update.isTyping) {
        setState(() => _otherTyping = update.isTyping);
      }
      if (update.isTyping) {
        _otherTypingTimer = Timer(const Duration(seconds: 6), _clearRemoteTyping);
      }
    });
  }

  void _clearRemoteTyping() {
    _otherTypingTimer?.cancel();
    _otherTypingTimer = null;
    if (mounted && _otherTyping) setState(() => _otherTyping = false);
  }

  void _handleDraftChanged() {
    final hasText = _msgCtrl.text.trim().isNotEmpty;
    if (hasText != _isTyping) setState(() => _isTyping = hasText);
    if (!_supportsTyping) return;

    if (!ref.read(localDatabaseProvider).getTypingIndicatorsEnabled()) {
      _typingKeepAliveTimer?.cancel();
      _typingKeepAliveTimer = null;
      _typingStopTimer?.cancel();
      _queueTypingSignal(false);
      return;
    }

    if (hasText) {
      _typingStopTimer?.cancel();
      _typingStopTimer = null;
      if (_typingKeepAliveTimer == null) {
        _queueTypingSignal(true);
        _typingKeepAliveTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          if (ref.read(localDatabaseProvider).getTypingIndicatorsEnabled()) {
            _queueTypingSignal(true, refresh: true);
          } else {
            _typingKeepAliveTimer?.cancel();
            _typingKeepAliveTimer = null;
            _queueTypingSignal(false);
          }
        });
      }
    } else {
      _typingKeepAliveTimer?.cancel();
      _typingKeepAliveTimer = null;
      _typingStopTimer?.cancel();
      _typingStopTimer = Timer(const Duration(milliseconds: 250), () {
        _typingStopTimer = null;
        _queueTypingSignal(false);
      });
    }
  }

  void _queueTypingSignal(bool active, {bool refresh = false}) {
    if (!_supportsTyping) return;
    final enabled = ref.read(localDatabaseProvider).getTypingIndicatorsEnabled();
    if (active && !enabled) return;
    if (!refresh && _localTypingActive == active) return;
    _localTypingActive = active;
    final service = ref.read(callServiceProvider);
    _typingSignalTail = _typingSignalTail.then((_) async {
      try {
        await service.sendTyping(widget.conversationId, active);
      } catch (_) {
        // Typing metadata is best-effort and never blocks sending a message.
      }
    });
  }

  Future<void> _loadMessages() async {
    if(_refreshing) { return; }
    _refreshing=true;
    try {
      final db=ref.read(localDatabaseProvider);
      final msgs=await db.getMessages(widget.conversationId);
      if(!mounted) { return; }
      if (!_loading) {
        final oldIds = _messages.map((m) => m.id).toSet();
        _animatedMessages.addAll(msgs.where((m) => !oldIds.contains(m.id)).map((m) => m.id));
      }
      setState(() { _messages=msgs.where((message)=>!message.isExpired).toList(); _loading=false; _loadError=null; });
      if (WidgetsBinding.instance.lifecycleState != null &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) { return; }
      if (ModalRoute.of(context)?.isCurrent == false) return;
      for(final message in msgs.where((m)=>m.senderId!='me'&&!m.isRead&&!m.isExpired)) {
        if(!db.getReadReceiptsEnabled()) { break; }
        try {
          await ref.read(apiServiceProvider).markMessagesRead(message.id);
          await db.addMessage(message.copyWith(isRead:true));
        } catch (_) { break; }
      }
    } catch (_) {
      if (mounted) setState(() { _loadError='Could not load messages.'; _loading=false; });
    } finally { _refreshing=false; }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _refreshTimer?.cancel();
    _typingKeepAliveTimer?.cancel();
    _typingStopTimer?.cancel();
    _otherTypingTimer?.cancel();
    if (_supportsTyping) _queueTypingSignal(false);
    _typingSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _refreshTimer?.cancel();
    if (state == AppLifecycleState.resumed) {
      _loadMessages();
      _refreshTimer = Timer.periodic(_messageRefreshInterval, (_) => _loadMessages());
      if (_supportsTyping && _msgCtrl.text.trim().isNotEmpty &&
          ref.read(localDatabaseProvider).getTypingIndicatorsEnabled()) {
        _handleDraftChanged();
      }
    } else if (_supportsTyping) {
      _typingKeepAliveTimer?.cancel();
      _typingKeepAliveTimer = null;
      _typingStopTimer?.cancel();
      _typingStopTimer = null;
      _queueTypingSignal(false);
    }
  }

  bool _isSent(Message m) => m.senderId == 'me';

  void _scrollToBottom() {
    if(!_scrollCtrl.hasClients) { return; }
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: ChhayaAnimation.normal,
      curve: ChhayaAnimation.springCurve,
    );
  }

  void _finishDraft(String draft, Message? reply, MessageAttachment? attachment) {
    if (!mounted) return;
    if (_msgCtrl.text == draft) _msgCtrl.clear();
    setState(() {
      if (_replyTo?.id == reply?.id) _replyTo = null;
      if (identical(_attachment, attachment)) _attachment = null;
    });
  }

  Future<void> _retryPending() async {
    try {
      await ref.read(messagingServiceProvider).retryPending(widget.conversationId);
      await _loadMessages();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Still offline. Your message remains queued.')));
      }
    }
  }

  Future<void> _sendMessage() async {
    final draft = _msgCtrl.text;
    final text = draft.trim();
    final attachment = _attachment;
    final reply = _replyTo;
    if ((text.isEmpty && attachment == null) || _sending) return;
    setState(() => _sending = true);
    try {
      final conversation = ref.read(conversationsProvider)
        .where((c) => c.id == widget.conversationId).firstOrNull;
      if (conversation == null) throw StateError('Conversation is unavailable');
      await ref.read(messagingServiceProvider).send(conversation, text,
        ttl: _ttlMinutes > 0 ? Duration(minutes: _ttlMinutes) : null,
        replyToId: reply?.id, attachment: attachment,
        type: attachment == null ? MessageType.text :
          attachment.isPreviewableImage ? MessageType.image :
          attachment.mimeType == 'audio/aac' ? MessageType.voice : MessageType.file);
      _finishDraft(draft, reply, attachment);
      await _loadMessages();
      _scrollToBottom();
    } on MessageQueuedException {
      _finishDraft(draft, reply, attachment);
      await _loadMessages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Message queued. It will retry while the app is open.'),
          action: SnackBarAction(label: 'Retry', onPressed: _retryPending)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message not sent: $error')));
      }
    } finally { if (mounted) setState(() => _sending = false); }
  }

  Future<void> _pickAttachment(bool imagesOnly) async {
    try {
      final selected = await AttachmentService.pick(imagesOnly: imagesOnly);
      if (mounted && selected != null) setState(() => _attachment = selected);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not attach the file. Choose a readable file up to 256 KB.')));
      }
    }
  }

  Future<void> _recordVoice() async {
    final attachment = await ChhayaMotion.sheet<MessageAttachment>(context, (_) => const VoiceRecorderSheet(), dismissible:false);
    if (mounted && attachment != null) setState(() => _attachment = attachment);
  }

  Future<void> _messageActions(Message message) => ChhayaMotion.sheet<void>(context, (ctx) => SafeArea(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.reply_rounded), title: const Text('Reply'),
          onTap: () { Navigator.pop(ctx); setState(() => _replyTo = message); }),
        if (message.content.isNotEmpty) ListTile(leading: const Icon(Icons.copy_rounded),
          title: const Text('Copy text'), onTap: () {
            Clipboard.setData(ClipboardData(text: message.content)); Navigator.pop(ctx);
          }),
        if (_isSent(message) && !message.isSent) ListTile(
          leading: const Icon(Icons.refresh_rounded), title: const Text('Retry queued messages'),
          onTap: () { Navigator.pop(ctx); _retryPending(); }),
      ],
    )),
  );

  Widget _replyPreview(String id, Color foreground) {
    final original = _messages.where((m) => m.id == id).firstOrNull;
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(original == null ? 'Reply' : _isSent(original) ? 'Reply to you' : 'Reply to ${widget.contactName}',
          style: ChhayaType.of(context).caption.copyWith(color: foreground, fontWeight: FontWeight.w700)),
        Text(original == null ? 'Original message unavailable' : original.attachment?.name ?? original.content,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: ChhayaType.of(context).body.copyWith(color: foreground)),
        Divider(color: foreground.withValues(alpha: 0.3)),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final conversations = ref.watch(conversationsProvider);
    final convo = conversations.where((c) => c.id == widget.conversationId).firstOrNull;

    return Scaffold(
      backgroundColor: ChhayaPalette.of(context).primaryBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, convo),
            if (_steganoMode) _buildSteganoBanner(disableAnimations),
            if (_loadError != null) MaterialBanner(content: Text(_loadError!),
              actions: [TextButton(onPressed: _loadMessages, child: const Text('Retry'))]),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: ChhayaPalette.of(context).accent))
                  : _messages.isEmpty && !_otherTyping
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
                            if(i == _messages.length) { return _buildTypingIndicator(disableAnimations); }
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

  Widget _buildAppBar(BuildContext context,Conversation? convo) => Padding(
    padding:const EdgeInsets.symmetric(horizontal:8,vertical:8),
    child:Row(children:[
      IconButton(tooltip:'Back',icon:const Icon(Icons.arrow_back_rounded),
        onPressed:()=>Navigator.of(context).pop()),
      Hero(tag:'conversation-avatar-${widget.conversationId}',child:AvatarWidget(name:widget.contactName,size:40)),
      const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(widget.contactName,maxLines:MediaQuery.viewInsetsOf(context).bottom>0?1:2,overflow:TextOverflow.ellipsis,style:ChhayaType.of(context).title),
        if(MediaQuery.viewInsetsOf(context).bottom==0) Text(convo?.participants.firstOrNull?.isVerified==true?'Verified identity':'Verify identity before messaging',
          maxLines:2,style:ChhayaType.of(context).caption),
      ])),
      PopupMenuButton<String>(tooltip:'Chat options',onSelected:(action){
        if(action=='timer') { _showTtlSheet(); return; }
        Navigator.of(context).pushNamed(ChhayaRouter.call,arguments:{
          'conversationId':widget.conversationId,'contactName':widget.contactName,'isVideo':action=='video'});
      },itemBuilder:(_)=>const [
        PopupMenuItem(value:'voice',child:Text('Voice call')),
        PopupMenuItem(value:'video',child:Text('Video call')),
        PopupMenuItem(value:'timer',child:Text('Disappearing messages')),
      ]),
    ]),
  );

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
            ChhayaPalette.of(context).accent.withValues(alpha: 0.18),
            ChhayaPalette.of(context).info.withValues(alpha: 0.12),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: ChhayaPalette.of(context).borderMed, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.visibility_off_rounded, size: 14, color: ChhayaPalette.of(context).accent),
          const SizedBox(width: ChhayaSpacing.space1),
          Text(
            'STEGANO MODE — messages hidden in images',
            style: ChhayaType.of(context).labelSmall.copyWith(
              color: ChhayaPalette.of(context).accent,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              fontSize: 11,
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
                color: ChhayaPalette.of(context).cardSurface,
                borderRadius: BorderRadius.circular(ChhayaRadius.xxl),
                border: Border.all(color: ChhayaPalette.of(context).glassBorder.withValues(alpha: 0.12)),
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 36,
                color: ChhayaPalette.of(context).accent.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: ChhayaSpacing.space5),
            Text(
              'End-to-End Encrypted',
              style: ChhayaType.of(context).headlineMedium.copyWith(fontSize: 15),
            ),
            const SizedBox(height: ChhayaSpacing.space1),
            Text(
              'Verify your contact and connect your server\nto exchange encrypted direct messages.',
              textAlign: TextAlign.center,
              style: ChhayaType.of(context).bodySmall.copyWith(
                color: ChhayaPalette.of(context).labelTertiary,
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

    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: 'Message actions'): () => _messageActions(msg),
        CustomSemanticsAction(label: 'Reply'): () => setState(() => _replyTo = msg),
      },
      child: MessageEntrance(key:ValueKey(msg.id),animate:_animatedMessages.remove(msg.id),
        child: SwipeReply(onReply:()=>setState(()=>_replyTo=msg), child: Align(
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
            ChhayaContextMenu(onStaticMenu:()=>_messageActions(msg),actions:[
              CupertinoContextMenuAction(trailingIcon:Icons.reply_rounded,child:const Text('Reply'),
                onPressed:(){Navigator.pop(context);setState(()=>_replyTo=msg);}),
              if(msg.content.isNotEmpty) CupertinoContextMenuAction(trailingIcon:Icons.copy_rounded,
                child:const Text('Copy text'),onPressed:(){Clipboard.setData(ClipboardData(text:msg.content));Navigator.pop(context);}),
              if(isSent&&!msg.isSent) CupertinoContextMenuAction(trailingIcon:Icons.refresh_rounded,
                child:const Text('Retry queued messages'),onPressed:(){Navigator.pop(context);_retryPending();}),
            ],child:Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ChhayaSpacing.space4,
                vertical: ChhayaSpacing.space3,
              ),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.74,
              ),
              decoration: BoxDecoration(

                color: isSent ? ChhayaPalette.of(context).bubbleSent : ChhayaPalette.of(context).bubbleReceived,
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
                            ? ChhayaPalette.of(context).info.withValues(alpha: 0.3)
                            : ChhayaPalette.of(context).separator,
                        width: 0.6,
                      ),

              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isStegano)
                    Padding(
                      padding: EdgeInsets.only(bottom: ChhayaSpacing.space1),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility_off_rounded, size: 12, color: ChhayaPalette.of(context).accent),
                          SizedBox(width: 4),
                          Text(
                            'STEGANO',
                            style: TextStyle(
                              color: ChhayaPalette.of(context).accent,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (msg.replyToId != null) _replyPreview(msg.replyToId!,
                    isSent ? ChhayaPalette.of(context).bubbleSentText : ChhayaPalette.of(context).bubbleReceivedText),
                  if (msg.attachment != null) MessageAttachmentView(attachment: msg.attachment!, heroTag:'message-image-${msg.id}',
                    foreground: isSent ? ChhayaPalette.of(context).bubbleSentText : ChhayaPalette.of(context).bubbleReceivedText),
                  if (msg.content.isNotEmpty) Text(
                    msg.content,
                    style: ChhayaType.of(context).bodyMedium.copyWith(
                      color: isSent && !isStegano ? ChhayaPalette.of(context).bubbleSentText : ChhayaPalette.of(context).bubbleReceivedText,
                      fontSize: 17,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: ChhayaSpacing.space1),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (msg.ttl != null)
                  Padding(
                    padding: EdgeInsets.only(right: ChhayaSpacing.space1),
                    child: Icon(Icons.timer_outlined, size: 11, color: ChhayaPalette.of(context).labelQuaternary),
                  ),
                Text(
                  timeStr,
                  style: ChhayaType.of(context).labelSmall.copyWith(
                    color: isSent
                        ? ChhayaPalette.of(context).inkMuted
                        : ChhayaPalette.of(context).labelTertiary,
                    fontSize: 11,
                  ),
                ),
                if (isSent) ...[
                  const SizedBox(width: 3),
                  Icon(
                    !msg.isSent ? Icons.schedule_rounded : msg.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 13,
                    color: msg.isRead
                        ? ChhayaPalette.of(context).accent
                        : ChhayaPalette.of(context).inkMuted,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ))));
  }

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
          color: ChhayaPalette.of(context).bubbleReceived,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(ChhayaRadius.lg),
            topRight: Radius.circular(ChhayaRadius.lg),
            bottomRight: Radius.circular(ChhayaRadius.lg),
            bottomLeft: Radius.circular(ChhayaRadius.sm),
          ),
          border: Border.all(color: ChhayaPalette.of(context).separator, width: 0.6),
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
                color: ChhayaPalette.of(context).accent.withValues(alpha: 0.3 + (i * 0.25)),
                shape: BoxShape.circle,
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildInputBar(bool disableAnimations) => Container(
    padding:const EdgeInsets.fromLTRB(12,12,12,12),
    decoration:BoxDecoration(color:ChhayaPalette.of(context).surface,
      border:Border(top:BorderSide(color:ChhayaPalette.of(context).borderSoft))),
    child:Column(mainAxisSize:MainAxisSize.min,children:[
      if (_replyTo != null) Row(children:[
        Expanded(child:Text('Replying to ${_isSent(_replyTo!) ? 'you' : widget.contactName}',
          maxLines:2,overflow:TextOverflow.ellipsis,style:ChhayaType.of(context).caption)),
        IconButton(tooltip:'Cancel reply',onPressed:()=>setState(()=>_replyTo=null),icon:const Icon(Icons.close_rounded)),
      ]),
      if (_attachment != null) Row(children:[
        Icon(Icons.attach_file_rounded,color:ChhayaPalette.of(context).accent),
        const SizedBox(width:8),
        Expanded(child:Text(_attachment!.name,maxLines:2,overflow:TextOverflow.ellipsis,style:ChhayaType.of(context).caption)),
        IconButton(tooltip:'Remove attachment',onPressed:()=>setState(()=>_attachment=null),icon:const Icon(Icons.close_rounded)),
      ]),
      Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
      IconButton(tooltip:'Attach a file',icon:const Icon(Icons.add_rounded),onPressed:_sending?null:_showAttachmentSheet),
      const SizedBox(width:8),
      Expanded(child:TextField(controller:_msgCtrl,minLines:1,
        maxLines:MediaQuery.viewInsetsOf(context).bottom>0?2:4,
        style:ChhayaType.of(context).bodyLarge,textCapitalization:TextCapitalization.sentences,
        decoration:const InputDecoration(hintText:'Write a message',
          contentPadding:EdgeInsets.symmetric(horizontal:16,vertical:12)),
      )),
      const SizedBox(width:8),
      IconButton.filled(tooltip:'Send message',
        onPressed:(_isTyping||_attachment!=null)&&!_sending?_sendMessage:null,
        icon:_sending?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2))
          :const Icon(Icons.arrow_upward_rounded)),
    ]),
    ]),
  );

  void _showTtlSheet() {
    const options = [0, 1, 5, 30, 60, 1440];
    ChhayaMotion.sheet<void>(context, (_) => Padding(
        padding: const EdgeInsets.all(ChhayaSpacing.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Disappearing Messages', style: ChhayaType.of(context).displaySmall.copyWith(fontSize: 18)),
            const SizedBox(height: ChhayaSpacing.space1),
            Text('Hide expired messages from this conversation', style: ChhayaType.of(context).labelMedium),
            const SizedBox(height: ChhayaSpacing.space4),
            ...options.map((m) {
              final label = m == 0
                  ? 'Use global default'
                  : m == 1440
                      ? '24 hours'
                      : '$m minute${m > 1 ? 's' : ''}';
              final selected = _ttlMinutes == m;
              return ListTile(
                dense: true,
                title: Text(label, style: ChhayaType.of(context).bodyMedium),
                trailing: selected
                    ? Icon(Icons.check_circle_rounded, color: ChhayaPalette.of(context).accent, size: 20)
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
    ChhayaMotion.sheet<void>(context,(ctx)=>SafeArea(
      child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Padding(padding:EdgeInsets.all(24),child:Text('Encrypted attachments · up to 256 KB')),
        ListTile(leading:const Icon(Icons.image_outlined),title:const Text('Photo'),
          subtitle:const Text('PNG, JPEG or WebP'),onTap:(){Navigator.pop(ctx);_pickAttachment(true);}),
        ListTile(leading:const Icon(Icons.mic_rounded),title:const Text('Voice message'),
          subtitle:const Text('Record up to one minute'),onTap:(){Navigator.pop(ctx);_recordVoice();}),
        ListTile(leading:const Icon(Icons.attach_file_rounded),title:const Text('File'),
          onTap:(){Navigator.pop(ctx);_pickAttachment(false);}),
      ]),
    ));
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
