import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

class GossipMessage {
  final String messageId;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final int ttl;
  final Set<String> seenBy;

  GossipMessage({
    required this.messageId,
    required this.senderId,
    required this.content,
    required this.timestamp,
    required this.ttl,
    Set<String>? seenBy,
  }) : seenBy = seenBy ?? {};

  GossipMessage copyWith({Set<String>? seenBy}) {
    return GossipMessage(
      messageId: messageId,
      senderId: senderId,
      content: content,
      timestamp: timestamp,
      ttl: ttl,
      seenBy: seenBy ?? this.seenBy,
    );
  }

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'senderId': senderId,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'ttl': ttl,
        'seenBy': seenBy.toList(),
      };

  factory GossipMessage.fromJson(Map<String, dynamic> json) {
    return GossipMessage(
      messageId: json['messageId'],
      senderId: json['senderId'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      ttl: json['ttl'],
      seenBy: Set<String>.from(json['seenBy'] ?? []),
    );
  }
}

class SummaryVector {
  final Map<String, Set<String>> _messagesByNode = {};

  SummaryVector();

  void addMessage(String nodeId, String messageId) {
    _messagesByNode[nodeId] ??= {};
    _messagesByNode[nodeId]!.add(messageId);
  }

  void removeMessage(String nodeId, String messageId) {
    _messagesByNode[nodeId]?.remove(messageId);
  }

  Set<String> getMessagesForNode(String nodeId) {
    return Set.from(_messagesByNode[nodeId] ?? {});
  }

  Set<String> getMissingMessages(String nodeId, SummaryVector other) {
    final myMessages = getMessagesForNode(nodeId);
    final theirMessages = other.getMessagesForNode(nodeId);
    return myMessages.difference(theirMessages);
  }

  Set<String> getAllMessageIds() {
    final all = <String>{};
    for (final messages in _messagesByNode.values) {
      all.addAll(messages);
    }
    return all;
  }

  Map<String, dynamic> toJson() => {
        'messages': _messagesByNode.map((k, v) => MapEntry(k, v.toList())),
      };

  factory SummaryVector.fromJson(Map<String, dynamic> json) {
    final sv = SummaryVector();
    final messages = json['messages'] as Map<String, dynamic>?;
    if (messages != null) {
      for (final entry in messages.entries) {
        sv._messagesByNode[entry.key] = Set<String>.from(entry.value as List);
      }
    }
    return sv;
  }
}

class EncounterRecord {
  final String nodeId;
  final DateTime encounterTime;
  final int rssi;
  final Duration duration;
  final SummaryVector summaryVector;

  EncounterRecord({
    required this.nodeId,
    required this.encounterTime,
    required this.rssi,
    required this.duration,
    required this.summaryVector,
  });
}

class EpidemicSpreadProtocol {
  final Map<String, GossipMessage> _messageStore = {};
  final Map<String, EncounterRecord> _recentEncounters = {};
  final Map<String, SummaryVector> _nodeSummaries = {};
  final Random _random = Random.secure();

  static const int _maxMessagesPerNode = 1000;
  static const int _defaultTTL = 7;
  static const Duration _encounterWindow = Duration(minutes: 30);
  static const int _spreadFactor = 3;
  static const int _maxHopCount = 5;

  Timer? _cleanupTimer;
  bool _isActive = false;

  final _messageController = StreamController<GossipMessage>.broadcast();
  Stream<GossipMessage> get messageStream => _messageController.stream;

  final _syncController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get syncStream => _syncController.stream;

  String _nodeId = '';

  void initialize(String nodeId) {
    _nodeId = nodeId;
    _isActive = true;
    _startCleanupTimer();
    debugPrint('EpidemicSpreadProtocol initialized for: $nodeId');
  }

  void _startCleanupTimer() {
    _cleanupTimer =
        Timer.periodic(const Duration(minutes: 5), (_) => _cleanup());
  }

  void _cleanup() {
    final expiredEncounters = <String>[];

    for (final entry in _recentEncounters.entries) {
      if (DateTime.now().difference(entry.value.encounterTime) >
          _encounterWindow) {
        expiredEncounters.add(entry.key);
      }
    }

    for (final id in expiredEncounters) {
      _recentEncounters.remove(id);
    }

    _pruneOldMessages();
  }

  void _pruneOldMessages() {
    final toRemove = <String>[];

    for (final entry in _messageStore.entries) {
      if (entry.value.ttl <= 0) {
        toRemove.add(entry.key);
      }
    }

    for (final id in toRemove) {
      _messageStore.remove(id);
      for (final summary in _nodeSummaries.values) {
        summary.removeMessage(_nodeId, id);
      }
    }
  }

  String disseminate({
    required String content,
    int ttl = _defaultTTL,
    int hopCount = 0,
  }) {
    if (!_isActive) {
      throw Exception('Protocol not initialized');
    }

    final messageId = 'GOSSIP_${DateTime.now().millisecondsSinceEpoch}';

    final message = GossipMessage(
      messageId: messageId,
      senderId: _nodeId,
      content: content,
      timestamp: DateTime.now(),
      ttl: ttl,
      seenBy: {_nodeId},
    );

    _messageStore[messageId] = message;
    _nodeSummaries[_nodeId]?.addMessage(_nodeId, messageId);
    _nodeSummaries[_nodeId] ??= SummaryVector()..addMessage(_nodeId, messageId);

    _messageController.add(message);
    debugPrint('Message disseminated: $messageId');

    return messageId;
  }

  SummaryVector createSummaryVector() {
    _nodeSummaries[_nodeId] ??= SummaryVector();

    for (final message in _messageStore.values) {
      if (!message.seenBy.contains(_nodeId)) {
        _nodeSummaries[_nodeId]!
            .addMessage(message.senderId, message.messageId);
      }
    }

    return _nodeSummaries[_nodeId]!;
  }

  List<GossipMessage> performAntiEntropy(
      String peerId, SummaryVector peerSummary) {
    final mySummary = createSummaryVector();
    final messagesToReceive = <GossipMessage>[];

    for (final nodeId in peerSummary.getAllMessageIds()) {
      final missingFromPeer = peerSummary.getMissingMessages(nodeId, mySummary);

      for (final messageId in missingFromPeer) {
        final message = _messageStore[messageId];
        if (message != null &&
            message.ttl > 0 &&
            message.seenBy.length < _maxHopCount) {
          messagesToReceive.add(message);
        }
      }
    }

    _syncController.add({
      'peerId': peerId,
      'messagesExchanged': messagesToReceive.length,
      'timestamp': DateTime.now().toIso8601String(),
    });

    return messagesToReceive;
  }

  void receiveMessage(GossipMessage message, String fromNodeId) {
    final existing = _messageStore[message.messageId];

    if (existing == null) {
      final updatedMessage = message.copyWith(
        seenBy: {...message.seenBy, _nodeId},
      );
      _messageStore[message.messageId] = updatedMessage;
      _nodeSummaries[_nodeId]?.addMessage(message.senderId, message.messageId);
      _messageController.add(updatedMessage);
      debugPrint('New gossip received: ${message.messageId}');
    } else {
      final combinedSeenBy = {...existing.seenBy, _nodeId, fromNodeId};
      if (combinedSeenBy.length > existing.seenBy.length) {
        final updatedMessage = existing.copyWith(seenBy: combinedSeenBy);
        _messageStore[message.messageId] = updatedMessage;
      }
    }
  }

  void recordEncounter(String peerId, int rssi, SummaryVector peerSummary) {
    final encounter = EncounterRecord(
      nodeId: peerId,
      encounterTime: DateTime.now(),
      rssi: rssi,
      duration: Duration.zero,
      summaryVector: peerSummary,
    );

    _recentEncounters[peerId] = encounter;
    _nodeSummaries[peerId] = peerSummary;
  }

  List<String> getPeersForGossip({int limit = _spreadFactor}) {
    final now = DateTime.now();
    final eligible = _recentEncounters.entries
        .where((e) => now.difference(e.value.encounterTime) <= _encounterWindow)
        .where((e) => e.value.rssi > -80)
        .toList();

    eligible.sort((a, b) => b.value.rssi.compareTo(a.value.rssi));

    return eligible.take(limit).map((e) => e.key).toList();
  }

  List<GossipMessage> getMessagesToForward(String peerId) {
    final peerSummary = _nodeSummaries[peerId];
    if (peerSummary == null) return [];

    final messagesToForward = <GossipMessage>[];

    for (final message in _messageStore.values) {
      if (!message.seenBy.contains(peerId) && message.ttl > 0) {
        messagesToForward.add(message);
      }
    }

    messagesToForward.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return messagesToForward.take(_spreadFactor).toList();
  }

  void decrementTTL() {
    for (final entry in _messageStore.entries) {
      if (entry.value.ttl > 0) {
        _messageStore[entry.key] = GossipMessage(
          messageId: entry.value.messageId,
          senderId: entry.value.senderId,
          content: entry.value.content,
          timestamp: entry.value.timestamp,
          ttl: entry.value.ttl - 1,
          seenBy: entry.value.seenBy,
        );
      }
    }
  }

  GossipMessage? getMessage(String messageId) => _messageStore[messageId];

  List<GossipMessage> getAllMessages() => _messageStore.values.toList();

  List<GossipMessage> getMessagesForSender(String senderId) {
    return _messageStore.values.where((m) => m.senderId == senderId).toList();
  }

  Map<String, dynamic> getStatistics() {
    return {
      'totalMessages': _messageStore.length,
      'activePeers': _recentEncounters.length,
      'recentEncounters': _recentEncounters.keys.toList(),
      'messageSpread': {
        for (final message in _messageStore.values)
          message.messageId: message.seenBy.length,
      },
    };
  }

  void dispose() {
    _isActive = false;
    _cleanupTimer?.cancel();
    _messageController.close();
    _syncController.close();
  }
}
