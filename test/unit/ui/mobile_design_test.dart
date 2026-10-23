import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/models/message.dart';
import 'package:chaaya/core/models/user_profile.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/screens/chat_list/chat_list_screen.dart';
import 'package:chaaya/ui/screens/contacts/contacts_tab.dart';
import 'package:chaaya/ui/screens/calls/calls_tab.dart';
import 'package:chaaya/ui/screens/settings/settings_screen.dart';
import 'package:chaaya/ui/screens/onboarding/onboarding_screen.dart';
import 'package:chaaya/ui/screens/chat/chat_screen.dart';
import 'package:chaaya/ui/screens/profile/profile_screen.dart';
import 'package:chaaya/ui/screens/verification/verification_screen.dart';

final _identity=ChhayaId.fromPublicKey('05${List.filled(32,'11').join()}');
final _maya=Contact(id:'maya',chhayaId:_identity,displayName:'Maya Rao',isVerified:true,verificationLevel:3);
final _conversations=[
  Conversation(id:'design-chat',participants:[_maya],createdAt:DateTime(2026,10,23),isPinned:true,
    unreadCount:2,lastMessage:Message(id:'last',conversationId:'design-chat',senderId:'maya',
      content:'See you at the coffee shop tomorrow?',timestamp:DateTime(2026,10,23,9,41),isRead:true)),
  Conversation(id:'second',participants:[Contact(id:'arjun',chhayaId:_identity,displayName:'Arjun Mehta')],
    createdAt:DateTime(2026,10,22)),
];
class DesignDatabase extends LocalDatabase {
  @override
  Future<List<Message>> getMessages(String id) async => [
    Message(id:'hello',conversationId:id,senderId:'maya',content:'Hey! Are we still on for tomorrow?',
      timestamp:DateTime(2026,10,23,9,40),isRead:true),
    Message(id:'reply',conversationId:id,senderId:'me',content:'Absolutely. Same place, a little after ten.',
      timestamp:DateTime(2026,10,23,9,41),isRead:true,isDelivered:true),
  ];
  @override
  Future<Contact?> getContact(String id) async => _maya;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader=FontLoader('Inter')..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await loader.load();
  });
  final scenes=<String,Widget>{
    'chats':const ChatListScreen(),
    'contacts':const ContactsTab(),
    'calls':const CallsTab(),
    'settings':const SettingsScreen(),
    'onboarding':const OnboardingScreen(),
    'conversation':const ChatScreen(conversationId:'design-chat',contactName:'Maya Rao'),
    'profile':const ProfileScreen(contactId:'maya'),
    'verification':const VerificationScreen(),
  };
  for(final viewport in [(360.0,1.0),(320.0,2.0),(768.0,1.0)]) {
    for(final entry in scenes.entries) {
      testWidgets('${entry.key} fits ${viewport.$1}dp at ${viewport.$2}x text', (tester) async {
        tester.view.physicalSize=Size(viewport.$1,820);
        tester.view.devicePixelRatio=1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container=ProviderContainer(overrides:[localDatabaseProvider.overrideWithValue(DesignDatabase())]);
        addTearDown(container.dispose);
        container.read(conversationsProvider.notifier).setConversations(_conversations);
        container.read(contactsProvider.notifier).setContacts([_maya]);
        container.read(currentUserProvider.notifier).state=UserProfile(chhayaId:_identity,
          displayName:'Alex Morgan',recoveryPhrase:List.filled(12,'example'),createdAt:DateTime(2026,10,23));
        final capture=GlobalKey();
        await tester.pumpWidget(UncontrolledProviderScope(container:container,
          child:RepaintBoundary(key:capture,child:MaterialApp(theme:ChhayaTheme.materialLight,
            builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(
              disableAnimations:true,textScaler:TextScaler.linear(viewport.$2)),child:child!),
            home:entry.value)),
        ));
        await tester.pump();
        await tester.pump(const Duration(seconds:2));
        expect(tester.takeException(),isNull,reason:'No layout or runtime errors at large text');
        if(entry.key=='conversation') {
          expect(find.byTooltip('Send message'),findsOneWidget);
          expect(find.byIcon(Icons.mic_rounded),findsNothing);
        }
        await tester.runAsync(() async {
          final boundary=capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image=await boundary.toImage(pixelRatio:1);
          final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
          final out=File('build/design-review/${entry.key}-${viewport.$1.toInt()}-${viewport.$2}x.png');
          await out.parent.create(recursive:true);
          await out.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
}
