import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'contact_service.dart';

class NfcService {
  static const MethodChannel _channel = MethodChannel('com.chaaya.meshlink/nfc');
  final ContactService _contactService;

  NfcService(this._contactService);

  void initialize() {
    _channel.setMethodCallHandler(_handleMethodCall);
    debugPrint('[NfcService] Listening for NDEF payloads...');
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onNdefDiscovered') {
      final String payload = call.arguments as String;
      debugPrint('[NfcService] Received NFC Payload: \$payload');
      try {
        await _contactService.processScannerUri(payload);
        debugPrint('[NfcService] Contact paired successfully via NFC.');
      } catch (e) {
        debugPrint('[NfcService] Error parsing NFC payload: \$e');
      }
    }
  }

  Future<bool> isNfcAvailable() async {
    try {
      final bool result = await _channel.invokeMethod('isNfcAvailable');
      return result;
    } on PlatformException {
      return false;
    }
  }
}
