import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/ui/screens/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class ContactDatabase extends LocalDatabase {
  ContactDatabase(this.contact);
  final Contact? contact;
  @override
  Future<Contact?> getContact(String contactId) async => contact;
  @override
  List<String> getBlockedContacts() => [];
}

void main() {
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
