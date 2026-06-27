import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

enum MessagePriority { critical, high, normal, low, background }

enum TrafficClass {
  sos,
  voiceCall,
  videoCall,
  textMessage,
  fileTransfer,
  sync,
  bulk
}

class QoSMessage {
  final String id;
  final String destinationId;
  final String payload;
  final MessagePriority priority;
  final TrafficClass trafficClass;
  final DateTime createdAt;
  final DateTime? deadline;
  final int maxRetries;
  final String? correlationId;

  int retryCount = 0;
  bool acknowledged = false;
  DateTime? sentAt;
  DateTime? deliveredAt;

  QoSMessage({
    required this.id,
    required this.destinationId,
    required this.payload,
    required this.priority,
    required this.trafficClass,
    required this.createdAt,
    this.deadline,
    this.maxRetries = 3,
    this.correlationId,
  });

  int get weight {
    switch (priority) {
      case MessagePriority.critical:
        return 100;
      case MessagePriority.high:
        return 75;
      case MessagePriority.normal:
        return 50;
      case MessagePriority.low:
        return 25;
      case MessagePriority.background:
        return 10;
    }
  }

  bool get isExpired => deadline != null && DateTime.now().isAfter(deadline!);

  Map<String, dynamic> toJson() => {
        'id': id,
        'destinationId': destinationId,
        'payload': payload,
        'priority': priority.name,
        'trafficClass': trafficClass.name,
        'createdAt': createdAt.toIso8601String(),
        'deadline': deadline?.toIso8601String(),
        'maxRetries': maxRetries,
        'correlationId': correlationId,
        'retryCount': retryCount,
        'acknowledged': acknowledged,
      };
}

class BandwidthAllocation {
  final TrafficClass trafficClass;
  double percentage;
  int maxConcurrent;

  BandwidthAllocation({
    required this.trafficClass,
    required this.percentage,
    required this.maxConcurrent,
  });
}

class QoSQueue {
  final int maxSize;
  final List<QoSMessage> _queue = [];
  final Set<String> _set = {};

  QoSQueue({this.maxSize = 1000});

  bool get isEmpty => _queue.isEmpty;
  bool get isFull => _set.length >= maxSize;
  int get length => _set.length;

  bool contains(String id) => _set.contains(id);

  bool add(QoSMessage message) {
    if (isFull || _set.contains(message.id)) return false;
    _queue.add(message);
    _set.add(message.id);
    return true;
  }

  QoSMessage? removeFirst() {
    if (isEmpty) return null;
    final message = _queue.removeAt(0);
    _set.remove(message.id);
    return message;
  }

  QoSMessage? peek() => _queue.isEmpty ? null : _queue.first;

  void remove(String id) {
    _queue.removeWhere((msg) => msg.id == id);
    _set.remove(id);
  }

  List<QoSMessage> toList() => List.from(_queue);
}

class QoSScheduler {
  final Map<TrafficClass, QoSQueue> _queues = {};
  final Map<String, QoSMessage> _pending = {};
  final Map<String, Timer> _deadlineTimers = {};
  final Map<TrafficClass, BandwidthAllocation> _allocations = {};

  static const int _defaultMaxQueueSize = 1000;
  static const Duration _defaultProcessingInterval =
      Duration(milliseconds: 100);

  int _totalBandwidthKBps = 500;
  Timer? _processingTimer;
  bool _isRunning = false;

  final _messageController = StreamController<QoSMessage>.broadcast();
  Stream<QoSMessage> get messageStream => _messageController.stream;

  final _droppedController = StreamController<QoSMessage>.broadcast();
  Stream<QoSMessage> get droppedStream => _droppedController.stream;

  final _metricsController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get metricsStream => _metricsController.stream;

  QoSScheduler() {
    _initQueues();
    _initAllocations();
  }

  void _initQueues() {
    for (final tc in TrafficClass.values) {
      _queues[tc] = QoSQueue(maxSize: _defaultMaxQueueSize);
    }
  }

  void _initAllocations() {
    _allocations[TrafficClass.sos] = BandwidthAllocation(
      trafficClass: TrafficClass.sos,
      percentage: 30,
      maxConcurrent: 10,
    );
    _allocations[TrafficClass.voiceCall] = BandwidthAllocation(
      trafficClass: TrafficClass.voiceCall,
      percentage: 25,
      maxConcurrent: 5,
    );
    _allocations[TrafficClass.videoCall] = BandwidthAllocation(
      trafficClass: TrafficClass.videoCall,
      percentage: 20,
      maxConcurrent: 2,
    );
    _allocations[TrafficClass.textMessage] = BandwidthAllocation(
      trafficClass: TrafficClass.textMessage,
      percentage: 15,
      maxConcurrent: 20,
    );
    _allocations[TrafficClass.fileTransfer] = BandwidthAllocation(
      trafficClass: TrafficClass.fileTransfer,
      percentage: 5,
      maxConcurrent: 3,
    );
    _allocations[TrafficClass.sync] = BandwidthAllocation(
      trafficClass: TrafficClass.sync,
      percentage: 3,
      maxConcurrent: 5,
    );
    _allocations[TrafficClass.bulk] = BandwidthAllocation(
      trafficClass: TrafficClass.bulk,
      percentage: 2,
      maxConcurrent: 2,
    );
  }

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _processingTimer =
        Timer.periodic(_defaultProcessingInterval, (_) => _processQueues());
    debugPrint('QoS Scheduler started');
  }

  void stop() {
    _isRunning = false;
    _processingTimer?.cancel();
    _processingTimer = null;
    debugPrint('QoS Scheduler stopped');
  }

  bool enqueue(QoSMessage message) {
    final queue = _queues[message.trafficClass]!;
    if (queue.isFull) {
      _evictLowestPriority(queue, message.priority);
    }

    if (!queue.add(message)) {
      _droppedController.add(message);
      debugPrint('Message ${message.id} dropped - queue full');
      return false;
    }

    if (message.deadline != null) {
      _deadlineTimers[message.id] = Timer(
        message.deadline!.difference(DateTime.now()),
        () => _handleDeadline(message.id),
      );
    }

    return true;
  }

  void _evictLowestPriority(QoSQueue queue, MessagePriority minPriority) {
    final messages = queue.toList();
    QoSMessage? lowest;
    int lowestIndex = -1;

    for (int i = 0; i < messages.length; i++) {
      if (messages[i].priority.index < minPriority.index) {
        if (lowest == null ||
            messages[i].priority.index < lowest.priority.index) {
          lowest = messages[i];
          lowestIndex = i;
        }
      }
    }

    if (lowest != null) {
      queue.remove(lowest.id);
      _droppedController.add(lowest);
      debugPrint('Evicted message ${lowest.id} for higher priority message');
    }
  }

  void _handleDeadline(String messageId) {
    _deadlineTimers.remove(messageId);
    for (final queue in _queues.values) {
      if (queue.contains(messageId)) {
        queue.remove(messageId);
        final message = _pending.remove(messageId);
        if (message != null) {
          _droppedController.add(message);
        }
        debugPrint('Message $messageId expired - deadline reached');
        break;
      }
    }
  }

  void acknowledge(String messageId) {
    final message = _pending.remove(messageId);
    if (message != null) {
      message.acknowledged = true;
      message.deliveredAt = DateTime.now();
      _deadlineTimers.remove(messageId);
      debugPrint('Message $messageId acknowledged');
    }
  }

  void retry(String messageId) {
    final message = _pending[messageId];
    if (message != null && message.retryCount < message.maxRetries) {
      message.retryCount++;
      _queues[message.trafficClass]!.add(message);
      debugPrint('Retrying message $messageId (attempt ${message.retryCount})');
    }
  }

  Future<void> _processQueues() async {
    if (!_isRunning) return;

    final sortedClasses = _getProcessingOrder();
    final bandwidthPerClass = _calculateBandwidthDistribution();

    for (final tc in sortedClasses) {
      final allocation = _allocations[tc]!;
      if (allocation.maxConcurrent <= 0) continue;

      final queue = _queues[tc]!;
      final bandwidth = bandwidthPerClass[tc]!;
      var messagesSent = 0;

      while (!queue.isEmpty && messagesSent < allocation.maxConcurrent) {
        final peeked = queue.peek();
        if (peeked == null) break;

        if (peeked.isExpired) {
          final removed = queue.removeFirst();
          if (removed != null) _droppedController.add(removed);
          continue;
        }

        final sentMessage = queue.removeFirst();
        if (sentMessage == null) break;
        sentMessage.sentAt = DateTime.now();
        _pending[sentMessage.id] = sentMessage;
        _messageController.add(sentMessage);
        messagesSent++;

        await Future.delayed(Duration(milliseconds: bandwidth));
      }
    }

    _emitMetrics();
  }

  List<TrafficClass> _getProcessingOrder() {
    return [
      TrafficClass.sos,
      TrafficClass.voiceCall,
      TrafficClass.videoCall,
      TrafficClass.textMessage,
      TrafficClass.fileTransfer,
      TrafficClass.sync,
      TrafficClass.bulk,
    ];
  }

  Map<TrafficClass, int> _calculateBandwidthDistribution() {
    final distribution = <TrafficClass, int>{};
    for (final entry in _allocations.entries) {
      distribution[entry.key] =
          (_totalBandwidthKBps * entry.value.percentage / 100).round();
    }
    return distribution;
  }

  void _emitMetrics() {
    final metrics = getMetrics();
    _metricsController.add(metrics);
  }

  void setBandwidth(int totalKBps) {
    _totalBandwidthKBps = totalKBps.clamp(100, 10000);
  }

  void setAllocation(TrafficClass trafficClass,
      {double? percentage, int? maxConcurrent}) {
    final allocation = _allocations[trafficClass];
    if (allocation != null) {
      if (percentage != null) {
        allocation.percentage = percentage.clamp(0, 100);
      }
      if (maxConcurrent != null) {
        allocation.maxConcurrent = maxConcurrent.clamp(0, 100);
      }
    }
  }

  QoSMessage? peekNext(TrafficClass trafficClass) {
    return _queues[trafficClass]?.peek();
  }

  QoSMessage? peekNextAny() {
    for (final tc in _getProcessingOrder()) {
      final msg = _queues[tc]?.peek();
      if (msg != null) return msg;
    }
    return null;
  }

  int getQueueSize(TrafficClass trafficClass) {
    return _queues[trafficClass]?.length ?? 0;
  }

  int getTotalQueueSize() {
    return _queues.values.fold(0, (sum, q) => sum + q.length);
  }

  int getPendingCount() => _pending.length;

  Map<String, dynamic> getMetrics() {
    return {
      'totalQueued': getTotalQueueSize(),
      'totalPending': _pending.length,
      'bandwidthKBps': _totalBandwidthKBps,
      'queues': {
        for (final tc in TrafficClass.values)
          tc.name: {
            'size': getQueueSize(tc),
            'allocation': _allocations[tc]!.percentage,
            'maxConcurrent': _allocations[tc]!.maxConcurrent,
          },
      },
      'pendingMessages': _pending.keys.toList(),
    };
  }

  void clearQueue(TrafficClass trafficClass) {
    _queues[trafficClass]?.toList().forEach((msg) {
      _droppedController.add(msg);
    });
    _queues[trafficClass] = QoSQueue(maxSize: _defaultMaxQueueSize);
  }

  void clearAllQueues() {
    for (final queue in _queues.values) {
      queue.toList().forEach((msg) => _droppedController.add(msg));
    }
    _initQueues();
    _pending.clear();
    for (final timer in _deadlineTimers.values) {
      timer.cancel();
    }
    _deadlineTimers.clear();
  }

  List<QoSMessage> getPendingMessages() => _pending.values.toList();

  QoSMessage? getPendingMessage(String id) => _pending[id];

  Map<String, dynamic> getQueueStatus() {
    return {
      for (final tc in TrafficClass.values)
        tc.name: {
          'size': getQueueSize(tc),
          'messages': _queues[tc]
              ?.toList()
              .map((m) => {
                    'id': m.id,
                    'priority': m.priority.name,
                    'age': DateTime.now().difference(m.createdAt).inSeconds,
                  })
              .toList(),
        },
    };
  }

  void dispose() {
    stop();
    _messageController.close();
    _droppedController.close();
    _metricsController.close();
    for (final timer in _deadlineTimers.values) {
      timer.cancel();
    }
    _deadlineTimers.clear();
  }
}
