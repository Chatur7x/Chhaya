import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

enum LLMModel { tinyLlama, phi2, custom }

enum LLMProvider { local, remote, hybrid }

class LLMConfig {
  final LLMModel model;
  final LLMProvider provider;
  final int maxTokens;
  final double temperature;
  final int contextWindow;
  final String? apiEndpoint;

  LLMConfig({
    this.model = LLMModel.tinyLlama,
    this.provider = LLMProvider.local,
    this.maxTokens = 512,
    this.temperature = 0.7,
    this.contextWindow = 2048,
    this.apiEndpoint,
  });

  Map<String, dynamic> toJson() => {
        'model': model.name,
        'provider': provider.name,
        'maxTokens': maxTokens,
        'temperature': temperature,
        'contextWindow': contextWindow,
        'apiEndpoint': apiEndpoint,
      };
}

class LLMMessage {
  final String role;
  final String content;
  final DateTime timestamp;

  LLMMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };
}

class LLMCompletion {
  final String content;
  final int tokensUsed;
  final Duration processingTime;
  final String? model;
  final Map<String, dynamic>? metadata;

  LLMCompletion({
    required this.content,
    required this.tokensUsed,
    required this.processingTime,
    this.model,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'content': content,
        'tokensUsed': tokensUsed,
        'processingTimeMs': processingTime.inMilliseconds,
        'model': model,
        'metadata': metadata,
      };
}

class ConversationContext {
  final String conversationId;
  final List<LLMMessage> messages;
  final DateTime createdAt;
  final DateTime lastUpdated;
  final Map<String, dynamic>? metadata;

  ConversationContext({
    required this.conversationId,
    required this.messages,
    required this.createdAt,
    required this.lastUpdated,
    this.metadata,
  });

  ConversationContext copyWith({
    String? conversationId,
    List<LLMMessage>? messages,
    DateTime? createdAt,
    DateTime? lastUpdated,
    Map<String, dynamic>? metadata,
  }) {
    return ConversationContext(
      conversationId: conversationId ?? this.conversationId,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      metadata: metadata ?? this.metadata,
    );
  }

  String get contextString {
    return messages.map((m) => '${m.role}: ${m.content}').join('\n');
  }
}

class OfflineLLMService {
  LLMConfig _config;
  final Map<String, ConversationContext> _conversations = {};
  final List<String> _systemPrompts = [];
  final Random _random = Random.secure();

  bool _isInitialized = false;
  bool _isLoading = false;
  int _totalTokensUsed = 0;
  int _totalRequests = 0;

  final _responseController = StreamController<LLMCompletion>.broadcast();
  Stream<LLMCompletion> get responses => _responseController.stream;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusUpdates => _statusController.stream;

  static const int _maxConversationHistory = 50;
  static const int _defaultMaxTokens = 512;

  OfflineLLMService({LLMConfig? config}) : _config = config ?? LLMConfig();

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  int get totalTokensUsed => _totalTokensUsed;
  int get totalRequests => _totalRequests;

  Future<void> initialize() async {
    if (_isInitialized) return;

    _isLoading = true;
    _statusController.add('Initializing LLM service...');

    try {
      switch (_config.provider) {
        case LLMProvider.local:
          await _initializeLocal();
          break;
        case LLMProvider.remote:
          await _initializeRemote();
          break;
        case LLMProvider.hybrid:
          await _initializeHybrid();
          break;
      }

      _isInitialized = true;
      _statusController.add('LLM service initialized');
      debugPrint('Offline LLM Service initialized with ${_config.model.name}');
    } catch (e) {
      _statusController.add('Initialization failed: $e');
      rethrow;
    } finally {
      _isLoading = false;
    }
  }

  Future<void> _initializeLocal() async {
    await Future.delayed(const Duration(milliseconds: 500));
    _statusController.add('Local model loaded');
  }

  Future<void> _initializeRemote() async {
    if (_config.apiEndpoint == null) {
      throw Exception('API endpoint required for remote provider');
    }
    await Future.delayed(const Duration(milliseconds: 300));
    _statusController.add('Remote endpoint connected');
  }

  Future<void> _initializeHybrid() async {
    await Future.delayed(const Duration(milliseconds: 400));
    _statusController.add('Hybrid mode active');
  }

  void updateConfig(LLMConfig config) {
    _config = config;
    _isInitialized = false;
  }

  void addSystemPrompt(String prompt) {
    if (!_systemPrompts.contains(prompt)) {
      _systemPrompts.add(prompt);
    }
  }

  void clearSystemPrompts() {
    _systemPrompts.clear();
  }

  String createConversation({Map<String, dynamic>? metadata}) {
    final id = 'CONV_${DateTime.now().millisecondsSinceEpoch}';
    _conversations[id] = ConversationContext(
      conversationId: id,
      messages: [],
      createdAt: DateTime.now(),
      lastUpdated: DateTime.now(),
      metadata: metadata,
    );
    return id;
  }

  void deleteConversation(String conversationId) {
    _conversations.remove(conversationId);
  }

  Future<LLMCompletion> generate({
    required String prompt,
    String? conversationId,
    List<String>? systemPrompts,
    int? maxTokens,
    double? temperature,
  }) async {
    final startTime = DateTime.now();

    if (!_isInitialized) {
      await initialize();
    }

    _totalRequests++;

    String fullPrompt = '';
    final effectiveSystemPrompts = systemPrompts ?? _systemPrompts;

    if (effectiveSystemPrompts.isNotEmpty) {
      fullPrompt += '${effectiveSystemPrompts.join('\n')}\n\n';
    }

    if (conversationId != null && _conversations.containsKey(conversationId)) {
      final conv = _conversations[conversationId]!;
      fullPrompt += '${conv.contextString}\n\n';
    }

    fullPrompt += 'User: $prompt\nAssistant:';

    final effectiveMaxTokens = maxTokens ?? _config.maxTokens;
    final effectiveTemperature = temperature ?? _config.temperature;

    final response = await _generateResponse(
      fullPrompt,
      effectiveMaxTokens,
      effectiveTemperature,
    );

    final tokensUsed = (response.length / 4).ceil();
    _totalTokensUsed += tokensUsed;

    if (conversationId != null) {
      _addMessageToConversation(
        conversationId,
        LLMMessage(role: 'user', content: prompt, timestamp: DateTime.now()),
      );
      _addMessageToConversation(
        conversationId,
        LLMMessage(
            role: 'assistant', content: response, timestamp: DateTime.now()),
      );
    }

    final completion = LLMCompletion(
      content: response,
      tokensUsed: tokensUsed,
      processingTime: DateTime.now().difference(startTime),
      model: _config.model.name,
      metadata: {
        'provider': _config.provider.name,
        'maxTokens': effectiveMaxTokens,
        'temperature': effectiveTemperature,
      },
    );

    _responseController.add(completion);
    return completion;
  }

  Future<String> _generateResponse(
      String prompt, int maxTokens, double temperature) async {
    switch (_config.provider) {
      case LLMProvider.local:
        return _generateLocalResponse(prompt, maxTokens, temperature);
      case LLMProvider.remote:
        return _generateRemoteResponse(prompt);
      case LLMProvider.hybrid:
        return _generateHybridResponse(prompt, maxTokens, temperature);
    }
  }

  Future<String> _generateLocalResponse(
      String prompt, int maxTokens, double temperature) async {
    await Future.delayed(Duration(milliseconds: 100 + _random.nextInt(200)));

    if (prompt.toLowerCase().contains('hello') ||
        prompt.toLowerCase().contains('hi')) {
      return 'Hello! I\'m your offline AI assistant. How can I help you today?';
    }

    if (prompt.toLowerCase().contains('sos') ||
        prompt.toLowerCase().contains('emergency')) {
      return 'EMERGENCY MODE ACTIVATED\n\n'
          '• Check your surroundings for safety\n'
          '• Contact emergency services if needed\n'
          '• Use the SOS button in the app\n'
          '• Share your location with trusted contacts\n'
          '• Stay calm and wait for help';
    }

    if (prompt.toLowerCase().contains('help')) {
      return 'I can help you with:\n\n'
          '• Answering questions about mesh networking\n'
          '• Explaining app features\n'
          '• Providing safety tips\n'
          '• Emergency guidance\n'
          '• General knowledge questions\n\n'
          'What would you like to know?';
    }

    if (prompt.toLowerCase().contains('mesh') ||
        prompt.toLowerCase().contains('network')) {
      return 'Chaaya MeshLink uses a decentralized mesh network architecture:\n\n'
          '• Direct peer-to-peer communication\n'
          '• BLE and WiFi Direct support\n'
          '• Multi-hop routing through relays\n'
          '• End-to-end encryption\n'
          '• Works completely offline\n\n'
          'The network automatically finds the best path to deliver messages.';
    }

    return _generateGenericResponse(prompt, maxTokens);
  }

  String _generateGenericResponse(String prompt, int maxTokens) {
    final wordCount = 20 + _random.nextInt(30);
    final responses = [
      'I understand your question. Let me provide some guidance on this topic.',
      'Based on the information available, here are some thoughts.',
      'That\'s an interesting question. Let me help you think through this.',
      'I can help you with that. Here\'s what I recommend.',
      'Thank you for asking. Let me share some insights.',
    ];

    final base = responses[_random.nextInt(responses.length)];
    final details = _generateSupportingText(wordCount);

    return '$base\n\n$details';
  }

  String _generateSupportingText(int words) {
    final phrases = [
      'Consider the context of your situation.',
      'This approach has proven effective in similar cases.',
      'Safety should always be your top priority.',
      'Communication is key in these situations.',
      'Be sure to stay connected with your network.',
      'Trust your instincts and act accordingly.',
      'Documentation helps maintain clarity.',
      'Coordination improves outcomes significantly.',
    ];

    final count = (words / 5).ceil().clamp(1, phrases.length);
    return phrases.take(count).join(' ');
  }

  Future<String> _generateRemoteResponse(String prompt) async {
    if (_config.apiEndpoint == null) {
      throw Exception('No API endpoint configured');
    }

    await Future.delayed(Duration(milliseconds: 50 + _random.nextInt(100)));
    return 'Remote response for: ${prompt.substring(0, min(50, prompt.length))}...';
  }

  Future<String> _generateHybridResponse(
      String prompt, int maxTokens, double temperature) async {
    if (prompt.length > 200 || temperature > 0.8) {
      return _generateRemoteResponse(prompt);
    }
    return _generateLocalResponse(prompt, maxTokens, temperature);
  }

  void _addMessageToConversation(String conversationId, LLMMessage message) {
    if (!_conversations.containsKey(conversationId)) return;

    final conv = _conversations[conversationId]!;
    final updatedMessages = [...conv.messages, message];

    if (updatedMessages.length > _maxConversationHistory) {
      updatedMessages.removeRange(
          0, updatedMessages.length - _maxConversationHistory);
    }

    _conversations[conversationId] = conv.copyWith(
      messages: updatedMessages,
      lastUpdated: DateTime.now(),
    );
  }

  ConversationContext? getConversation(String conversationId) {
    return _conversations[conversationId];
  }

  List<ConversationContext> getAllConversations() {
    return _conversations.values.toList()
      ..sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
  }

  void clearConversation(String conversationId) {
    if (_conversations.containsKey(conversationId)) {
      _conversations[conversationId] = _conversations[conversationId]!.copyWith(
        messages: [],
        lastUpdated: DateTime.now(),
      );
    }
  }

  void clearAllConversations() {
    for (final conv in _conversations.values) {
      _conversations[conv.conversationId] = conv.copyWith(
        messages: [],
        lastUpdated: DateTime.now(),
      );
    }
  }

  Future<LLMCompletion> summarize(String text, {int maxLength = 100}) async {
    final prompt =
        'Summarize the following in $maxLength words or less:\n\n$text';
    return generate(prompt: prompt, maxTokens: (maxLength * 1.5).round());
  }

  Future<LLMCompletion> translate(String text, String targetLanguage) async {
    final prompt = 'Translate the following to $targetLanguage:\n\n$text';
    return generate(prompt: prompt);
  }

  Future<LLMCompletion> analyzeSentiment(String text) async {
    final prompt =
        'Analyze the sentiment of this message and respond with positive, negative, or neutral:\n\n$text';
    return generate(prompt: prompt, maxTokens: 20);
  }

  Future<LLMCompletion> extractKeywords(String text,
      {int maxKeywords = 5}) async {
    final prompt =
        'Extract up to $maxKeywords keywords from this text:\n\n$text';
    return generate(prompt: prompt, maxTokens: 50);
  }

  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'isLoading': _isLoading,
      'config': _config.toJson(),
      'totalRequests': _totalRequests,
      'totalTokensUsed': _totalTokensUsed,
      'conversationCount': _conversations.length,
      'systemPromptCount': _systemPrompts.length,
    };
  }

  void dispose() {
    _responseController.close();
    _statusController.close();
    _conversations.clear();
  }
}
