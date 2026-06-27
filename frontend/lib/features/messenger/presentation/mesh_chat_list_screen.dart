import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../data/mesh_chat_service.dart';
import 'mesh_conversation_screen.dart';

/// Mesh Chat List — WhatsApp-style conversation list.
class MeshChatListScreen extends ConsumerWidget {
  const MeshChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationListProvider);

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        backgroundColor: ChaayaTheme.background,
        title: const Row(
          children: [
            Icon(Icons.cell_tower_rounded, color: ChaayaTheme.accent, size: 24),
            SizedBox(width: 10),
            Text('Chaaya'),
          ],
        ),
        actions: [
          // Channel status indicator
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: ChaayaTheme.channelBadge('ble'),
          ),
        ],
      ),
      body: conversations.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: conversations.length,
              itemBuilder: (context, index) {
                return _ConversationTile(
                  conversation: conversations[index],
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MeshConversationScreen(
                          contactId: conversations[index].contactId,
                          contactName: conversations[index].contactName,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  ChaayaTheme.accent.withValues(alpha: 0.15),
                  ChaayaTheme.bleColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: ChaayaTheme.accent.withValues(alpha: 0.1),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
              border: Border.all(color: ChaayaTheme.accent.withValues(alpha: 0.2), width: 1.5),
            ),
            child: const Icon(Icons.forum_rounded, size: 48, color: ChaayaTheme.accent),
          ),
          const SizedBox(height: 24),
          const Text('No Active Nodes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: ChaayaTheme.textPrimary, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          const Text(
            'Pair via QR or discover nearby\nnodes over the BLE mesh network.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: ChaayaTheme.textMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatefulWidget {
  final ConversationPreview conversation;
  final VoidCallback onTap;
  
  const _ConversationTile({required this.conversation, required this.onTap});

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutQuart,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        transform: Matrix4.identity()..scale(_pressed ? 0.96 : 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: ChaayaTheme.surfaceLight.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: [
            if (!_pressed)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Glowing Avatar
              Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [ChaayaTheme.accent.withValues(alpha: 0.2), ChaayaTheme.accentLight.withValues(alpha: 0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: ChaayaTheme.accent.withValues(alpha: 0.4), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: ChaayaTheme.accent.withValues(alpha: 0.15), blurRadius: 12),
                  ],
                ),
                child: Center(
                  child: Text(
                    widget.conversation.contactName.isNotEmpty 
                        ? widget.conversation.contactName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ChaayaTheme.accentLight),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              
              // Text Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            widget.conversation.contactName,
                            style: const TextStyle(fontWeight: FontWeight.w600, color: ChaayaTheme.textPrimary, fontSize: 16, letterSpacing: -0.3),
                          ),
                        ),
                        Text(
                          widget.conversation.timeText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: widget.conversation.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                            color: widget.conversation.unreadCount > 0 ? ChaayaTheme.accentLight : ChaayaTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.conversation.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: widget.conversation.unreadCount > 0 ? ChaayaTheme.textSecondary : ChaayaTheme.textMuted,
                            ),
                          ),
                        ),
                        if (widget.conversation.unreadCount > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [ChaayaTheme.gradientStart, ChaayaTheme.gradientEnd]),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${widget.conversation.unreadCount}',
                              style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

