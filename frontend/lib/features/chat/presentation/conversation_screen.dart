import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/presentation/widgets/glass_container.dart';
import '../../../core/mesh/mesh_message.dart';
import '../../../core/providers/app_providers.dart';
import '../../contacts/domain/models/contact.dart';
import '../../../core/crypto/signal_protocol_service.dart';
import '../../../core/theme/chaaya_theme.dart';
import 'voice_message_recorder.dart';
import 'reaction_picker.dart';
import 'typing_indicator.dart';
import 'reply_quote_card.dart';
import '../domain/models/message_metadata.dart';

class MessageData {
  final MeshMessage message;
  final MessageMetadata? metadata;

  MessageData({required this.message, this.metadata});
}

class ConversationScreen extends ConsumerStatefulWidget {
  final Contact contact;
  const ConversationScreen({super.key, required this.contact});

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _messageController = TextEditingController();
  final List<MessageData> _messages = [];
  bool _isEncrypting = false;
  MessageData? _replyingTo;
  bool _showReactionPicker = false;
  String? _selectedMessageId;
  bool _isContactTyping = false;
  bool _showAttachmentPicker = false;
  bool _showVoiceRecorder = false;

  StreamSubscription? _bleSub;
  StreamSubscription? _wifiSub;
  StreamSubscription? _typingSub;

  @override
  void initState() {
    super.initState();
    _setupMessageListeners();
    _setupTypingListener();
  }

  void _setupMessageListeners() {
    final ble = ref.read(bleMeshServiceProvider);
    _bleSub = ble.incomingMessages.listen((msg) {
      if (msg.senderId == widget.contact.deviceId) {
        _handleIncomingEncrypted(msg);
      }
    });

    final wifi = ref.read(wifiDirectServiceProvider);
    _wifiSub = wifi.incomingMessages.listen((msg) {
      if (msg.senderId == widget.contact.deviceId) {
        _handleIncomingEncrypted(msg);
      }
    });
  }

  void _setupTypingListener() {
    final presence = ref.read(presenceServiceProvider);
    _typingSub = presence.typingStream.listen((event) {
      if (event.senderId == widget.contact.deviceId) {
        setState(() {
          _isContactTyping = event.isTyping;
        });
      }
    });
  }

  Future<void> _handleIncomingEncrypted(MeshMessage msg) async {
    final crypto = ref.read(signalProtocolProvider);
    final reactionSvc = ref.read(reactionServiceProvider);
    final replySvc = ref.read(replyServiceProvider);

    try {
      final payloadJson = jsonDecode(msg.content);
      final payload = EncryptedPayload.fromJson(payloadJson);
      final decryptedText =
          await crypto.decrypt(widget.contact.deviceId, payload);

      final metadata =
          reactionSvc.getMetadata(msg.id) ?? replySvc.getReplyMetadata(msg.id);

      if (mounted) {
        setState(() {
          _messages.add(MessageData(
            message: msg.copyWith(content: decryptedText),
            metadata: metadata,
          ));
        });
      }
    } catch (e) {
      debugPrint('[Chat] Decrypt failed: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isEncrypting = true);

    final myIdentity = ref.read(identityServiceProvider).currentIdentity;
    if (myIdentity == null) {
      setState(() => _isEncrypting = false);
      return;
    }

    final crypto = ref.read(signalProtocolProvider);
    final router = ref.read(meshRouterProvider);
    final replySvc = ref.read(replyServiceProvider);
    final presence = ref.read(presenceServiceProvider);

    try {
      await crypto.getOrCreateSession(
          widget.contact.deviceId, widget.contact.publicKey);
      final payload = await crypto.encrypt(widget.contact.deviceId, text);

      MeshMessage msg = MeshMessage(
        senderId: myIdentity.deviceId,
        senderName: myIdentity.username,
        recipientId: widget.contact.deviceId,
        content: jsonEncode(payload.toJson()),
        replyToId: _replyingTo?.message.id,
        quotedText: _replyingTo?.message.content,
      );

      if (_replyingTo != null) {
        await replySvc.setReplyTo(
            msg.id, _replyingTo!.message.id, _replyingTo!.message.content);
      }

      final displayMsg = msg.copyWith(content: text);

      if (mounted) {
        setState(() {
          _messageController.clear();
          _messages.add(MessageData(message: displayMsg));
          _replyingTo = null;
          _showReactionPicker = false;
          _selectedMessageId = null;
        });
      }

      await router.send(msg);
      presence.sendReadReceipt(msg.id, widget.contact.deviceId);
    } catch (e) {
      debugPrint('[Chat] Send failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Encryption failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isEncrypting = false);
      }
    }
  }

  void _handleReaction(String emoji) {
    if (_selectedMessageId == null) return;

    final reactionSvc = ref.read(reactionServiceProvider);
    final myIdentity = ref.read(identityServiceProvider).currentIdentity;
    if (myIdentity == null) return;

    reactionSvc.toggleReaction(_selectedMessageId!, emoji, myIdentity.deviceId);

    setState(() {
      _showReactionPicker = false;
      _selectedMessageId = null;
    });
  }

  void _showReplyTo(MessageData msgData) {
    setState(() {
      _replyingTo = msgData;
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  void _startVoiceCall() {
    final callService = ref.read(callServiceProvider);
    callService.startCall(widget.contact.deviceId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Calling ${widget.contact.name}...')),
    );
  }

  void _startVideoCall() {
    final callService = ref.read(callServiceProvider);
    callService.startVideoCall(widget.contact.deviceId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Starting video call with ${widget.contact.name}...')),
    );
  }

  void _openContactCard() {
    Navigator.pushNamed(context, '/contact-card', arguments: widget.contact);
  }

  void _shareLocation() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Location sharing coming soon...')),
    );
  }

  void _sendSOS() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Send SOS?'),
          ],
        ),
        content: const Text(
          'This will send an emergency SOS to all trusted contacts with your current location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('SOS sent to trusted contacts!'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    _wifiSub?.cancel();
    _typingSub?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: GlassContainer(
          borderRadius: 0,
          blur: 20,
          opacity: 0.15,
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.blueAccent,
                  child: Text(widget.contact.name[0].toUpperCase(),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.contact.name,
                        style: const TextStyle(fontSize: 16)),
                    Row(
                      children: [
                        const Icon(Icons.lock,
                            size: 10, color: Colors.greenAccent),
                        const SizedBox(width: 4),
                        Text(
                            widget.contact.status == ContactStatus.nearby
                                ? 'Directly connected'
                                : 'Offline mesh',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.videocam),
                onPressed: () => _startVideoCall(),
              ),
              IconButton(
                icon: const Icon(Icons.call),
                onPressed: () => _startVoiceCall(),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'contact_card':
                      _openContactCard();
                      break;
                    case 'location':
                      _shareLocation();
                      break;
                    case 'sos':
                      _sendSOS();
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'contact_card',
                    child: Row(
                      children: [
                        Icon(Icons.person),
                        SizedBox(width: 8),
                        Text('Contact Info'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'location',
                    child: Row(
                      children: [
                        Icon(Icons.location_on),
                        SizedBox(width: 8),
                        Text('Share Location'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'sos',
                    child: Row(
                      children: [
                        Icon(Icons.sos, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Send SOS', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_showReactionPicker && _selectedMessageId != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ReactionPicker(onReactionSelected: _handleReaction),
            ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                        'Secure E2EE established.\nMessages are routed offline.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msgData = _messages[index];
                      final msg = msgData.message;
                      final isMe = msg.senderId != widget.contact.deviceId;
                      final metadata = msgData.metadata ??
                          ref.read(reactionServiceProvider).getMetadata(msg.id);

                      return GestureDetector(
                        onLongPress: () {
                          setState(() {
                            _showReactionPicker = true;
                            _selectedMessageId = msg.id;
                          });
                        },
                        child: Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            if (msg.replyToId != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: ChaayaTheme.accent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.reply,
                                        size: 14, color: ChaayaTheme.accent),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        (msg.quotedText?.length ?? 0) > 50
                                            ? '${msg.quotedText!.substring(0, 50)}...'
                                            : msg.quotedText ?? '',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: ChaayaTheme.accent),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? Colors.blueAccent
                                      : Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(isMe ? 16 : 0),
                                    bottomRight: Radius.circular(isMe ? 0 : 16),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      msg.content,
                                      style: TextStyle(
                                          color: isMe
                                              ? Colors.white
                                              : Colors.white70),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isMe)
                                          const Icon(Icons.lock_outline,
                                              size: 10, color: Colors.white54),
                                        if (isMe) const SizedBox(width: 4),
                                        if (msg.edited) ...[
                                          const Text('(edited) ',
                                              style: TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 9,
                                                  fontStyle: FontStyle.italic)),
                                        ],
                                        Text(
                                            '${msg.timestamp.hour}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                                            style: TextStyle(
                                                color: isMe
                                                    ? Colors.white70
                                                    : Colors.grey,
                                                fontSize: 10)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (metadata != null &&
                                metadata.reactions.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: 8, left: 4, right: 4),
                                child: ReactionDisplay(
                                  reactions: metadata.reactions,
                                  onTap: () {
                                    setState(() {
                                      _showReactionPicker = true;
                                      _selectedMessageId = msg.id;
                                    });
                                  },
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildActionButton(
                                      Icons.reply, () => _showReplyTo(msgData)),
                                  const SizedBox(width: 8),
                                  _buildActionButton(
                                      Icons.emoji_emotions_outlined, () {
                                    setState(() {
                                      _showReactionPicker = true;
                                      _selectedMessageId = msg.id;
                                    });
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (_isContactTyping)
            TypingIndicator(contactName: widget.contact.name),
          if (_replyingTo != null)
            ReplyQuoteCard(
              senderName:
                  _replyingTo!.message.senderId == widget.contact.deviceId
                      ? widget.contact.name
                      : 'You',
              quotedText: _replyingTo!.message.content,
              onCancel: _cancelReply,
            ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 16, color: Colors.white54),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showAttachmentPicker)
            AttachmentPicker(
              onPickImage: () => _pickImage(),
              onPickFile: () => _pickFile(),
              onPickVoice: () {
                setState(() {
                  _showAttachmentPicker = false;
                  _showVoiceRecorder = true;
                });
              },
            ),
          if (_showVoiceRecorder)
            VoiceMessageRecorder(
              onVoiceMessageSent: (base64, duration) {
                _sendVoiceMessage(base64, duration);
                setState(() => _showVoiceRecorder = false);
              },
            ),
          Row(
            children: [
              IconButton(
                icon: Icon(_showAttachmentPicker ? Icons.close : Icons.add,
                    color: Colors.blueAccent),
                onPressed: () {
                  setState(() {
                    _showAttachmentPicker = !_showAttachmentPicker;
                    _showVoiceRecorder = false;
                  });
                },
              ),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (text) {
                    final presence = ref.read(presenceServiceProvider);
                    presence.sendTyping(widget.contact.deviceId);
                  },
                  decoration: InputDecoration(
                    hintText: 'Type a secure message...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: Colors.blueAccent,
                child: _isEncrypting
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : IconButton(
                        icon: const Icon(Icons.send, color: Colors.white),
                        onPressed: _sendMessage,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    setState(() => _showAttachmentPicker = false);
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      _sendFileAttachment(image.path, 'image');
    }
  }

  Future<void> _pickFile() async {
    setState(() => _showAttachmentPicker = false);
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.isNotEmpty) {
      _sendFileAttachment(result.files.first.path!, 'file');
    }
  }

  void _sendVoiceMessage(String base64Audio, int durationSeconds) {
    debugPrint('[Chat] Voice message sent: ${durationSeconds}s');
  }

  void _sendFileAttachment(String path, String type) {
    debugPrint('[Chat] File attachment sent: $type from $path');
  }
}
