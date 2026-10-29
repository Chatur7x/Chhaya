import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/core/models/user_profile.dart';
import 'package:chaaya/services/api/api_service.dart';
import 'package:chaaya/services/auth/auth_service.dart';
import 'package:chaaya/ui/screens/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

class ContactDatabase extends LocalDatabase {
  ContactDatabase(this.contact);
  final Contact? contact;
  @override
  Future<Contact?> getContact(String contactId) async => contact;
  @override
  List<String> getBlockedContacts() => [];
}

class ProfileApi extends ApiService {
  ProfileApi({this.fail = false})
    : super.forTesting(
        storage: SecureStorageMock(),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
  final bool fail;
  String? name;
  @override
  bool get isAuthenticated => true;
  @override
  Future<void> updateDisplayName(String value) async {
    if (fail) throw StateError('offline');
    name = value;
  }
}

class ProfileAuth extends AuthService {
  ProfileAuth(this.profile);
  UserProfile profile;
  @override
  UserProfile get currentUser => profile;
  @override
  Future<void> updateDisplayName(String name) async {
    profile = profile.copyWith(displayName: name);
  }
}

void main() {
  for (final fail in [false, true]) {
    testWidgets('profile save handles server result: $fail', (tester) async {
      final api = ProfileApi(fail: fail);
      final auth = ProfileAuth(
        UserProfile(
          chhayaId: ChhayaId.fromPublicKey('05${'11' * 32}'),
          displayName: 'Before',
          recoveryPhrase: const [],
          createdAt: DateTime(2026),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiServiceProvider.overrideWithValue(api),
            authServiceProvider.overrideWithValue(auth),
            currentUserProvider.overrideWith((ref) => auth.currentUser),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.tap(find.text('Edit profile'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  After  ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(auth.currentUser.displayName, fail ? 'Before' : 'After');
      expect(api.name, fail ? null : 'After');
      if (fail) {
        expect(find.textContaining('Could not save profile'), findsOneWidget);
      }
    });
  }
  for (final verified in [false, true]) {
    testWidgets('profile uses local verified flag: $verified', (tester) async {
      final contact = Contact(
        id: 'peer',
        chhayaId: ChhayaId.fromPublicKey('05${'11' * 32}'),
        displayName: 'Peer',
        verificationLevel: 3,
        isVerified: verified,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localDatabaseProvider.overrideWithValue(ContactDatabase(contact)),
          ],
          child: const MaterialApp(home: ProfileScreen(contactId: 'peer')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(verified ? 'Verified' : 'Unverified'),
        verified ? findsNWidgets(2) : findsOneWidget,
      );
      expect(find.text(verified ? 'Unverified' : 'Verified'), findsNothing);
    });
  }
}
