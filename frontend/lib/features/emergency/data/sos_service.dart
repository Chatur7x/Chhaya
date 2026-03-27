import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../../../core/mesh/ble_mesh_service.dart';
import '../../../core/mesh/mesh_message.dart';
import '../../../core/mesh/wifi_direct_service.dart';
import '../../contacts/data/contact_service.dart';

class SosService {
  static const MethodChannel _channel = MethodChannel('com.chaaya.meshlink/panic'); // reuse panic channel for SOS triggers
  
  final BleMeshService _bleMesh;
  final WifiDirectService _wifiDirect;
  final ContactService _contactService;
  final String _myDeviceId;

  SosService({
    required BleMeshService bleMesh,
    required WifiDirectService wifiDirect,
    required ContactService contactService,
    required String myDeviceId,
  }) : _bleMesh = bleMesh,
       _wifiDirect = wifiDirect,
       _contactService = contactService,
       _myDeviceId = myDeviceId {
         
    _bleMesh.incomingMessages.listen((msg) {
      if (msg.isSOS) {
        _handleIncomingSos(msg);
      }
    });
  }

  Future<void> triggerSos() async {
    final trusted = _contactService.getAll().where((c) => c.isTrusted).toList();
    if (trusted.isEmpty) {
      debugPrint('[SOS] No trusted contacts available to send SOS.');
    }

    // 10 second audio recording and location would be grabbed here before sending
    final payload = "SOS EMERGENCY! Require immediate assistance.";
    
    // Broadcast multi-channel (skip queue logic by directly sending)
    for (final contact in trusted) {
      final msg = MeshMessage(
        senderId: _myDeviceId,
        senderName: "Me", // Would be actual name
        recipientId: contact.deviceId,
        content: payload,
        isSOS: true,
      );

      // Bypass MessageQueue, force direct transport
      _bleMesh.sendMessage(msg);
      _wifiDirect.sendMessage(msg.toJson());
      
      debugPrint('[SOS] Alert cast via BLE and WiFi to \${contact.name}');
    }
  }

  Future<void> _handleIncomingSos(MeshMessage msg) async {
    debugPrint('[SOS] Incoming EMERGENCY packet from \${msg.senderId}');
    try {
      // Trigger native Android TelecomManager auto-answer / siren
      await _channel.invokeMethod('triggerSosAlarm', {
        'sender': msg.senderName, 
        'id': msg.senderId
      });
    } on PlatformException catch (_) {
      debugPrint('[SOS] Native trigger failed');
    }
  }
}
