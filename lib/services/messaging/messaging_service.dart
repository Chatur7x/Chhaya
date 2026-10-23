import 'dart:async';
import 'package:uuid/uuid.dart';
import '../../core/crypto/key_manager.dart';
import '../../core/crypto/ratchet/session_store.dart';
import '../../core/database/local_database.dart';
import '../../core/models/contact.dart';
import '../../core/models/conversation.dart';
import '../../core/models/message.dart';
import '../api/api_service.dart';
import 'ratchet_message_codec.dart';

class MessagingService {
  final ApiService api;
  final LocalDatabase database;
  final KeyManager keys;
  Future<void> _tail=Future<void>.value();
  MessagingService({required this.api,required this.database,required this.keys});

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next=_tail.then((_)=>operation());
    _tail=next.then<void>((_) {},onError:(Object error,StackTrace stack) {});
    return next;
  }

  Future<RatchetMessageCodec> _codec() async {
    final identity=await keys.getKeyPair();
    final profile=await database.getUserProfile();
    if(identity==null||profile==null) { throw StateError('Account is locked'); }
    return RatchetMessageCodec(sessions:LocalDatabaseSessionStorage(database),
        identity:identity,ownId:profile.chhayaId.publicKey);
  }

  Future<Message> send(Conversation conversation,String text,{Duration? ttl}) => _serial(() async {
    if(!api.isAuthenticated) { throw StateError('Connect your server in Settings first'); }
    if(conversation.isGroup||conversation.participants.length!=1) { throw StateError('Encrypted group messaging is not available yet'); }
    final peer=await database.getContact(conversation.participants.single.id) ?? conversation.participants.single;
    final message=Message(id:const Uuid().v4(),conversationId:conversation.id,
        senderId:'me',content:text,timestamp:DateTime.now(),isSent:false,ttl:ttl);
    final envelope=await (await _codec()).encrypt(peer,conversation.id,message.id,api.userId!,
        {'content':text,'ttlMs':ttl?.inMilliseconds},
        commit:(state,envelope)=>database.commitOutgoingMessage(state,message,envelope));
    return _deliver(message,envelope);
  });

  Future<Message> _deliver(Message message,String envelope) async {
    await api.sendMessage(conversationId:message.conversationId,content:envelope,messageId:message.id);
    final sent=message.copyWith(isSent:true);
    await database.commitMessageSent(sent);
    return sent;
  }

  Future<void> retryPending(String conversationId) => _serial(() async {
    for(final message in await database.getMessages(conversationId)) {
      if(message.senderId!='me'||message.isSent) { continue; }
      final envelope=await database.loadSessionBlob('outbox:${message.id}');
      if(envelope!=null) { await _deliver(message,envelope); }
    }
  });

  Future<List<Conversation>> sync() => _serial(() async {
    if(!api.isAuthenticated) { return database.getAllConversations(); }
    final contacts=await database.getAllContacts();
    final remote=await api.getConversations();
    final result=<Conversation>[];
    for(final conversation in remote) {
      final peers=<Contact>[];
      for(final peer in conversation.participants) {
        final old=contacts.where((c)=>c.id==peer.id&&c.chhayaId==peer.chhayaId).firstOrNull;
        final contact=old??peer;
        await database.addContact(contact);
        peers.add(contact);
      }
      var updated=conversation.copyWith(participants:peers);
      await database.addConversation(updated);
      final local=await database.getMessages(conversation.id);
      final known=local.map((m)=>m.id).toSet();
      if(!conversation.isGroup&&peers.length==1&&peers.single.isVerified) {
        final batches=<Message>[];
        String? before;
        for(var page=0;page<50;page++) {
          final batch=await api.getMessages(conversation.id,limit:200,before:before);
          batches.insertAll(0,batch);
          if(batch.length<200||batch.any((m)=>known.contains(m.id))) { break; }
          before=batch.first.timestamp.toIso8601String();
        }
        final codec=await _codec();
        for(final message in batches) {
          if(message.senderId==api.userId) {
            final saved=local.where((m)=>m.id==message.id).firstOrNull;
            if(saved!=null) { await database.addMessage(saved.copyWith(isRead:message.isRead,isDelivered:message.isDelivered)); }
            continue;
          }
          if(known.contains(message.id)) { continue; }
          await codec.decrypt(peers.single,conversation.id,message.id,message.senderId,message.content,
            commit:(state,payload) async {
              final received=message.copyWith(content:payload['content'] as String,
                  ttl:payload['ttlMs']==null?null:Duration(milliseconds:payload['ttlMs'] as int));
              await database.commitReceivedMessage(state,received);
            });
        }
      }
      final messages=(await database.getMessages(conversation.id)).where((m)=>!m.isExpired).toList();
      if(messages.isNotEmpty) { updated=updated.copyWith(lastMessage:messages.last); }
      await database.addConversation(updated);
      result.add(updated);
    }
    return result;
  });
}
