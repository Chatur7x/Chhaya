import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../../core/crypto/key_manager.dart';
import '../../core/crypto/primitives/aes_gcm.dart';
import '../../core/crypto/primitives/rng.dart';
import '../../core/crypto/ratchet/session_store.dart';
import '../../core/crypto/ratchet/session_state.dart';
import '../../core/database/local_database.dart';
import '../../core/models/contact.dart';
import '../../core/models/conversation.dart';
import '../../core/models/message.dart';
import '../../core/models/message_attachment.dart';
import 'message_payload.dart';
import 'poll_payload.dart';
import '../api/api_service.dart';
import 'ratchet_message_codec.dart';
import 'pq_hybrid_v1.dart';

/// The message has committed locally; retry its existing ID instead of composing again.
class MessageQueuedException implements Exception {
  final Message message;
  final bool membershipChanged;
  MessageQueuedException(this.message, {this.membershipChanged = false});
  @override
  String toString() => 'Message saved on this device and waiting to send';
}

class MessagingService {
  final ApiService api;
  final LocalDatabase database;
  final KeyManager keys;
  Future<void> _tail = Future<void>.value();
  MessagingService({
    required this.api,
    required this.database,
    required this.keys,
  });

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  /// Session/resync bookkeeping must never break delivery for databases
  /// without kv (in-memory test doubles): failures degrade to no-ops.
  Future<T?> _softDb<T>(Future<T> Function(LocalDatabase db) fn) async {
    try {
      return await fn(database);
    } catch (_) {
      return null;
    }
  }

  /// Handles the post-restore hold (spec §3.7): when this device restored
  /// and the conversation awaits a peer ack, user content is NOT sent; the
  /// resync envelope goes out instead. Returns true when the message must
  /// be held (caller persists it and throws MessageQueuedException).
  Future<bool> _holdForResync(
    Conversation conversation,
    Message message,
    List<Contact> peers,
  ) async {
    if (!await PqHybridV1.enabled()) return false;
    if (await _softDb((db) => db.sessionGenerationState(conversation.id)) == 'rollback') {
      // Rollback is a forced resync (spec §3.8); mark it explicitly unless
      // a marker is already pending.
      if (await _softDb((db) => db.readResyncPending(conversation.id)) == null) {
        await _softDb((db) =>
            db.markResyncPending(conversation.id, reason: 'rollback'));
      }
    }
    final pending = await _softDb((db) => db.readResyncPending(conversation.id));
    if (pending == null) return false;
    if (conversation.isGroup) {
      await _sendGroupResyncIfNeeded(conversation, peers);
    } else if (peers.length == 1) {
      await _sendResyncIfNeeded(peers.single, conversation, pending);
    }
    await database.addMessage(message);
    return true;
  }

  Future<RatchetMessageCodec> _codec() async {
    final identity = await keys.getKeyPair();
    final profile = await database.getUserProfile();
    if (identity == null || profile == null) {
      throw StateError('Account is locked');
    }
    // Loopback/unit tests explicitly install a fake bundle server via the
    // PqHybridV1 seam; it wins over the production client in tests only.
    final bundleFetcher = PqHybridV1.testBundleFetcher ??
        PqHybridV1.productionBundleFetcher(
          apiAuthenticated: api.isAuthenticated,
          authToken: api.authToken,
          baseUrl: api.baseUrl,
        );
    return RatchetMessageCodec(
      sessions: LocalDatabaseSessionStorage(database),
      identity: identity,
      ownId: profile.chhayaId.publicKey,
      database: database,
      bundleFetcher: bundleFetcher,
      ed25519PublicKey: () async =>
          PqHybridV1.testEd25519PublicKey?.call(identity.publicKey) ??
          keys.getIdentityEd25519PublicKeyBytes(),
    );
  }

  /// 30 s throttle for outbound resync envelopes per conversation.
  static const Duration _resyncThrottle = Duration(seconds: 30);

  /// Sends the resync envelope for [pending] (spec §3.7 initiator side).
  /// Establishes the v2 session first when absent; user content is never
  /// included. No message row is written — sync/retry delivers the queue
  /// after the ack arrives.
  Future<void> _sendResyncIfNeeded(
    Contact peer,
    Conversation conversation,
    ({String restoreGeneration, String reason}) pending,
  ) async {
    if (!api.isAuthenticated) return;
    final conversationId = conversation.id;
    final sessionKey = '$conversationId:${peer.chhayaId.publicKey}';
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final sessionExists =
        await database.loadSessionBlob(sessionKey) != null;
    final lastRaw = await _softDb((db) => db.readPlainKv(
      LocalDatabase.resyncSentKey(conversationId),
    ));
    final last = lastRaw == null ? null : int.tryParse(lastRaw);
    if (sessionExists &&
        last != null &&
        nowMs - last < _resyncThrottle.inMilliseconds) {
      return; // recently sent and the session exists; the queue holds.
    }
    final codec = await _codec();
    final resyncMessageId = const Uuid().v4();
    final payload = <String, dynamic>{
      'type': resyncPayloadType,
      'restore_generation': pending.restoreGeneration,
      'session_generation': await codec.generationMax(conversationId),
      'reason': pending.reason,
      'v': 1,
    };
    final envelope = await codec.encrypt(
      peer,
      conversationId,
      resyncMessageId,
      api.userId!,
      payload,
    );
    await api.sendMessage(
      conversationId: conversationId,
      content: envelope,
      messageId: resyncMessageId,
    );
    await _softDb((db) => db.writePlainKv(
      LocalDatabase.resyncSentKey(conversationId),
      nowMs.toString(),
    ));
    await _softDb((db) => db.writePlainKv(
      LocalDatabase.postRestoreUnverifiedKey(conversationId),
      '1',
    ));
  }

  /// Re-creates stuck pending messages from DB content with fresh ids and
  /// re-encrypts under the current session (spec §3.7.5). Marks originals
  /// superseded (kv tombstone) — they stay in the DB for forensics.
  Future<void> _recreateStuckPendingDirect(
    Conversation conversation,
    Contact peer,
  ) async {
    final conversationId = conversation.id;
    if (await _softDb((db) => db.readResyncPending(conversationId)) != null) {
      return; // await the ack first
    }
    final codec = await _codec();
    for (final message in await database.getPendingMessages(conversationId)) {
      if (message.senderId != 'me' || message.isSent || message.isExpired) {
        continue;
      }
      if (await database.loadSessionBlob('outbox:${message.id}') != null) {
        continue; // normal pending; retryPending delivers the exact envelope
      }
      if ((await _softDb((db) => db.readPlainKv(
            LocalDatabase.resyncSupersededKey(message.id),
          ))) !=
          null) {
        continue;
      }
      final newId = const Uuid().v4();
      final newMessage = message.copyWith(id: newId);
      final String envelope;
      try {
        envelope = await codec.encrypt(
          peer,
          conversationId,
          newId,
          api.userId!,
          MessagePayload.encode(newMessage),
          commit: (state, envelope) =>
              database.commitOutgoingMessage(state, newMessage, envelope),
        );
      } catch (_) {
        // Cannot establish right now (flag off, rollback, unavailable peer):
        // leave the original pending for a later retry.
        continue;
      }
      await _softDb((db) => db.writePlainKv(
        LocalDatabase.resyncSupersededKey(message.id),
        '1',
      ));
      try {
        await _deliver(newMessage, envelope);
      } catch (_) {
        // Outbox committed; retryPending will re-deliver the exact envelope.
      }
    }
  }

  /// Group analog of the stuck-pending re-creation (spec §3.7.5): re-issues
  /// each me-pending, unsent group message from DB content with a fresh id.
  Future<void> _resumePendingGroupResync(Conversation conversation) async {
    if (!api.isAuthenticated) return;
    if (await _softDb((db) => db.readResyncPending(conversation.id)) != null) {
      return; // await the ack first
    }
    for (final message in await database.getPendingMessages(conversation.id)) {
      if (message.senderId != 'me' || message.isSent || message.isExpired) {
        continue;
      }
      if (message.type == MessageType.poll) {
        // Poll re-validation is not safe to replay blindly; leave pending.
        continue;
      }
      if (await database.loadSessionBlob('outbox:${message.id}') != null) {
        continue; // normal pending; retryPending delivers the exact envelope
      }
      if ((await _softDb((db) => db.readPlainKv(
            LocalDatabase.resyncSupersededKey(message.id),
          ))) !=
          null) {
        continue;
      }
      try {
        await _sendGroup(
          conversation,
          message.content,
          ttl: message.ttl,
          replyToId: message.replyToId,
          attachment: message.attachment,
          type: message.type,
        );
        await _softDb((db) => db.writePlainKv(
          LocalDatabase.resyncSupersededKey(message.id),
          '1',
        ));
      } on MessageQueuedException {
        // Committed with a fresh id; the ack path/retry delivers it.
        await _softDb((db) => db.writePlainKv(
          LocalDatabase.resyncSupersededKey(message.id),
          '1',
        ));
      } catch (_) {
        // Pre-commit failure; leave the original pending for a later resume.
        continue;
      }
    }
  }

  /// Responder-side resync handling after a valid inbound resync payload
  /// (spec §3.7): adopt max restore_generation, mark, and emit the ack
  /// (idempotent re-ack on replay, no re-increment — spec §3.7 rule).
  Future<void> _sendResyncAck(
    Contact peer,
    String conversationId,
    Map<String, dynamic> payload,
  ) async {
    if (!api.isAuthenticated) return;
    final theirsRaw = payload['restore_generation'];
    final theirsGen = theirsRaw is String &&
            RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
                .hasMatch(theirsRaw)
        ? theirsRaw
        : null;
    final adopted = await _softDb((db) =>
        db.adoptRestoreGeneration(conversationId, theirsGen));
    await _softDb((db) => db.writePlainKv(
      LocalDatabase.peerRestoredKey(conversationId),
      '1',
    ));
    final codec = await _codec();
    final ackedKey = LocalDatabase.resyncAckedKey(
      conversationId,
      adopted ?? 'unknown',
    );
    if ((await _softDb((db) => db.readPlainKv(ackedKey))) != '1') {
      await _softDb((db) => db.writePlainKv(ackedKey, '1'));
      await codec.incrementGeneration(conversationId);
    }
    final ack = <String, dynamic>{
      'type': resyncAckPayloadType,
      if (adopted != null) 'restore_generation': adopted,
      'session_generation': await codec.generationMax(conversationId),
      'v': 1,
    };
    final ackMessageId = const Uuid().v4();
    final echo = await codec.ownOfferEcho();
    final envelope = await codec.encrypt(
      peer,
      conversationId,
      ackMessageId,
      api.userId!,
      ack,
      echo: echo,
    );
    await api.sendMessage(
      conversationId: conversationId,
      content: envelope,
      messageId: ackMessageId,
    );
  }

  /// Group-member resync receipt (spec §3.7, per-member path): adopt max
  /// generation, mark, and increment once per restore_generation. The
  /// member's next outbound (any AEAD-valid v2 message) is its ack; there
  /// is deliberately no proactive group ack envelope (see WS3 report).
  Future<void> _processGroupResync(
    String conversationId,
    Map<String, dynamic> payload,
  ) async {
    final theirsRaw = payload['restore_generation'];
    final theirsGen = theirsRaw is String &&
            RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
                .hasMatch(theirsRaw)
        ? theirsRaw
        : null;
    final adopted = await _softDb((db) =>
        db.adoptRestoreGeneration(conversationId, theirsGen));
    await _softDb((db) => db.writePlainKv(
      LocalDatabase.peerRestoredKey(conversationId),
      '1',
    ));
    final codec = await _codec();
    final ackedKey = LocalDatabase.resyncAckedKey(
      conversationId,
      adopted ?? 'unknown',
    );
    if ((await _softDb((db) => db.readPlainKv(ackedKey))) != '1') {
      await _softDb((db) => db.writePlainKv(ackedKey, '1'));
      await codec.incrementGeneration(conversationId);
    }
  }

  /// Sends the resync-only group envelope (all wrappers carry
  /// `chhaya-resync-v1`) — used when this device restored and must
  /// re-establish before any content flows (spec §3.7).
  Future<bool> _sendGroupResyncIfNeeded(
    Conversation conversation,
    List<Contact> peers,
  ) async {
    if (!api.isAuthenticated || api.userId == null) return false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastRaw = await _softDb((db) => db.readPlainKv(
      LocalDatabase.resyncSentKey(conversation.id),
    ));
    final last = lastRaw == null ? null : int.tryParse(lastRaw);
    if (last != null && nowMs - last < _resyncThrottle.inMilliseconds) {
      return false;
    }
    final pending = await _softDb((db) => db.readResyncPending(conversation.id));
    if (pending == null) return false;
    final codec = await _codec();
    final groupMessageId = const Uuid().v4();
    final payload = <String, dynamic>{
      'type': resyncPayloadType,
      'restore_generation': pending.restoreGeneration,
      'session_generation': await codec.generationMax(conversation.id),
      'reason': pending.reason,
      'v': 1,
    };
    final states = <SessionState>[];
    try {
      final wrappers = <String, String>{};
      for (final peer in peers) {
        final prepared = await codec.prepareEncrypt(
          peer,
          conversation.id,
          groupMessageId,
          api.userId!,
          payload,
        );
        states.add(prepared.state);
        wrappers[peer.id] = prepared.envelope;
      }
      // The body is opaque filler: after a restore every member wrapper
      // carries chhaya-resync-v1, so no member decrypts it.
      final contentKey = Csprng.instance.bytes(32);
      final body = AesGcm.encryptBytes(
        contentKey,
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        aad: _groupBodyAad(conversation.id, groupMessageId, api.userId!),
      );
      Csprng.wipe(contentKey);
      final envelope = jsonEncode({
        'v': 1,
        'kind': 'chhaya-group-v1',
        'conversationId': conversation.id,
        'messageId': groupMessageId,
        'senderId': api.userId!,
        'keys': wrappers,
        'body': base64Encode(body),
      });
      // Ratchet-only commits: no message row, no outbox — the resync-only
      // envelope exists to re-establish pairwise sessions.
      for (final state in states) {
        await database.commitRatchetOnly(state);
      }
      await api.sendMessage(
        conversationId: conversation.id,
        content: envelope,
        messageId: groupMessageId,
      );
      await _softDb((db) => db.writePlainKv(
        LocalDatabase.resyncSentKey(conversation.id),
        nowMs.toString(),
      ));
      await _softDb((db) => db.writePlainKv(
        LocalDatabase.postRestoreUnverifiedKey(conversation.id),
        '1',
      ));
      return true;
    } finally {
      for (final state in states) {
        state.wipe();
      }
    }
  }

  Future<Message> send(
    Conversation conversation,
    String text, {
    Duration? ttl,
    bool disableTtl = false,
    String? replyToId,
    MessageAttachment? attachment,
    MessageType type = MessageType.text,
  }) => _serial(() async {
    if (!api.isAuthenticated) {
      throw StateError('Connect your server in Settings first');
    }
    if (type == MessageType.poll) {
      await _validatePollContent(conversation.id, text, DateTime.now());
    }
    if (conversation.isGroup) {
      return _sendGroup(
        conversation,
        text,
        ttl: ttl,
        disableTtl: disableTtl,
        replyToId: replyToId,
        attachment: attachment,
        type: type,
      );
    }
    if (conversation.participants.length != 1) {
      throw StateError('Conversation must have exactly one recipient');
    }
    final peer =
        await database.getContact(conversation.participants.single.id) ??
        conversation.participants.single;
    if (peer.isBlocked || database.getBlockedContacts().contains(peer.id)) {
      throw StateError('Unblock this contact before sending messages');
    }
    final globalTtl = database.getGlobalDisappearingDuration();
    final effectiveTtl = disableTtl
        ? null
        : ttl ?? (globalTtl > 0 ? Duration(seconds: globalTtl) : null);
    final message = Message(
      id: const Uuid().v4(),
      conversationId: conversation.id,
      senderId: 'me',
      content: text,
      timestamp: DateTime.now(),
      isSent: false,
      ttl: effectiveTtl,
      replyToId: replyToId,
      attachment: attachment,
      type: type,
    );
    if (await _holdForResync(conversation, message, [peer])) {
      throw MessageQueuedException(message);
    }
    final envelope = await (await _codec()).encrypt(
      peer,
      conversation.id,
      message.id,
      api.userId!,
      MessagePayload.encode(message),
      commit: (state, envelope) =>
          database.commitOutgoingMessage(state, message, envelope),
    );
    try {
      return await _deliver(message, envelope);
    } catch (_) {
      throw MessageQueuedException(message);
    }
  });

  Future<Message> _sendGroup(
    Conversation conversation,
    String text, {
    Duration? ttl,
    bool disableTtl = false,
    String? replyToId,
    MessageAttachment? attachment,
    required MessageType type,
  }) async {
    if (conversation.participants.isEmpty) {
      throw StateError('Group must contain at least one other member');
    }
    final profile = await database.getUserProfile();
    if (profile == null || api.userId == null) {
      throw StateError('Account is locked');
    }
    final peers = <Contact>[];
    for (final participant in conversation.participants) {
      if (participant.id == api.userId) continue;
      final peer = await database.getContact(participant.id) ?? participant;
      if (!peer.isVerified) {
        throw StateError('Verify every group member before messaging');
      }
      if (peer.isBlocked || database.getBlockedContacts().contains(peer.id)) {
        throw StateError('Unblock every group member before messaging');
      }
      peers.add(peer);
    }
    if (peers.isEmpty) {
      throw StateError('Group must contain at least one other member');
    }
    final message = Message(
      id: const Uuid().v4(),
      conversationId: conversation.id,
      senderId: 'me',
      content: text,
      timestamp: DateTime.now(),
      isSent: false,
      ttl: disableTtl
          ? null
          : ttl ??
                (database.getGlobalDisappearingDuration() > 0
                    ? Duration(
                        seconds: database.getGlobalDisappearingDuration(),
                      )
                    : null),
      replyToId: replyToId,
      attachment: attachment,
      type: type,
    );
    if (await _holdForResync(conversation, message, peers)) {
      throw MessageQueuedException(message);
    }
    final contentKey = Csprng.instance.bytes(32);
    final bodyAad = _groupBodyAad(conversation.id, message.id, api.userId!);
    final body = AesGcm.encryptBytes(
      contentKey,
      Uint8List.fromList(
        utf8.encode(jsonEncode(MessagePayload.encode(message))),
      ),
      aad: bodyAad,
    );
    final codec = await _codec();
    final states = <SessionState>[];
    try {
      final wrappers = <String, String>{};
      for (final peer in peers) {
        final prepared = await codec
            .prepareEncrypt(peer, conversation.id, message.id, api.userId!, {
              'kind': 'chhaya-group-key-v1',
              'conversationId': conversation.id,
              'messageId': message.id,
              'senderId': api.userId!,
              'key': base64Encode(contentKey),
            });
        states.add(prepared.state);
        wrappers[peer.id] = prepared.envelope;
      }
      final envelope = jsonEncode({
        'v': 1,
        'kind': 'chhaya-group-v1',
        'conversationId': conversation.id,
        'messageId': message.id,
        'senderId': api.userId!,
        'keys': wrappers,
        'body': base64Encode(body),
      });
      await database.commitOutgoingGroupMessage(states, message, envelope);
      try {
        return await _deliver(message, envelope);
      } on ApiException catch (error) {
        throw MessageQueuedException(
          message,
          membershipChanged:
              error.statusCode == 409 &&
              error.message ==
                  'Group membership changed; refresh before sending',
        );
      } catch (_) {
        throw MessageQueuedException(message);
      }
    } finally {
      Csprng.wipe(contentKey);
      for (final state in states) {
        state.wipe();
      }
    }
  }

  Uint8List _groupBodyAad(
    String conversationId,
    String messageId,
    String senderId,
  ) => Uint8List.fromList(
    utf8.encode(
      jsonEncode(['chhaya-group-body-v1', conversationId, messageId, senderId]),
    ),
  );

  Future<Message> _deliver(Message message, String envelope) async {
    await api.sendMessage(
      conversationId: message.conversationId,
      content: envelope,
      messageId: message.id,
    );
    final sent = message.copyWith(isSent: true);
    await database.commitMessageSent(sent);
    return sent;
  }

  Future<void> retryPending(String conversationId) => _serial(() async {
    if (!api.isAuthenticated) return;
    final conversation = (await database.getAllConversations())
        .where((c) => c.id == conversationId)
        .firstOrNull;
    if (conversation == null ||
        (!conversation.isGroup && conversation.participants.length != 1)) {
      return;
    }
    if (conversation.isGroup) {
      for (final participant in conversation.participants) {
        if (participant.id == api.userId) {
          continue;
        }
        final peer = await database.getContact(participant.id) ?? participant;
        if (!peer.isVerified ||
            peer.isBlocked ||
            database.getBlockedContacts().contains(peer.id)) {
          return;
        }
      }
      ApiException? staleMembership;
      for (final message in await database.getPendingMessages(conversationId)) {
        if (message.senderId != 'me' || message.isSent || message.isExpired) {
          continue;
        }
        final envelope = await database.loadSessionBlob('outbox:${message.id}');
        if (envelope != null) {
          try {
            await _deliver(message, envelope);
          } on ApiException catch (error) {
            if (error.statusCode == 409 &&
                error.message ==
                    'Group membership changed; refresh before sending') {
              staleMembership = error;
              continue;
            }
            rethrow;
          }
        }
      }
      if (staleMembership != null) throw staleMembership;
      return;
    }
    final peer =
        await database.getContact(conversation.participants.single.id) ??
        conversation.participants.single;
    if (!peer.isVerified ||
        peer.isBlocked ||
        database.getBlockedContacts().contains(peer.id)) {
      return;
    }
    for (final message in await database.getPendingMessages(conversationId)) {
      if (message.senderId != 'me' || message.isSent || message.isExpired) {
        continue;
      }
      final envelope = await database.loadSessionBlob('outbox:${message.id}');
      if (envelope != null) {
        await _deliver(message, envelope);
        continue;
      }
      // Restore-stuck pending message: re-create from DB content with a
      // fresh messageId under the current session (spec §3.7.5). The
      // helper iterates every stuck row for this conversation.
      await _recreateStuckPendingDirect(conversation, peer);
      break;
    }
  });

  Future<void> retryAllPending() async {
    if (!api.isAuthenticated) return;
    for (final conversation in await database.getAllConversations()) {
      try {
        await retryPending(conversation.id);
      } catch (_) {
        if (!api.isAuthenticated) return;
      }
    }
  }

  Future<List<Conversation>> sync() => _serial(() async {
    if (!api.isAuthenticated) {
      return database.getAllConversations();
    }
    final resyncsToAck =
        <({Contact peer, String conversationId, Map<String, dynamic> payload})>[];
    final contacts = await database.getAllContacts();
    final remote = await api.getConversations();
    final existing = await database.getAllConversations();
    final result = <Conversation>[];
    for (final conversation in remote) {
      final peers = <Contact>[];
      for (final peer in conversation.participants) {
        if (peer.id == api.userId) continue;
        final old = contacts
            .where((c) => c.id == peer.id && c.chhayaId == peer.chhayaId)
            .firstOrNull;
        final contact = old ?? peer;
        await database.addContact(contact);
        peers.add(contact);
      }
      final previous = existing
          .where((c) => c.id == conversation.id)
          .firstOrNull;
      var updated = conversation.copyWith(
        participants: peers,
        isMuted: previous?.isMuted,
        isPinned: previous?.isPinned,
      );
      await database.addConversation(updated);
      final known = <String>{};
      if (conversation.isGroup &&
          peers.isNotEmpty &&
          peers.every((peer) => peer.isVerified)) {
        final batches = <Message>[];
        String? beforeId;
        for (var page = 0; page < 50; page++) {
          final batch = await api.getMessages(
            conversation.id,
            limit: 200,
            beforeId: beforeId,
          );
          known.addAll(
            await database.getKnownMessageIds(
              conversation.id,
              messageIds: batch.map((message) => message.id).toList(),
            ),
          );
          batches.insertAll(0, batch);
          if (batch.length < 200 || batch.every((m) => known.contains(m.id))) {
            break;
          }
          beforeId = batch.first.id;
        }
        final codec = await _codec();
        for (final message in batches) {
          if (message.senderId == api.userId) {
            final saved = await database.getMessage(
              conversation.id,
              message.id,
            );
            if (saved != null &&
                (saved.isRead != message.isRead ||
                    saved.isDelivered != message.isDelivered)) {
              await database.addMessage(
                saved.copyWith(
                  isRead: message.isRead,
                  isDelivered: message.isDelivered,
                ),
              );
            }
            continue;
          }
          if (known.contains(message.id)) {
            continue;
          }
          try {
            final wire = jsonDecode(message.content) as Map<String, dynamic>;
            if (wire['v'] != 1 ||
                wire['kind'] != 'chhaya-group-v1' ||
                wire['conversationId'] != conversation.id ||
                wire['messageId'] != message.id ||
                wire['senderId'] != message.senderId) {
              throw const FormatException('Invalid group envelope');
            }
            final sender =
                peers.where((p) => p.id == message.senderId).firstOrNull ??
                await database.getContact(message.senderId);
            if (sender == null || !sender.isVerified) continue;
            final keys = Map<String, dynamic>.from(wire['keys'] as Map);
            final recipientEnvelope = keys[api.userId];
            // Preserve a visible gap for historical records with no key
            // wrapper for this device instead of silently dropping them.
            if (recipientEnvelope is! String) {
              await database.addMessage(
                Message(
                  id: message.id,
                  conversationId: conversation.id,
                  senderId: '__system__',
                  content:
                      'This encrypted message is unavailable in this device’s history.',
                  type: MessageType.system,
                  timestamp: message.timestamp,
                  isSent: true,
                  isDelivered: true,
                  isRead: true,
                ),
              );
              continue;
            }
            await codec.decrypt(
              sender,
              conversation.id,
              message.id,
              message.senderId,
              recipientEnvelope,
              commit: (state, wrapped) async {
                if (wrapped['type'] == resyncPayloadType) {
                  // Restoring member's resync rides its pairwise session;
                  // commit the ratchet, no message row (spec §3.7).
                  await database.commitRatchetOnly(state);
                  await _processGroupResync(conversation.id, wrapped);
                  return;
                }
                if (wrapped['kind'] != 'chhaya-group-key-v1' ||
                    wrapped['conversationId'] != conversation.id ||
                    wrapped['messageId'] != message.id ||
                    wrapped['senderId'] != message.senderId) {
                  throw const FormatException('Invalid group key wrapper');
                }
                final key = base64Decode(wrapped['key'] as String);
                if (key.length != 32) {
                  Csprng.wipe(key);
                  throw const FormatException('Invalid group key');
                }
                try {
                  final plain = AesGcm.decryptBytes(
                    key,
                    base64Decode(wire['body'] as String),
                    aad: _groupBodyAad(
                      conversation.id,
                      message.id,
                      message.senderId,
                    ),
                  );
                  final payload =
                      jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
                  final received = await _decodePayload(message, payload);
                  await database.commitReceivedMessage(state, received);
                } finally {
                  Csprng.wipe(key);
                }
              },
            );
          } catch (_) {
            // Ignore one malformed/unsupported remote row without aborting the rest of sync.
          }
        }
      } else if (!conversation.isGroup &&
          peers.length == 1 &&
          peers.single.isVerified) {
        final batches = <Message>[];
        String? beforeId;
        for (var page = 0; page < 50; page++) {
          final batch = await api.getMessages(
            conversation.id,
            limit: 200,
            beforeId: beforeId,
          );
          known.addAll(
            await database.getKnownMessageIds(
              conversation.id,
              messageIds: batch.map((message) => message.id).toList(),
            ),
          );
          batches.insertAll(0, batch);
          if (batch.length < 200 || batch.every((m) => known.contains(m.id))) {
            break;
          }
          beforeId = batch.first.id;
        }
        final codec = await _codec();
        for (final message in batches) {
          if (message.senderId == api.userId) {
            final saved = await database.getMessage(
              conversation.id,
              message.id,
            );
            if (saved != null &&
                (saved.isRead != message.isRead ||
                    saved.isDelivered != message.isDelivered)) {
              await database.addMessage(
                saved.copyWith(
                  isRead: message.isRead,
                  isDelivered: message.isDelivered,
                ),
              );
            }
            continue;
          }
          if (known.contains(message.id)) {
            continue;
          }
          try {
            await codec.decrypt(
              peers.single,
              conversation.id,
              message.id,
              message.senderId,
              message.content,
              commit: (state, payload) async {
                if (payload['type'] == resyncPayloadType) {
                  // Restoring peer's resync: commit the ratchet, no message
                  // row; the ack flushes after the batch loop.
                  await database.commitRatchetOnly(state);
                  resyncsToAck.add((
                    peer: peers.single,
                    conversationId: conversation.id,
                    payload: payload,
                  ));
                  return;
                }
                final received = await _decodePayload(message, payload);
                await database.commitReceivedMessage(state, received);
              },
            );
          } catch (_) {
            // A malformed row must not prevent later authenticated messages syncing.
          }
        }
      }
      // v2 resync post-processing (flag-gated no-op otherwise): resume the
      // local queue after an ack, flush acks for inbound resyncs, and
      // (re)fire our own resync while a restore is unacknowledged.
      if (await PqHybridV1.enabled()) {
        final resume = await _softDb(
          (db) => db.readPlainKv(LocalDatabase.resyncResumeKey(conversation.id)),
        );
        if (resume == '1') {
          await _softDb(
            (db) => db.deletePlainKv(LocalDatabase.resyncResumeKey(conversation.id)),
          );
          if (conversation.isGroup) {
            await _resumePendingGroupResync(conversation);
          } else if (peers.length == 1 &&
              peers.single.isVerified &&
              !peers.single.isBlocked &&
              !database.getBlockedContacts().contains(peers.single.id)) {
            await _recreateStuckPendingDirect(conversation, peers.single);
          }
        }
        for (final item in resyncsToAck) {
          if (item.conversationId == conversation.id) {
            try {
              await _sendResyncAck(item.peer, item.conversationId, item.payload);
            } catch (_) {
              // Ack delivery failed; the next inbound resync triggers a
              // re-ack (replayed resync ⇒ idempotent re-ack).
            }
          }
        }
        final pending = await _softDb((db) => db.readResyncPending(conversation.id));
        if (pending != null) {
          final verified = peers
              .where((p) =>
                  p.isVerified &&
                  !p.isBlocked &&
                  !database.getBlockedContacts().contains(p.id))
              .toList();
          if (conversation.isGroup) {
            if (verified.isNotEmpty) {
              await _sendGroupResyncIfNeeded(conversation, verified);
            }
          } else if (verified.length == 1) {
            await _sendResyncIfNeeded(verified.single, conversation, pending);
          }
        }
      }
      final latest = await database.getLatestMessage(conversation.id);
      if (latest != null) {
        updated = updated.copyWith(lastMessage: latest);
      }
      await database.addConversation(updated);
      result.add(updated);
    }
    return result;
  });

  Future<Message> _decodePayload(
    Message envelope,
    Map<String, dynamic> payload,
  ) async {
    final message = MessagePayload.decode(envelope, payload);
    if (message.type == MessageType.poll) {
      await _validatePollContent(
        message.conversationId,
        message.content,
        message.timestamp,
      );
    }
    return message;
  }

  Future<void> _validatePollContent(
    String conversationId,
    String content,
    DateTime at,
  ) async {
    final value = jsonDecode(content) as Map<String, dynamic>;
    if (value['kind'] == 'definition') {
      PollPayload.decodeDefinition(value);
      return;
    }
    final vote = PollPayload.decodeVote(value);
    final history = await database.getMessages(conversationId);
    PollDefinition? definition;
    for (final item in history) {
      if (item.type != MessageType.poll) continue;
      try {
        final event = jsonDecode(item.content) as Map<String, dynamic>;
        if (event['kind'] == 'definition' && event['pollId'] == vote.pollId) {
          definition = PollPayload.decodeDefinition(event);
          break;
        }
      } catch (_) {
        continue;
      }
    }
    if (definition == null) {
      throw const FormatException('This poll is unavailable');
    }
    PollPayload.decodeVote(value, definition: definition, votedAt: at);
  }
}
