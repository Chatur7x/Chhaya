import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/presentation/widgets/glass_container.dart';
import '../../../core/mesh/mesh_message.dart';
import '../../../core/providers/app_providers.dart';
import '../../contacts/data/contact_service.dart';
import '../../contacts/domain/models/contact.dart';
import '../../../core/crypto/signal_protocol_service.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  final Contact contact;
  const ConversationScreen({super.key, required this.contact});

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _messageController = TextEditingController();
  final List<MeshMessage> _messages = [];
  bool _isEncrypting = false;

  StreamSubscription? _bleSub;
  StreamSubscription? _wifiSub;

  @override
  void initState() {
    super.initState();
    _setupMessageListeners();
  }

  void _setupMessageListeners() {
    // Listen to incoming messages via BLE
    final ble = ref.read(bleMeshServiceProvider);
    _bleSub = ble.incomingMessages.listen((msg) {
      if (msg.senderId == widget.contact.deviceId) {
        _handleIncomingEncrypted(msg);
      }
    });

    // Listen to incoming messages via WiFi Direct
    final wifi = ref.read(wifiDirectServiceProvider);
    _wifiSub = wifi.incomingMessages.listen((msg) {
      if (msg.senderId == widget.contact.deviceId) {
        _handleIncomingEncrypted(msg);
      }
    });
  }

  Future<void> _handleIncomingEncrypted(MeshMessage msg) async {
    final crypto = ref.read(signalProtocolProvider);
    try {
      final payloadJson = jsonDecode(msg.content);
      final payload = EncryptedPayload.fromJson(payloadJson);
      final decryptedText = await crypto.decrypt(widget.contact.deviceId, payload);
      
      if (mounted) {
        setState(() {
          _messages.add(msg.copyWith(content: decryptedText));
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

    try {
      // Ensure session exists
      await crypto.getOrCreateSession(widget.contact.deviceId, widget.contact.publicKey);
      
      // Encrypt the text using Signal protocol
      final payload = await crypto.encrypt(widget.contact.deviceId, text);
      
      // Build offline mesh message
      final msg = MeshMessage(
        senderId: myIdentity.deviceId,
        senderName: myIdentity.username,
        recipientId: widget.contact.deviceId,
        content: jsonEncode(payload.toJson()), // send encrypted payload as content
      );

      // Save to local UI unencrypted for display
      if (mounted) {
        setState(() {
          _messageController.clear();
          _messages.add(msg.copyWith(content: text));
        });
      }

      // Route it (BLE -> WiFi Direct -> Queue)
      await router.send(msg);

    } catch (e) {
      debugPrint('[Chat] Send failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Encryption failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isEncrypting = false);
      }
    }
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    _wifiSub?.cancel();
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
                  child: Text(widget.contact.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.contact.name, style: const TextStyle(fontSize: 16)),
                    Row(
                      children: [
                        const Icon(Icons.lock, size: 10, color: Colors.greenAccent),
                        const SizedBox(width: 4),
                        Text(widget.contact.status == ContactStatus.nearby ? 'Directly connected' : 'Offline mesh', 
                          style: const TextStyle(fontSize: 10, color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(icon: const Icon(Icons.videocam), onPressed: () {}),
              IconButton(icon: const Icon(Icons.call), onPressed: () {}),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty 
              ? const Center(child: Text('Secure E2EE established.\nMessages are routed offline.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)))
              : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg.senderId != widget.contact.deviceId;
                
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blueAccent : Colors.white.withOpacity(0.1),
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
                          style: TextStyle(color: isMe ? Colors.white : Colors.white70),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isMe) const Icon(Icons.lock_outline, size: 10, color: Colors.white54),
                            if (isMe) const SizedBox(width: 4),
                            Text('${msg.timestamp.hour}:${msg.timestamp.minute.toString().padLeft(2, '0')}', style: TextStyle(color: isMe ? Colors.white70 : Colors.grey, fontSize: 10)),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.black,
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.add, color: Colors.blueAccent), onPressed: () {}),
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Type a secure message...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.blueAccent,
            child: _isEncrypting
              ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: _sendMessage,
                ),
          ),
        ],
      ),
    );
  }
}
