import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto_lib;
import '../../core/models/message.dart';


class OnionNode {
  final String id;
  final String address;
  final Uint8List publicKey;
  final int latencyMs;
  final bool isActive;

  OnionNode({
    required this.id,
    required this.address,
    required this.publicKey,
    required this.latencyMs,
    this.isActive = true,
  });
}


class OnionPacket {
  final String packetId;
  final Uint8List payload;
  final int layersRemaining;
  final List<String> routePath;
  final DateTime createdAt;
  final int ttlSeconds;

  OnionPacket({
    required this.packetId,
    required this.payload,
    required this.layersRemaining,
    required this.routePath,
    required this.createdAt,
    this.ttlSeconds = 30,
  });

  bool get isExpired =>
      DateTime.now().difference(createdAt).inSeconds > ttlSeconds;
}


class RoutingStats {
  int totalSent = 0;
  int totalReceived = 0;
  int totalFailed = 0;
  double averageLatencyMs = 0;

  void recordSent(double latency) {
    totalSent++;
    averageLatencyMs =
        ((averageLatencyMs * (totalSent - 1)) + latency) / totalSent;
  }
}


class OnionRouterService {
  bool isEnabled;
  final int hopCount;
  final List<OnionNode> _availableNodes = [];
  final RoutingStats stats = RoutingStats();
  final Random _random = Random.secure();

  OnionRouterService({
    this.isEnabled = true,
    this.hopCount = 3,
  }) {
    _initializeSimulatedNodes();
  }

  List<OnionNode> get activeNodes =>
      _availableNodes.where((n) => n.isActive).toList();

  void _initializeSimulatedNodes() {
    final regions = ['us-east', 'eu-west', 'ap-south', 'us-west', 'eu-north',
                     'ap-east', 'sa-east', 'af-south'];
    for (int i = 0; i < 8; i++) {
      final keyBytes = List<int>.generate(32, (_) => _random.nextInt(256));
      _availableNodes.add(OnionNode(
        id: 'node_${regions[i]}_${i.toString().padLeft(3, '0')}',
        address: '${regions[i]}.Chhaya.network:${8443 + i}',
        publicKey: Uint8List.fromList(keyBytes),
        latencyMs: 50 + _random.nextInt(200),
      ));
    }
  }


  List<OnionNode> getOptimalPath() {
    final available = List<OnionNode>.from(activeNodes);
    available.sort((a, b) => a.latencyMs.compareTo(b.latencyMs));

    final candidates = available.take(hopCount + 2).toList();
    candidates.shuffle(_random);
    return candidates.take(hopCount).toList();
  }




  OnionPacket wrapMessage(Message message, List<OnionNode> path) {
    final originalBytes = Uint8List.fromList(message.content.codeUnits);
    const paddedSize = 512;

    if (originalBytes.length > paddedSize - 4) {
      throw ArgumentError('Message content too large for fixed-size onion padding');
    }


    final paddedPayload = Uint8List(paddedSize);


    final length = originalBytes.length;
    paddedPayload[0] = (length >> 24) & 0xFF;
    paddedPayload[1] = (length >> 16) & 0xFF;
    paddedPayload[2] = (length >> 8) & 0xFF;
    paddedPayload[3] = length & 0xFF;


    paddedPayload.setRange(4, 4 + length, originalBytes);


    for (int i = 4 + length; i < paddedSize; i++) {
      paddedPayload[i] = _random.nextInt(256);
    }

    Uint8List payload = paddedPayload;


    for (int i = path.length - 1; i >= 0; i--) {
      final node = path[i];

      final keyHash = crypto_lib.sha256.convert(node.publicKey);
      final keyBytes = Uint8List.fromList(keyHash.bytes);
      final wrappedPayload = Uint8List(payload.length);
      for (int j = 0; j < payload.length; j++) {
        wrappedPayload[j] = payload[j] ^ keyBytes[j % keyBytes.length];
      }
      payload = wrappedPayload;
    }

    final packetIdBytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final packetId = packetIdBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    return OnionPacket(
      packetId: packetId,
      payload: payload,
      layersRemaining: path.length,
      routePath: path.map((n) => n.id).toList(),
      createdAt: DateTime.now(),
    );
  }


  OnionPacket unwrapLayer(OnionPacket packet, Uint8List nodePrivateKey) {
    final keyHash = crypto_lib.sha256.convert(nodePrivateKey);
    final keyBytes = Uint8List.fromList(keyHash.bytes);
    final unwrapped = Uint8List(packet.payload.length);

    for (int j = 0; j < packet.payload.length; j++) {
      unwrapped[j] = packet.payload[j] ^ keyBytes[j % keyBytes.length];
    }

    return OnionPacket(
      packetId: packet.packetId,
      payload: unwrapped,
      layersRemaining: packet.layersRemaining - 1,
      routePath: packet.routePath.sublist(1),
      createdAt: packet.createdAt,
      ttlSeconds: packet.ttlSeconds,
    );
  }


  static String extractContent(Uint8List decryptedPayload) {

    final length = (decryptedPayload[0] << 24) |
                   (decryptedPayload[1] << 16) |
                   (decryptedPayload[2] << 8) |
                   decryptedPayload[3];

    if (length < 0 || length > decryptedPayload.length - 4) {
      throw FormatException('Malformed payload size header: $length');
    }

    final contentBytes = decryptedPayload.sublist(4, 4 + length);
    return String.fromCharCodes(contentBytes);
  }



  Future<bool> routeMessage(Message message, Uint8List recipientPublicKey) async {
    if (!isEnabled) {
      stats.recordSent(10);
      return true;
    }

    final path = getOptimalPath();
    if (path.length < hopCount) {
      stats.totalFailed++;
      return false;
    }

    final packet = wrapMessage(message, path);


    final entryNode = path.first;
    final delivered = await WebSocketTransport.sendPacket(
      entryNode.address,
      packet.payload,
    );

    if (delivered) {

      double totalLatency = 0;
      for (final node in path) {
        totalLatency += node.latencyMs + 20 + _random.nextInt(130);
      }
      stats.recordSent(totalLatency);
      return true;
    }


    double totalLatency = 0;
    OnionPacket currentPacket = packet;

    for (int i = 0; i < path.length; i++) {
      final node = path[i];
      final jitter = 20 + _random.nextInt(130);
      final hopDelay = node.latencyMs + jitter;
      totalLatency += hopDelay;

      await Future.delayed(Duration(milliseconds: hopDelay));
      currentPacket = unwrapLayer(currentPacket, node.publicKey);
    }

    stats.recordSent(totalLatency);
    return true;
  }
}



class WebSocketTransport {


  static Future<bool> sendPacket(String nodeAddress, Uint8List payload) async {
    try {

      final uri = Uri.parse('wss://$nodeAddress/relay');
      final socket = await WebSocket.connect(uri.toString())
          .timeout(const Duration(seconds: 5));

      socket.add(payload);


      await socket.first.timeout(const Duration(seconds: 3));

      await socket.close();
      return true;
    } on SocketException {

      return false;
    } on TimeoutException {

      return false;
    } catch (_) {

      return false;
    }
  }


  static Future<Stream<Uint8List>?> openReceiveStream(String nodeAddress) async {
    try {
      final uri = Uri.parse('wss://$nodeAddress/relay');
      final socket = await WebSocket.connect(uri.toString())
          .timeout(const Duration(seconds: 5));

      return socket.where((data) => data is List<int>).map((data) => Uint8List.fromList(data as List<int>));
    } catch (_) {
      return null;
    }
  }
}

