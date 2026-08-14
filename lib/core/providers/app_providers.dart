import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../crypto/chhaya_crypto_engine.dart';
import '../crypto/key_manager.dart';
import '../database/local_database.dart';
import '../models/contact.dart';
import '../models/conversation.dart';
import '../models/user_profile.dart';
import '../../services/auth/auth_service.dart';
import '../../services/network/onion_router_service.dart';
import '../../services/network/p2p_tunnel_service.dart';
import '../../services/network/decentralized_file_client.dart';
import '../../services/notification/notification_service.dart';




final LocalDatabase _dbSingleton = LocalDatabase();
final KeyManager _keyManagerSingleton = KeyManager();
final ChhayaCryptoEngine _cryptoSingleton = ChhayaCryptoEngine();
final OnionRouterService _onionSingleton = OnionRouterService();
final P2PTunnelService _p2pSingleton = P2PTunnelService();
final DecentralizedFileClient _fileSingleton = DecentralizedFileClient();
final NotificationService _notifSingleton = NotificationService();



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
