// SQLCipher schema constants for Chhaya (V14 Part 3).
//
// Purpose: single source of truth for table and column names. All SQL
// lives in migrations/ and queries.dart — never inline elsewhere.
// Content columns holding user data are always encrypted blobs;
// index/where columns carry routing metadata only (ids, timestamps,
// flags), never message text, names, or keys.
class DbTables {
  DbTables._();

  /// Tracks applied migration versions (see migration_runner.dart).
  static const String schemaVersion = 'schema_version';

  /// Local user profiles (one row per local identity).
  static const String users = 'users';

  /// Address-book entries owned by a local user.
  static const String contacts = 'contacts';

  /// Conversation headers (participants live in [participants]).
  static const String conversations = 'conversations';

  /// Conversation membership with join/leave history.
  static const String participants = 'conversation_participants';

  /// Messages with encrypted content envelope.
  static const String messages = 'messages';

  /// Linked devices (FCM tokens always encrypted).
  static const String devices = 'devices';

  /// Cached onion circuits (paths always encrypted).
  static const String circuits = 'circuits';

  /// Key-value store for settings and small profile blobs.
  static const String kv = 'kv';
}

/// Column names per table. `_enc` suffix = AES-GCM ciphertext (base64).
class DbCols {
  DbCols._();

  // Shared
  /// Primary key.
  static const String id = 'id';

  /// Creation time, milliseconds since epoch.
  static const String createdAt = 'created_at';

  // schema_version
  /// Applied migration version.
  static const String version = 'version';

  /// Apply time, milliseconds since epoch.
  static const String appliedAt = 'applied_at';

  // users
  /// Owner-scoped Chhaya public key (hex).
  static const String chhayaId = 'chhaya_id';

  /// AES-GCM display name.
  static const String displayNameEnc = 'display_name_enc';

  /// Ed25519/X25519 public keys (public material, safe at rest).
  static const String publicKey = 'public_key';

  /// Already-encrypted private key bundle (as issued by auth layer).
  static const String encryptedPrivateKey = 'encrypted_private_key';

  // contacts
  /// Owning local user id.
  static const String userId = 'user_id';

  /// Remote contact id.
  static const String contactId = 'contact_id';

  /// AES-GCM display name.
  static const String displayNameEncContact = 'display_name_enc';

  /// AES-GCM avatar URL (nullable).
  static const String avatarEnc = 'avatar_enc';

  /// 1 = known, 2 = matched, 3 = verified.
  static const String verificationLevel = 'verification_level';

  /// 0/1 blocked flag.
  static const String isBlocked = 'is_blocked';

  /// Added time, milliseconds since epoch.
  static const String addedAt = 'added_at';

  // conversations
  /// 'direct' or 'group'.
  static const String type = 'type';

  /// AES-GCM group name (nullable).
  static const String nameEnc = 'name_enc';

  /// Raw avatar bytes (nullable, non-sensitive).
  static const String avatarBlob = 'avatar_blob';

  /// Creator user id.
  static const String createdBy = 'created_by';

  /// 0/1 pinned flag (drives ordering).
  static const String pinned = 'pinned';

  /// Last activity, milliseconds since epoch (drives ordering).
  static const String lastTs = 'last_ts';

  // participants
  /// Conversation id (FK).
  static const String conversationId = 'conversation_id';

  /// Join time, milliseconds since epoch.
  static const String joinedAt = 'joined_at';

  /// Leave time, milliseconds since epoch (nullable = active).
  static const String leftAt = 'left_at';

  /// 0/1 admin flag.
  static const String isAdmin = 'is_admin';

  // messages
  /// Sender user/contact id.
  static const String senderId = 'sender_id';

  /// AES-GCM message content envelope.
  static const String encryptedContent = 'encrypted_content';

  /// MessageType name (text/image/file/voice/system/poll).
  static const String contentType = 'content_type';

  /// Raw media bytes (nullable).
  static const String mediaBlob = 'media_blob';

  /// AES-GCM media metadata JSON (nullable).
  static const String mediaMetaEnc = 'media_meta_enc';

  /// Replied-to message id (nullable).
  static const String replyToId = 'reply_to_id';

  /// Send time, milliseconds since epoch.
  static const String sentAt = 'sent_at';

  /// Delivery time, milliseconds since epoch (nullable).
  static const String deliveredAt = 'delivered_at';

  /// Read time, milliseconds since epoch (nullable).
  static const String readAt = 'read_at';

  // devices
  /// Human-readable device label.
  static const String deviceName = 'device_name';

  /// 'android' | 'ios' | 'windows' | ...
  static const String platform = 'platform';

  /// AES-GCM FCM/APNs token. NEVER plaintext.
  static const String fcmTokenEncrypted = 'fcm_token_encrypted';

  /// 0/1 linked flag.
  static const String isLinked = 'is_linked';

  /// Last activity, milliseconds since epoch.
  static const String lastActiveAt = 'last_active_at';

  // circuits
  /// AES-GCM serialized circuit path.
  static const String pathEnc = 'path_enc';

  /// Expiry time, milliseconds since epoch.
  static const String expiresAt = 'expires_at';

  // kv
  /// Setting key.
  static const String key = 'key';

  /// AES-GCM setting value.
  static const String value = 'value';
}

/// Index names. Indices cover routing metadata only — never encrypted
/// content, names, tokens, or keys.
class DbIndices {
  DbIndices._();

  /// Message lookup by conversation, time-ordered.
  static const String messagesByConversation = 'idx_messages_convo';

  /// Membership lookup by user.
  static const String participantsByUser = 'idx_participants_user';

  /// Conversation list ordering.
  static const String conversationsOrder = 'idx_conversations_order';

  /// Contact lookup by owner.
  static const String contactsByUser = 'idx_contacts_user';

  /// Device lookup by owner.
  static const String devicesByUser = 'idx_devices_user';
}
