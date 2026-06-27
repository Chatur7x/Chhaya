import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/identity/identity_service.dart';
import '../../core/mesh/ble_mesh_service.dart';
import '../../core/mesh/mesh_router.dart';
import '../../core/mesh/message_queue.dart';
import '../../core/mesh/wifi_direct_service.dart';
import '../../core/mesh/store_forward_service.dart';
import '../../core/mesh/channel_hopper.dart';
import '../../core/crypto/signal_protocol_service.dart';
import '../../core/network/onion_router.dart';
import '../../core/network/privacy_layer.dart';
import '../../core/network/dead_drop_service.dart';
import '../../core/network/platform_channel_bridge.dart';
import '../../core/network/path_discovery.dart';
import '../../features/contacts/data/contact_service.dart';
import '../../features/contacts/domain/models/contact.dart';
import '../../features/contacts/data/contact_group_service.dart';
import '../../features/contacts/data/nfc_service.dart';
import '../../features/contacts/data/call_service.dart';
import '../../features/emergency/data/sos_service.dart';
import '../../features/stealth/data/stealth_service.dart';
import '../../features/messenger/data/mesh_chat_service.dart';
import '../../features/messenger/data/group_channel_service.dart';
import '../../features/radio/data/walkie_talkie_service.dart';
import '../../features/safety/data/location_safety_service.dart';

import '../../features/chat/data/voice_message_service.dart';
import '../../features/chat/data/disappearing_message_service.dart';
import '../../features/chat/data/search_service.dart';
import '../../features/chat/data/reaction_service.dart';
import '../../features/chat/data/reply_service.dart';
import '../../features/chat/data/presence_service.dart';
import '../../features/chat/data/pin_service.dart';
import '../../features/chat/data/wallpaper_service.dart';
import '../../features/chat/data/schedule_service.dart';
import '../../features/chat/data/chat_folder_service.dart';
import '../../features/identity/data/key_verification_service.dart';
import '../../features/auth/data/biometric_service.dart';
import '../../features/auth/data/decoy_service.dart';
import '../../features/messenger/data/poll_service.dart';
import '../../features/safety/data/location_share_service.dart';
import '../../features/safety/data/panic_button_service.dart';
import '../../features/ai/data/offline_ai_service.dart';
import '../../features/gamification/gamification_engine.dart';
import '../../features/mission/mission_planner.dart';
import '../../features/intelligence/crowd_intelligence.dart';
import '../../core/theme/theme_service.dart';
import '../../core/network/dtn_bundle_protocol.dart';
import '../../core/network/epidemic_spread.dart';
import '../../core/network/mixnet_router.dart';
import '../../core/network/predictive_failure_detector.dart';
import '../../core/network/adaptive_routing_engine.dart';
import '../../core/network/route_optimizer.dart';
import '../../core/network/qos_scheduler.dart';
import '../../core/intelligence/context_aware_ui_engine.dart';
import '../../core/power/survival_mode.dart';
import '../../core/storage/distributed_storage.dart';
import '../../core/sync/dedup_cache.dart';
import '../../core/sync/crdt_message_store.dart';
import '../../core/sync/vector_clock.dart';
import '../../core/crypto/key_rotation_manager.dart';
import '../../core/crypto/anti_replay_cache.dart';
import '../../core/mesh/node_reputation.dart';
import '../../core/mesh/adaptive_bluetooth_scanner.dart';

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
  final sf = ref.read(storeForwardServiceProvider);
  return MeshRouter(
    bleService: ble,
    sfService: sf,
    myDeviceId: identity.currentIdentity?.deviceId ?? '',
  );
});

final pathDiscoveryServiceProvider = Provider<PathDiscoveryService>((ref) {
  final myDeviceId =
      ref.read(identityServiceProvider).currentIdentity?.deviceId ?? '';
  final contactSvc = ref.read(contactServiceProvider);
  final service =
      PathDiscoveryService(contactService: contactSvc, myDeviceId: myDeviceId);

  // Wire up BLE to PathDiscovery
  ref.read(bleMeshServiceProvider).connectionStatus.listen((statusMap) {
    service.updateDirectNeighbors(statusMap.keys.toList());
  });

  return service;
});

final signalProtocolProvider = Provider<SignalProtocolService>((ref) {
  return SignalProtocolService();
});

/// ─── Feature Service Providers ───

final contactServiceProvider = Provider<ContactService>((ref) {
  final identity = ref.read(identityServiceProvider);
  return ContactService(identity);
});

final contactGroupServiceProvider = Provider<ContactGroupService>((ref) {
  final service = ContactGroupService();
  service.initialize();
  return service;
});

final nfcServiceProvider = Provider<NfcService>((ref) {
  final contactService = ref.read(contactServiceProvider);
  final service = NfcService(contactService);
  service.initialize();
  return service;
});

final meshChatServiceProvider = Provider<MeshChatService>((ref) {
  return MeshChatService();
});

final groupChannelServiceProvider = Provider<GroupChannelService>((ref) {
  return GroupChannelService();
});

final callServiceProvider = Provider<CallService>((ref) {
  final wifi = ref.read(wifiDirectServiceProvider);
  return CallService(
    wifiService: wifi,
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

final sosServiceProvider = Provider<SosService>((ref) {
  final ble = ref.read(bleMeshServiceProvider);
  final wifi = ref.read(wifiDirectServiceProvider);
  final contacts = ref.read(contactServiceProvider);
  final identity = ref.read(identityServiceProvider);
  return SosService(
    bleMesh: ble,
    wifiDirect: wifi,
    contactService: contacts,
    myDeviceId: identity.currentIdentity?.deviceId ?? '',
  );
});

final stealthServiceProvider = Provider<StealthService>((ref) {
  return StealthService();
});

final locationSafetyServiceProvider = Provider<LocationSafetyService>((ref) {
  return LocationSafetyService();
});

final identityReadyProvider = StateProvider<bool>((ref) => false);
final currentIdentityProvider = StateProvider<MeshIdentity?>((ref) => null);
final contactListProvider = StateProvider<List<Contact>>((ref) => []);
final conversationListProvider =
    StateProvider<List<ConversationPreview>>((ref) => []);
final locationStreamProvider = StreamProvider<Map<String, UserLocation>>((ref) {
  return ref.watch(locationSafetyServiceProvider).locationUpdates;
});

/// ─── New MeshLink Service Providers ───

final platformBridgeProvider = Provider<PlatformChannelBridge>((ref) {
  final bridge = PlatformChannelBridge();
  bridge.initialize();
  return bridge;
});

final storeForwardServiceProvider = Provider<StoreForwardService>((ref) {
  return StoreForwardService();
});

final onionRouterProvider = Provider<OnionRouter>((ref) {
  return OnionRouter();
});

final privacyLayerProvider = Provider<PrivacyLayer>((ref) {
  return PrivacyLayer();
});

final deadDropServiceProvider = Provider<DeadDropService>((ref) {
  return DeadDropService();
});

final voiceMessageServiceProvider = Provider<VoiceMessageService>((ref) {
  return VoiceMessageService();
});

final disappearingMessageServiceProvider =
    Provider<DisappearingMessageService>((ref) {
  return DisappearingMessageService();
});

final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService();
});

final channelHopperProvider =
    Provider.family<ChannelHopper, List<int>>((ref, secretBytes) {
  return ChannelHopper(sharedSecret: Uint8List.fromList(secretBytes));
});

final reactionServiceProvider = Provider<ReactionService>((ref) {
  final service = ReactionService();
  service.initialize();
  return service;
});

final replyServiceProvider = Provider<ReplyService>((ref) {
  final service = ReplyService();
  service.initialize();
  return service;
});

final presenceServiceProvider = Provider<PresenceService>((ref) {
  final service = PresenceService();
  service.initialize();
  return service;
});

final keyVerificationServiceProvider = Provider<KeyVerificationService>((ref) {
  return KeyVerificationService();
});

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

final decoyServiceProvider = Provider<DecoyService>((ref) {
  return DecoyService();
});

final pollServiceProvider = Provider<PollService>((ref) {
  final service = PollService();
  service.initialize();
  return service;
});

final pinServiceProvider = Provider<PinService>((ref) {
  final service = PinService();
  service.initialize();
  return service;
});

final wallpaperServiceProvider = Provider<WallpaperService>((ref) {
  final service = WallpaperService();
  service.initialize();
  return service;
});

final scheduleServiceProvider = Provider<ScheduleService>((ref) {
  final service = ScheduleService();
  service.initialize();
  return service;
});

final locationShareServiceProvider = Provider<LocationShareService>((ref) {
  return LocationShareService();
});

final panicButtonServiceProvider = Provider<PanicButtonService>((ref) {
  final safety = ref.read(locationSafetyServiceProvider);
  final service = PanicButtonService(safety);
  service.startListening();
  return service;
});

final offlineAIServiceProvider = Provider<OfflineAIService>((ref) {
  return OfflineAIService();
});

final gamificationEngineProvider = Provider<GamificationEngine>((ref) {
  return GamificationEngine();
});

final missionPlannerProvider = Provider<MissionPlanner>((ref) {
  return MissionPlanner();
});

final crowdIntelProvider = Provider<CrowdIntelligence>((ref) {
  return CrowdIntelligence();
});

final currentThemeProvider =
    StateProvider<AppThemeMode>((ref) => AppThemeMode.chaaya);
final currentFolderProvider =
    StateProvider<ChatFolder>((ref) => ChatFolder.all);

/// ─── V2 Network Service Providers ───

final dtnBundleProtocolProvider = Provider<DTNBundleProtocol>((ref) {
  return DTNBundleProtocol();
});

final epidemicSpreadProtocolProvider = Provider<EpidemicSpreadProtocol>((ref) {
  return EpidemicSpreadProtocol();
});

final mixnetRouterProvider = Provider<MixnetRouter>((ref) {
  return MixnetRouter();
});

final predictiveFailureDetectorProvider =
    Provider<PredictiveFailureDetector>((ref) {
  return PredictiveFailureDetector();
});

final adaptiveRoutingEngineProvider = Provider<AdaptiveRoutingEngine>((ref) {
  return AdaptiveRoutingEngine();
});

final routeOptimizerProvider = Provider<RouteOptimizer>((ref) {
  final nodeReputation = ref.read(nodeReputationSystemProvider);
  return RouteOptimizer(nodeReputation);
});

final qosSchedulerProvider = Provider<QoSScheduler>((ref) {
  return QoSScheduler();
});

/// ─── V2 Intelligence Providers ───

final contextAwareUIEngineProvider = Provider<ContextAwareUIEngine>((ref) {
  return ContextAwareUIEngine();
});

/// ─── V2 Power Providers ───

final survivalModeProvider = Provider<SurvivalMode>((ref) {
  return SurvivalMode();
});

/// ─── V2 Storage Providers ───

final distributedStorageProvider = Provider<DistributedStorage>((ref) {
  return DistributedStorage();
});

/// ─── V2 Sync Providers ───

final dedupCacheProvider = Provider<DedupCache>((ref) {
  return DedupCache();
});

final crdtMessageStoreProvider = Provider<CRDTMessageStore>((ref) {
  final store = CRDTMessageStore();
  store.initialize();
  return store;
});

final vectorClockProvider = Provider<VectorClock>((ref) {
  final identity = ref.read(identityServiceProvider);
  return VectorClock(identity.currentIdentity?.deviceId ?? 'unknown');
});

/// ─── V2 Crypto Providers ───

final keyRotationManagerProvider = Provider<KeyRotationManager>((ref) {
  return KeyRotationManager();
});

final antiReplayCacheProvider = Provider<AntiReplayCache>((ref) {
  return AntiReplayCache();
});

final messageValidatorProvider = Provider<MessageValidator>((ref) {
  return MessageValidator();
});

/// ─── V2 Mesh Providers ───

final nodeReputationSystemProvider = Provider<NodeReputationSystem>((ref) {
  return NodeReputationSystem();
});

final adaptiveBLEScannerProvider = Provider<AdaptiveBLEScanner>((ref) {
  return AdaptiveBLEScanner();
});
