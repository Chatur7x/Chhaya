import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/services/api/api_service.dart';
import 'package:chaaya/services/call/call_service.dart';

class BlockedCallDatabase extends LocalDatabase {
  final bool contactFlag;
  BlockedCallDatabase(this.contactFlag);
  Contact get peer => Contact(id: 'peer', displayName: 'Peer',
    chhayaId: ChhayaId.fromPublicKey('05${List.filled(64, 'a').join()}'),
    isVerified: true, isBlocked: contactFlag);
  @override
  Future<List<Conversation>> getAllConversations() async => [
    Conversation(id: 'chat', participants: [peer], createdAt: DateTime(2026))];
  @override
  Future<Contact?> getContact(String id) async => peer;
  @override
  List<String> getBlockedContacts() => contactFlag ? [] : ['peer'];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final contactFlag in [true, false]) {
    test('blocked calls fail before signaling or media (contact flag: $contactFlag)', () async {
      final service = CallService(api: ApiService(),
        database: BlockedCallDatabase(contactFlag),
        keys: KeyManager(secureBackend: SecureStorageMock()));
      addTearDown(service.dispose);
      await expectLater(service.call('chat', false),
        throwsA(isA<StateError>().having((e) => e.message, 'reason', contains('Unblock'))));
    });
  }
}
