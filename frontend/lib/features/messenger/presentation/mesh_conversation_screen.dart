import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/mesh/mesh_message.dart';
import '../../../core/providers/app_providers.dart';

/// Mesh Conversation Screen — WhatsApp-style 1:1 chat over BLE mesh.
class MeshConversationScreen extends ConsumerStatefulWidget {
  final String contactId;
  final String contactName;

  const MeshConversationScreen({
    super.key,
    required this.contactId,
    required this.contactName,
  });

  @override
  ConsumerState<MeshConversationScreen> createState() =>
      _MeshConversationScreenState();
}

class _MeshConversationScreenState extends ConsumerState<MeshConversationScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<MeshMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _listenForIncoming();
  }

  void _loadMessages() {
    final chatService = ref.read(meshChatServiceProvider);
    final identity = ref.read(currentIdentityProvider);
    if (identity == null) return;

    setState(() {
      _messages = chatService.getMessages(identity.deviceId, widget.contactId);
    });

    // Mark as read
    chatService.markAsRead(identity.deviceId, widget.contactId);
    _scrollToBottom();
  }

  void _listenForIncoming() {
    final bleService = ref.read(bleMeshServiceProvider);
    bleService.incomingMessages.listen((message) {
      if (message.senderId == widget.contactId) {
        final chatService = ref.read(meshChatServiceProvider);
        chatService.saveMessage(message);
        _loadMessages();
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final identity = ref.read(currentIdentityProvider);
    if (identity == null) return;

    final message = MeshMessage(
      senderId: identity.deviceId,
      senderName: identity.username,
      recipientId: widget.contactId,
      content: text,
    );

    _messageController.clear();

    // Save locally
    final chatService = ref.read(meshChatServiceProvider);
    await chatService.saveMessage(message);

    // Send via mesh router
    final router = ref.read(meshRouterProvider);
    final result = await router.send(message);

    // Update status
    if (result.success) {
      await chatService.updateMessageStatus(
        identity.deviceId, widget.contactId, message.id, MessageStatus.sent,
      );
    }

    _loadMessages();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(currentIdentityProvider);
    final myId = identity?.deviceId ?? '';

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        backgroundColor: ChaayaTheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: ChaayaTheme.accent.withOpacity(0.2),
              child: Text(
                widget.contactName[0].toUpperCase(),
                style: const TextStyle(
                  color: ChaayaTheme.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.contactName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                Row(
                  children: [
                    ChaayaTheme.statusDot('nearby'),
                    const SizedBox(width: 4),
                    const Text(
                      'Nearby • BLE',
                      style: TextStyle(fontSize: 11, color: ChaayaTheme.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_outlined, color: ChaayaTheme.safeGreen),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined, color: ChaayaTheme.bleColor),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: ChaayaTheme.textSecondary),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Channel info bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: ChaayaTheme.accent.withOpacity(0.08),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock, size: 12, color: ChaayaTheme.accent),
                const SizedBox(width: 6),
                Text(
                  'End-to-end encrypted • BLE Mesh',
                  style: TextStyle(
                    fontSize: 11,
                    color: ChaayaTheme.accent.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyChat()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = msg.senderId == myId;
                      return _MessageBubble(message: msg, isMe: isMe);
                    },
                  ),
          ),

          // Message input
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: ChaayaTheme.accent.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_outline, size: 32, color: ChaayaTheme.accent),
          ),
          const SizedBox(height: 16),
          Text(
            'Chat with ${widget.contactName}',
            style: ChaayaTheme.heading3,
          ),
          const SizedBox(height: 6),
          const Text(
            'Messages are encrypted end-to-end\nand sent directly over the mesh.',
            textAlign: TextAlign.center,
            style: ChaayaTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: ChaayaTheme.surface,
        border: Border(top: BorderSide(color: ChaayaTheme.glassBorder, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Attachment button
            IconButton(
              icon: const Icon(Icons.attach_file, color: ChaayaTheme.textMuted),
              onPressed: () {},
            ),

            // Text field
            Expanded(
              child: Container(
                decoration: ChaayaTheme.glassDecoration(borderRadius: 24),
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(color: ChaayaTheme.textPrimary, fontSize: 15),
                  maxLines: 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'Message',
                    hintStyle: const TextStyle(color: ChaayaTheme.textMuted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.emoji_emotions_outlined, color: ChaayaTheme.textMuted, size: 22),
                      onPressed: () {},
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Send button
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: ChaayaTheme.accent,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send, size: 20, color: Colors.white),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual message bubble
class _MessageBubble extends StatelessWidget {
  final MeshMessage message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 3,
          bottom: 3,
          left: isMe ? 60 : 0,
          right: isMe ? 0 : 60,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? ChaayaTheme.accent.withOpacity(0.2)
              : ChaayaTheme.surfaceLight,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(
            color: isMe
                ? ChaayaTheme.accent.withOpacity(0.15)
                : ChaayaTheme.glassBorder,
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.content,
              style: const TextStyle(
                color: ChaayaTheme.textPrimary,
                fontSize: 14.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: const TextStyle(
                    fontSize: 11,
                    color: ChaayaTheme.textMuted,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _statusIcon(message.status),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.queued:
        return const Icon(Icons.access_time, size: 14, color: ChaayaTheme.textMuted);
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 14, color: ChaayaTheme.textMuted);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: ChaayaTheme.textMuted);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 14, color: ChaayaTheme.bleColor);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 14, color: ChaayaTheme.sosRed);
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

