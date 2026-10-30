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

  Future<RatchetMessageCodec> _codec() async {
    final identity = await keys.getKeyPair();
    final profile = await database.getUserProfile();
    if (identity == null || profile == null) {
      throw StateError('Account is locked');
    }
    return RatchetMessageCodec(
      sessions: LocalDatabaseSessionStorage(database),
      identity: identity,
      ownId: profile.chhayaId.publicKey,
    );
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
      }
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
                final received = await _decodePayload(message, payload);
                await database.commitReceivedMessage(state, received);
              },
            );
          } catch (_) {
            // A malformed row must not prevent later authenticated messages syncing.
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
