import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../crypto/chhaya_crypto_engine.dart';
import '../crypto/key_manager.dart';
import '../database/local_database.dart';
import '../models/contact.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user_profile.dart';
import '../../services/auth/auth_service.dart';
import '../../services/network/onion_router_service.dart';
import '../../services/network/p2p_tunnel_service.dart';
import '../../services/network/decentralized_file_client.dart';
import '../../services/notification/notification_service.dart';
import '../../services/api/api_service.dart';
import '../../services/messaging/messaging_service.dart';
import '../../services/call/call_service.dart';




final LocalDatabase _dbSingleton = LocalDatabase();
final KeyManager _keyManagerSingleton = KeyManager();
final ChhayaCryptoEngine _cryptoSingleton = ChhayaCryptoEngine();
final OnionRouterService _onionSingleton = OnionRouterService();
final P2PTunnelService _p2pSingleton = P2PTunnelService();
final DecentralizedFileClient _fileSingleton = DecentralizedFileClient();
final NotificationService _notifSingleton = NotificationService();
final ApiService _apiSingleton = ApiService();



final notificationServiceProvider = Provider<NotificationService>((ref) {
  return _notifSingleton;
});

final cryptoEngineProvider = Provider<ChhayaCryptoEngine>((ref) {
  return _cryptoSingleton;
});

final keyManagerProvider = Provider<KeyManager>((ref) {
  return _keyManagerSingleton;
});

final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  return _dbSingleton;
});



final onionRouterProvider = Provider<OnionRouterService>((ref) {
  return _onionSingleton;
});

final p2pTunnelProvider = Provider<P2PTunnelService>((ref) {
  return _p2pSingleton;
});

final fileClientProvider = Provider<DecentralizedFileClient>((ref) {
  return _fileSingleton;
});

final apiServiceProvider = Provider<ApiService>((ref) {
  return _apiSingleton;
});



final authServiceProvider = Provider<AuthService>((ref) {

  return AuthService(
    crypto: _cryptoSingleton,
    keyManager: _keyManagerSingleton,
    database: _dbSingleton,
  );
});



final currentUserProvider = StateProvider<UserProfile?>((ref) => null);

final conversationsProvider =
    StateNotifierProvider<ConversationsNotifier, List<Conversation>>((ref) {
  return ConversationsNotifier();
});

final contactsProvider =
    StateNotifierProvider<ContactsNotifier, List<Contact>>((ref) {
  return ContactsNotifier();
});



class ConversationsNotifier extends StateNotifier<List<Conversation>> {
  ConversationsNotifier() : super([]);

  void setConversations(List<Conversation> conversations) {
    if (_sameConversationSnapshot(state, conversations)) { return; }
    state = conversations;
  }

  void addConversation(Conversation conversation) {
    state = [conversation, ...state];
  }

  void updateConversation(Conversation conversation) {
    state = state.map((c) => c.id == conversation.id ? conversation : c).toList();
  }

  void removeConversation(String id) {
    state = state.where((c) => c.id != id).toList();
  }

  void pinConversation(String id) {
    state = state.map((c) {
      if (c.id == id) return c.copyWith(isPinned: !c.isPinned);
      return c;
    }).toList();
  }
}

class ContactsNotifier extends StateNotifier<List<Contact>> {
  ContactsNotifier() : super([]);

  void setContacts(List<Contact> contacts) {
    if (_sameContactSnapshot(state, contacts)) { return; }
    state = contacts;
  }

  void addContact(Contact contact) {
    state = [...state, contact];
  }

  void updateContact(Contact contact) {
    state = state.map((c) => c.id == contact.id ? contact : c).toList();
  }

  void removeContact(String id) {
    state = state.where((c) => c.id != id).toList();
  }
}

// Keep the previous list when a poll returns the same visible data. This
// prevents Riverpod from redrawing chat and contact screens every refresh.
bool _sameContactSnapshot(List<Contact> a, List<Contact> b) {
  if (identical(a, b)) { return true; }
  if (a.length != b.length) { return false; }
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (x.id != y.id || x.chhayaId.publicKey != y.chhayaId.publicKey ||
        x.displayName != y.displayName || x.avatarUrl != y.avatarUrl ||
        x.verificationLevel != y.verificationLevel || x.isBlocked != y.isBlocked ||
        x.isPinned != y.isPinned || x.lastSeen != y.lastSeen ||
        x.isOnline != y.isOnline || x.isVerified != y.isVerified) {
      return false;
    }
  }
  return true;
}

bool _sameConversationSnapshot(List<Conversation> a, List<Conversation> b) {
  if (identical(a, b)) { return true; }
  if (a.length != b.length) { return false; }
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (x.id != y.id || x.unreadCount != y.unreadCount ||
        x.isPinned != y.isPinned || x.isMuted != y.isMuted ||
        x.isGroup != y.isGroup || x.groupName != y.groupName ||
        x.groupAvatarUrl != y.groupAvatarUrl || x.createdAt != y.createdAt ||
        !_sameContactSnapshot(x.participants, y.participants) ||
        !_sameMessagePreview(x.lastMessage, y.lastMessage)) {
      return false;
    }
  }
  return true;
}

bool _sameMessagePreview(Message? a, Message? b) {
  if (identical(a, b)) { return true; }
  if (a == null || b == null) { return false; }
  return a.id == b.id && a.senderId == b.senderId && a.content == b.content &&
      a.type == b.type && a.timestamp == b.timestamp && a.isExpired == b.isExpired &&
      a.replyToId == b.replyToId && a.attachment?.name == b.attachment?.name &&
      a.attachment?.mimeType == b.attachment?.mimeType;
}

final messagingServiceProvider = Provider<MessagingService>((ref) => MessagingService(
  api:ref.read(apiServiceProvider),database:ref.read(localDatabaseProvider),keys:ref.read(keyManagerProvider)));

final callServiceProvider=ChangeNotifierProvider<CallService>((ref)=>CallService(
  api:ref.read(apiServiceProvider),database:ref.read(localDatabaseProvider),keys:ref.read(keyManagerProvider)));
