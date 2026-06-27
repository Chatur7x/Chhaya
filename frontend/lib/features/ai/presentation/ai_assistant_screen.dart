import 'package:flutter/material.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../data/ai_assistant_service.dart';

/// AI Assistant Screen — chat-style interface for offline survival intelligence.
class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({super.key});

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _aiService = AIAssistantService();
  final List<_ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _aiService.initialize();
    // Welcome message
    _messages.add(_ChatMessage(
      text: 'I\'m your offline AI survival assistant. Ask me about:\n'
          '• First aid (CPR, bleeding, fractures)\n'
          '• Water purification\n'
          '• Fire starting & shelter building\n'
          '• Navigation without GPS\n'
          '• Rescue signaling\n'
          '• Medical triage',
      isAI: true,
    ));
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isAI: false));
    });
    _controller.clear();

    // Get AI response
    final response = _aiService.ask(text);
    setState(() {
      _messages.add(_ChatMessage(
        text: response.answer,
        isAI: true,
        confidence: response.confidence,
        category: response.category,
      ));
    });

    _scrollToBottom();
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        backgroundColor: ChaayaTheme.background,
        title: const Row(
          children: [
            Icon(Icons.smart_toy, color: ChaayaTheme.warningYellow, size: 22),
            SizedBox(width: 10),
            Text('AI Assistant'),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: ChaayaTheme.safeGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.wifi_off, size: 12, color: ChaayaTheme.safeGreen),
                SizedBox(width: 4),
                Text('Offline', style: TextStyle(fontSize: 11, color: ChaayaTheme.safeGreen)),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Quick topic buttons
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _topicChip('🏥 First Aid'),
                _topicChip('💧 Water'),
                _topicChip('🔥 Fire'),
                _topicChip('🏕️ Shelter'),
                _topicChip('🧭 Navigation'),
                _topicChip('📡 Signaling'),
                _topicChip('🌡️ Hypothermia'),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, i) => _buildBubble(_messages[i]),
            ),
          ),

          // Input
          _buildInput(),
        ],
      ),
    );
  }

  Widget _topicChip(String label) {
    return GestureDetector(
      onTap: () {
        _controller.text = label.replaceAll(RegExp(r'[^\w\s]'), '').trim();
        _sendMessage();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: ChaayaTheme.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ChaayaTheme.glassBorder),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, color: ChaayaTheme.textSecondary)),
      ),
    );
  }

  Widget _buildBubble(_ChatMessage msg) {
    return Align(
      alignment: msg.isAI ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: EdgeInsets.only(
          top: 4, bottom: 4,
          left: msg.isAI ? 0 : 48,
          right: msg.isAI ? 48 : 0,
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: msg.isAI
              ? ChaayaTheme.surfaceLight
              : ChaayaTheme.accent.withOpacity(0.2),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isAI ? 4 : 16),
            bottomRight: Radius.circular(msg.isAI ? 16 : 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.isAI && msg.category != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: msg.category == 'medical'
                      ? ChaayaTheme.sosRed.withOpacity(0.15)
                      : ChaayaTheme.safeGreen.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  msg.category == 'medical' ? '🏥 Medical' : '🏕️ Survival',
                  style: TextStyle(
                    fontSize: 10,
                    color: msg.category == 'medical' ? ChaayaTheme.sosRed : ChaayaTheme.safeGreen,
                  ),
                ),
              ),
            Text(
              msg.text,
              style: const TextStyle(color: ChaayaTheme.textPrimary, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
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
            Expanded(
              child: Container(
                decoration: ChaayaTheme.glassDecoration(borderRadius: 24),
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: ChaayaTheme.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Ask a survival question...',
                    hintStyle: TextStyle(color: ChaayaTheme.textMuted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(color: ChaayaTheme.accent, shape: BoxShape.circle),
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

class _ChatMessage {
  final String text;
  final bool isAI;
  final double? confidence;
  final String? category;
  _ChatMessage({required this.text, required this.isAI, this.confidence, this.category});
}

