import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/identity/identity_service.dart';
import '../../core/mesh/ble_mesh_service.dart';
import '../../core/mesh/mesh_router.dart';
import '../../core/mesh/message_queue.dart';
import '../../core/mesh/wifi_direct_service.dart';
import '../../core/crypto/signal_protocol_service.dart';
import '../../features/contacts/data/contact_service.dart';
import '../../features/contacts/data/call_service.dart';
import '../../features/messenger/data/mesh_chat_service.dart';
import '../../features/messenger/data/group_channel_service.dart';
import '../../features/radio/data/walkie_talkie_service.dart';
import '../../features/safety/data/location_safety_service.dart';
import '../../features/storage/data/secure_storage_manager.dart';

/// ─── Core Service Providers ───

final identityServiceProvider = Provider<IdentityService>((ref) {
  return IdentityService();
});

final messageQueueProvider = Provider<MessageQueue>((ref) {
  return MessageQueue();
});

final bleMeshServiceProvider = Provider<BleMeshService>((ref) {
  final queue = ref.read(messageQueueProvider);
  final identity = ref.read(identityServiceProvider);
  return BleMeshService(
    messageQueue: queue,
    myDeviceId: identity.currentIdentity?.deviceId ?? '',
  );
});

final wifiDirectServiceProvider = Provider<WifiDirectService>((ref) {
  final queue = ref.read(messageQueueProvider);
  final identity = ref.read(identityServiceProvider);
  return WifiDirectService(
    messageQueue: queue,
    myDeviceId: identity.currentIdentity?.deviceId ?? '',
  );
});

final meshRouterProvider = Provider<MeshRouter>((ref) {
  final ble = ref.read(bleMeshServiceProvider);
  final identity = ref.read(identityServiceProvider);
  return MeshRouter(
    bleService: ble,
    myDeviceId: identity.currentIdentity?.deviceId ?? '',
  );
});

final signalProtocolProvider = Provider<SignalProtocolService>((ref) {
  return SignalProtocolService();
});

/// ─── Feature Service Providers ───

final contactServiceProvider = Provider<ContactService>((ref) {
  return ContactService();
});

final meshChatServiceProvider = Provider<MeshChatService>((ref) {
  return MeshChatService();
});

final groupChannelServiceProvider = Provider<GroupChannelService>((ref) {
  return GroupChannelService();
});

final callServiceProvider = Provider<CallService>((ref) {
  final wifi = ref.read(wifiDirectServiceProvider);
  final identity = ref.read(identityServiceProvider);
  return CallService(
    wifiService: wifi,
    myDeviceId: identity.currentIdentity?.deviceId ?? '',
  );
});

final walkieTalkieServiceProvider = Provider<WalkieTalkieService>((ref) {
  final wifi = ref.read(wifiDirectServiceProvider);
  final identity = ref.read(identityServiceProvider);
  return WalkieTalkieService(
    wifiService: wifi,
    myDeviceId: identity.currentIdentity?.deviceId ?? '',
    myCallsign: identity.currentIdentity?.username.toUpperCase() ?? 'ALPHA-1',
  );
});

final locationSafetyServiceProvider = Provider<LocationSafetyService>((ref) {
  return LocationSafetyService();
});

final secureStorageProvider = Provider<SecureStorageManager>((ref) {
  return SecureStorageManager();
});

/// ─── State Providers ───

final identityReadyProvider = StateProvider<bool>((ref) => false);
final currentIdentityProvider = StateProvider<MeshIdentity?>((ref) => null);
final contactListProvider = StateProvider<List<MeshContact>>((ref) => []);
final conversationListProvider = StateProvider<List<ConversationPreview>>((ref) => []);
final locationStreamProvider = StreamProvider<Map<String, UserLocation>>((ref) {
  return ref.watch(locationSafetyServiceProvider).locationUpdates;
});
