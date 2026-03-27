import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/models/contact.dart';
import '../../../core/identity/identity_service.dart';

class ContactService {
  static const String boxName = 'chaaya_contacts';
  late Box<Contact> _box;

  final IdentityService _identityService;

  ContactService(this._identityService);

  Future<void> initialize() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ContactAdapter());
    }
    _box = await Hive.openBox<Contact>(boxName);
  }

  List<Contact> getAll() {
    return _box.values.toList();
  }

  Contact? getContact(String deviceId) {
    return _box.get(deviceId);
  }

  Future<void> saveContact(Contact contact) async {
    await _box.put(contact.deviceId, contact);
  }

  Future<void> deleteContact(String deviceId) async {
    await _box.delete(deviceId);
  }
  
  Future<void> setTrusted(String deviceId, bool trusted) async {
    final c = getContact(deviceId);
    if (c != null) {
      // Check ring size limit
      if (trusted) {
        final trustedCount = _box.values.where((test) => test.isTrusted).length;
        if (trustedCount >= 5) {
          throw Exception("Trusted Contact Ring is full (Max 5).");
        }
      }
      c.isTrusted = trusted;
      await c.save();
    }
  }

  String getMyPairingUri() {
    final pkHex = _identityService.currentIdentity!.publicKey; 
    final id = _identityService.currentIdentity!.deviceId;
    return 'chaaya://pair?v=1&pk=$pkHex&id=$id';
  }

  Future<Contact> processScannerUri(String uriString) async {
    try {
      final uri = Uri.parse(uriString);
      if (uri.scheme != 'chaaya' || uri.host != 'pair') {
        throw Exception("Invalid Chaaya pairing QR code.");
      }
      
      final pk = uri.queryParameters['pk'];
      final id = uri.queryParameters['id'];
      final name = uri.queryParameters['name'] ?? 'Anonymous';

      if (pk == null || id == null) {
        throw Exception("Missing cryptographic identifiers in QR.");
      }

      final contact = Contact(
        deviceId: id,
        publicKey: pk,
        name: name,
      );

      await saveContact(contact);
      return contact;
    } catch (e) {
      debugPrint("QR Parse Error: \$e");
      rethrow;
    }
  }
}
