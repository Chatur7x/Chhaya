import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../sync/vector_clock.dart';

enum BundlePriority { critical, high, normal, low }

enum BundleStatus { pending, inTransit, delivered, expired, failed }

class DTNBundle {
  final String id;
  final String sourceEid;
  final String destinationEid;
  String? custodianEid;
  final DateTime creationTime;
  final Duration lifetime;
  final Uint8List payload;
  final BundlePriority priority;
  final VectorClock vectorClock;
  final Map<String, dynamic> metadata;
  final int custodyCount;

  BundleStatus _status = BundleStatus.pending;
  DateTime? _deliveredAt;
  final List<String> _custodyHistory = [];
  final List<String> _routeHistory = [];

  DTNBundle({
    required this.id,
    required this.sourceEid,
    required this.destinationEid,
    String? initialCustodian,
    required this.creationTime,
    required this.lifetime,
    required this.payload,
    required this.priority,
    required this.vectorClock,
    this.metadata = const {},
    this.custodyCount = 0,
  }) : custodianEid = initialCustodian {
    if (initialCustodian != null) {
      _custodyHistory.add(initialCustodian);
    }
  }

  BundleStatus get status => _status;
  DateTime? get deliveredAt => _deliveredAt;
  List<String> get custodyHistory => List.unmodifiable(_custodyHistory);
  List<String> get routeHistory => List.unmodifiable(_routeHistory);

  bool get isExpired => DateTime.now().isAfter(creationTime.add(lifetime));
  bool get isDelivered => _status == BundleStatus.delivered;

  Duration get remainingLifetime {
    final expiry = creationTime.add(lifetime);
    final remaining = expiry.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  DTNBundle copyWith({
    String? id,
    String? sourceEid,
    String? destinationEid,
    String? initialCustodian,
    DateTime? creationTime,
    Duration? lifetime,
    Uint8List? payload,
    BundlePriority? priority,
    VectorClock? vectorClock,
    Map<String, dynamic>? metadata,
    int? custodyCount,
  }) {
    return DTNBundle(
      id: id ?? this.id,
      sourceEid: sourceEid ?? this.sourceEid,
      destinationEid: destinationEid ?? this.destinationEid,
      initialCustodian: initialCustodian ?? this.custodianEid,
      creationTime: creationTime ?? this.creationTime,
      lifetime: lifetime ?? this.lifetime,
      payload: payload ?? this.payload,
      priority: priority ?? this.priority,
      vectorClock: vectorClock ?? this.vectorClock,
      metadata: metadata ?? this.metadata,
      custodyCount: custodyCount ?? this.custodyCount,
    );
  }

  void updateStatus(BundleStatus newStatus) {
    _status = newStatus;
    if (newStatus == BundleStatus.delivered) {
      _deliveredAt = DateTime.now();
    }
  }

  void transferCustody(String newCustodian) {
    _custodyHistory.add(newCustodian);
    custodianEid = newCustodian;
  }

  void addRouteHop(String nodeId) {
    _routeHistory.add(nodeId);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceEid': sourceEid,
        'destinationEid': destinationEid,
        'custodianEid': custodianEid,
        'creationTime': creationTime.toIso8601String(),
        'lifetimeMs': lifetime.inMilliseconds,
        'payloadSize': payload.length,
        'priority': priority.name,
        'status': _status.name,
        'custodyHistory': _custodyHistory,
        'routeHistory': _routeHistory,
        'custodyCount': custodyCount,
        'vectorClock': vectorClock.toJson(),
        'metadata': metadata,
      };

  factory DTNBundle.fromJson(Map<String, dynamic> json) {
    final bundle = DTNBundle(
      id: json['id'],
      sourceEid: json['sourceEid'],
      destinationEid: json['destinationEid'],
      initialCustodian: json['custodianEid'],
      creationTime: DateTime.parse(json['creationTime']),
      lifetime: Duration(milliseconds: json['lifetimeMs']),
      payload: Uint8List(json['payloadSize']),
      priority:
          BundlePriority.values.firstWhere((e) => e.name == json['priority']),
      vectorClock: VectorClock.fromJson(json['vectorClock']),
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
      custodyCount: json['custodyCount'] ?? 0,
    );
    bundle._status =
        BundleStatus.values.firstWhere((e) => e.name == json['status']);
    bundle._custodyHistory
        .addAll(List<String>.from(json['custodyHistory'] ?? []));
    bundle._routeHistory.addAll(List<String>.from(json['routeHistory'] ?? []));
    return bundle;
  }
}

class DTNBundleProtocol {
  final Map<String, DTNBundle> _bundles = {};
  final Map<String, Set<String>> _pendingDeliveries = {};
  final Set<String> _custodyNodes = {};

  static const Duration _defaultLifetime = Duration(days: 7);
  static const int _maxPayloadSize = 1024 * 1024;
  static const int _maxCustodyChain = 10;

  final _bundleController = StreamController<DTNBundle>.broadcast();
  Stream<DTNBundle> get bundleUpdates => _bundleController.stream;

  final _deliveryController = StreamController<DTNBundle>.broadcast();
  Stream<DTNBundle> get deliveryStream => _deliveryController.stream;

  final _expiryController = StreamController<DTNBundle>.broadcast();
  Stream<DTNBundle> get expiryStream => _expiryController.stream;

  String createBundle({
    required String sourceEid,
    required String destinationEid,
    required Uint8List payload,
    BundlePriority priority = BundlePriority.normal,
    Duration? lifetime,
    String? initialCustodian,
    Map<String, dynamic>? metadata,
  }) {
    if (payload.length > _maxPayloadSize) {
      throw Exception(
          'Payload too large: ${payload.length} > $_maxPayloadSize');
    }

    final id =
        'BUNDLE_${DateTime.now().millisecondsSinceEpoch}_${sourceEid.hashCode}';

    final bundle = DTNBundle(
      id: id,
      sourceEid: sourceEid,
      destinationEid: destinationEid,
      initialCustodian: initialCustodian,
      creationTime: DateTime.now(),
      lifetime: lifetime ?? _defaultLifetime,
      payload: payload,
      priority: priority,
      vectorClock: VectorClock(sourceEid),
      metadata: metadata ?? {},
    );

    _bundles[id] = bundle;
    _pendingDeliveries[destinationEid] ??= {};
    _pendingDeliveries[destinationEid]!.add(id);

    if (initialCustodian != null) {
      _custodyNodes.add(initialCustodian);
    }

    _bundleController.add(bundle);
    debugPrint('DTN Bundle created: $id');
    return id;
  }

  void acceptCustody(String bundleId, String nodeEid) {
    final bundle = _bundles[bundleId];
    if (bundle == null) return;

    if (bundle.custodyCount >= _maxCustodyChain) {
      bundle.updateStatus(BundleStatus.failed);
      return;
    }

    bundle.transferCustody(nodeEid);
    _custodyNodes.add(nodeEid);
    _bundleController.add(bundle);
    debugPrint('Custody transferred to: $nodeEid');
  }

  void relayBundle(String bundleId, String relayNodeEid) {
    final bundle = _bundles[bundleId];
    if (bundle == null) return;

    if (bundle.isExpired) {
      bundle.updateStatus(BundleStatus.expired);
      _expiryController.add(bundle);
      return;
    }

    bundle.addRouteHop(relayNodeEid);
    bundle.updateStatus(BundleStatus.inTransit);
    _bundleController.add(bundle);
    debugPrint('Bundle $bundleId relayed via: $relayNodeEid');
  }

  void deliverBundle(String bundleId) {
    final bundle = _bundles[bundleId];
    if (bundle == null) return;

    if (bundle.isExpired) {
      bundle.updateStatus(BundleStatus.expired);
      _expiryController.add(bundle);
      return;
    }

    bundle.updateStatus(BundleStatus.delivered);
    _pendingDeliveries[bundle.destinationEid]?.remove(bundleId);
    _deliveryController.add(bundle);
    debugPrint('Bundle $bundleId delivered');
  }

  void processExpiredBundles() {
    final expired = _bundles.values
        .where((b) => b.isExpired && b.status != BundleStatus.delivered)
        .toList();

    for (final bundle in expired) {
      bundle.updateStatus(BundleStatus.expired);
      _pendingDeliveries[bundle.destinationEid]?.remove(bundle.id);
      _expiryController.add(bundle);
    }
  }

  DTNBundle? getBundle(String bundleId) => _bundles[bundleId];

  List<DTNBundle> getPendingBundles(String nodeEid) {
    return _bundles.values
        .where((b) =>
            b.status == BundleStatus.pending ||
            b.status == BundleStatus.inTransit)
        .where((b) => b.isExpired == false)
        .toList()
      ..sort((a, b) => b.priority.index.compareTo(a.priority.index));
  }

  List<DTNBundle> getBundlesForDestination(String destinationEid) {
    return _bundles.values
        .where((b) => b.destinationEid == destinationEid)
        .where((b) =>
            b.status != BundleStatus.delivered &&
            b.status != BundleStatus.expired)
        .toList();
  }

  List<DTNBundle> getCustodyBundles(String nodeEid) {
    return _bundles.values
        .where((b) => b.custodianEid == nodeEid)
        .where((b) =>
            b.status == BundleStatus.pending ||
            b.status == BundleStatus.inTransit)
        .toList();
  }

  Set<String> getCustodyNodes() => Set.unmodifiable(_custodyNodes);

  void mergeBundle(DTNBundle remoteBundle) {
    final local = _bundles[remoteBundle.id];

    if (local == null) {
      _bundles[remoteBundle.id] = remoteBundle;
      _bundleController.add(remoteBundle);
      return;
    }

    if (remoteBundle.vectorClock.happensBefore(local.vectorClock) == false &&
        remoteBundle.creationTime.isAfter(local.creationTime)) {
      _bundles[remoteBundle.id] = remoteBundle;
      _bundleController.add(remoteBundle);
    }
  }

  Map<String, dynamic> getStatistics() {
    int pending = 0, inTransit = 0, delivered = 0, expired = 0;

    for (final bundle in _bundles.values) {
      switch (bundle.status) {
        case BundleStatus.pending:
          pending++;
          break;
        case BundleStatus.inTransit:
          inTransit++;
          break;
        case BundleStatus.delivered:
          delivered++;
          break;
        case BundleStatus.expired:
          expired++;
          break;
        default:
          break;
      }
    }

    return {
      'totalBundles': _bundles.length,
      'pending': pending,
      'inTransit': inTransit,
      'delivered': delivered,
      'expired': expired,
      'custodyNodes': _custodyNodes.length,
    };
  }

  void dispose() {
    _bundleController.close();
    _deliveryController.close();
    _expiryController.close();
  }
}
