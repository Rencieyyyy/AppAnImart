import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../main.dart';

/// One row of the Chats list: a thread plus the other person's profile bits
/// and how many of their messages the signed-in user hasn't read yet.
class ChatConversation {
  final String id;
  final String otherId;
  final String otherName;
  final String otherAvatar;
  final bool otherIsSeller;

  /// The listing this pair last messaged about, if the chat started from one
  /// — powers "View Listing" in the thread menu. Empty when there is none.
  final String listingId;

  /// Muted threads stay out of the unread badge on the Chats icon.
  final bool muted;

  /// Preview of the newest message ('Photo' for a picture-only message).
  final String lastMessage;

  /// Who sent [lastMessage] — used for the "You: …" prefix.
  final String lastSenderId;
  final DateTime? lastMessageAt;
  final int unreadCount;

  const ChatConversation({
    required this.id,
    required this.otherId,
    required this.otherName,
    this.otherAvatar = '',
    this.otherIsSeller = false,
    this.listingId = '',
    this.muted = false,
    this.lastMessage = '',
    this.lastSenderId = '',
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  bool get sentByMe => lastSenderId == supabase.auth.currentUser?.id;
  bool get hasUnread => unreadCount > 0;

  factory ChatConversation.fromRow(Map<String, dynamic> row) {
    return ChatConversation(
      id: (row['id'] ?? '').toString(),
      otherId: (row['other_id'] ?? '').toString(),
      otherName: ((row['other_name'] as String?) ?? '').trim().isEmpty
          ? 'AniMart User'
          : (row['other_name'] as String).trim(),
      otherAvatar: ((row['other_avatar'] as String?) ?? '').trim(),
      otherIsSeller: row['other_is_seller'] == true,
      listingId: ((row['listing_id'] as String?) ?? '').trim(),
      muted: row['muted'] == true,
      lastMessage: ((row['last_message'] as String?) ?? '').trim(),
      lastSenderId: (row['last_sender_id'] ?? '').toString(),
      lastMessageAt: DateTime.tryParse('${row['last_message_at'] ?? ''}'),
      unreadCount: (row['unread_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One user's own view of a thread — every field is per-user, so muting or
/// archiving never touches what the other participant sees.
class ChatThreadState {
  /// Listing the thread is about; empty when it didn't start from one.
  final String listingId;

  /// When this user last cleared the thread; messages older than this are
  /// hidden from them. Null means never cleared.
  final DateTime? clearedAt;

  final bool muted;
  final bool archived;

  const ChatThreadState({
    this.listingId = '',
    this.clearedAt,
    this.muted = false,
    this.archived = false,
  });

  ChatThreadState copyWith({bool? muted, bool? archived}) => ChatThreadState(
    listingId: listingId,
    clearedAt: clearedAt,
    muted: muted ?? this.muted,
    archived: archived ?? this.archived,
  );
}

/// User-to-user chat: opening threads, listing them, reading them live and
/// hiding one from your own screen.
///
/// Everything here is scoped to the signed-in user by Row Level Security and
/// by the `security definer` helpers in
/// `supabase/migrations/20260724000000_user_chat.sql` — a thread is only ever
/// visible to its two participants.
class ChatService {
  ChatService._();

  /// Private Storage bucket for chat pictures. Objects live at
  /// `<conversation_id>/<uid>/<ms>.<ext>` and render via signed URLs.
  static const String imageBucket = 'user-chat';

  /// Max picture size the bucket accepts (5 MB), checked client-side too so
  /// the user gets a clear message instead of a storage error.
  static const int maxImageBytes = 5 * 1024 * 1024;

  static const Map<String, String> imageContentTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  /// Signed URLs cached per object path, so the realtime stream's rebuilds
  /// don't re-sign (and re-download) every picture.
  static final Map<String, Future<String?>> _signedUrls = {};

  /// Opens the thread with [otherUserId], creating it on first contact, and
  /// returns its id. Throws if either side has blocked the other.
  ///
  /// Pass [listingId] when the chat is opened from a listing — the thread
  /// remembers it so "View Listing" in the thread menu has a target.
  static Future<String> startConversation(
    String otherUserId, {
    String? listingId,
  }) async {
    final id = await supabase.rpc(
      'start_conversation',
      params: {
        'other_user': otherUserId,
        if (listingId != null && listingId.isNotEmpty) 'listing': listingId,
      },
    );
    return '$id';
  }

  /// Every thread the signed-in user can still see, newest first. Threads
  /// they cleared stay out until the other person writes again.
  ///
  /// [archived] flips it to the archive: threads they filed away that have
  /// had no new message since.
  static Future<List<ChatConversation>> fetchConversations({
    bool archived = false,
  }) async {
    final rows = await supabase.rpc(
      'my_conversations',
      params: {'archived_only': archived},
    );
    return (rows as List)
        .map((r) => ChatConversation.fromRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Total unread messages across every thread — the badge on the Chats icon.
  static Future<int> unreadCount() async {
    try {
      final n = await supabase.rpc('my_unread_chat_count');
      return (n as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('Unread chat count failed: $e');
      return 0;
    }
  }

  /// Live feed of a thread's messages.
  ///
  /// Realtime can't express the per-user "cleared" watermark, so the stream
  /// carries every message and the caller drops the ones sent before
  /// [clearedAt] (see [clearedAt] below) — matching what
  /// `conversation_messages()` returns on the server.
  static Stream<List<Map<String, dynamic>>> messageStream(
    String conversationId,
  ) {
    return supabase
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);
  }

  /// Fires whenever any of the signed-in user's threads changes (a new
  /// message updates its preview), so the Chats list can refresh itself.
  static Stream<List<Map<String, dynamic>>> conversationStream() {
    return supabase.from('conversations').stream(primaryKey: ['id']);
  }

  /// This user's own side of a thread: their clear watermark, whether they
  /// muted or archived it, and the listing it's about. Everything here is
  /// per-user — the other participant has their own independent state.
  static Future<ChatThreadState> fetchState(String conversationId) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return const ChatThreadState();
    try {
      final row = await supabase
          .from('conversations')
          .select(
            'user_a, listing_id, a_cleared_at, b_cleared_at, '
            'a_muted, b_muted, a_archived_at, b_archived_at',
          )
          .eq('id', conversationId)
          .maybeSingle();
      if (row == null) return const ChatThreadState();
      final isA = row['user_a'] == uid;
      return ChatThreadState(
        listingId: ((row['listing_id'] as String?) ?? '').trim(),
        clearedAt: DateTime.tryParse(
          '${(isA ? row['a_cleared_at'] : row['b_cleared_at']) ?? ''}',
        ),
        muted: (isA ? row['a_muted'] : row['b_muted']) == true,
        archived: (isA ? row['a_archived_at'] : row['b_archived_at']) != null,
      );
    } catch (e) {
      debugPrint('Failed to read chat thread state: $e');
      return const ChatThreadState();
    }
  }

  /// Sends a text message (and/or a picture already uploaded at [imagePath]).
  static Future<void> sendMessage(
    String conversationId, {
    String body = '',
    String? imagePath,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    await supabase.from('chat_messages').insert({
      'conversation_id': conversationId,
      'sender_id': uid,
      'body': body.trim(),
      if (imagePath != null && imagePath.isNotEmpty) 'image_url': imagePath,
    });
  }

  /// Uploads a chat picture and returns its storage object path.
  static Future<String> uploadImage(
    String conversationId,
    Uint8List bytes, {
    required String ext,
    required String contentType,
  }) async {
    final uid = supabase.auth.currentUser!.id;
    final path =
        '$conversationId/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await supabase.storage
        .from(imageBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    return path;
  }

  /// Raw bytes of a chat picture, straight from the private bucket.
  ///
  /// Used by the image viewer's save button. Going through Storage (rather
  /// than re-fetching the signed URL over HTTP) keeps the download on the
  /// authenticated client, so it can't 404 on an expired signature.
  static Future<Uint8List> downloadImage(String path) {
    return supabase.storage.from(imageBucket).download(path);
  }

  /// Signed URL for a chat picture, cached per path (the bucket is private).
  static Future<String?> signedUrl(String path) {
    return _signedUrls.putIfAbsent(path, () async {
      try {
        return await supabase.storage
            .from(imageBucket)
            .createSignedUrl(path, 3600);
      } catch (e) {
        debugPrint('Chat image sign failed: $e');
        return null;
      }
    });
  }

  /// Clears the unread badge for this thread.
  static Future<void> markRead(String conversationId) async {
    try {
      await supabase.rpc(
        'mark_conversation_read',
        params: {'conv': conversationId},
      );
    } catch (e) {
      debugPrint('Mark conversation read failed: $e');
    }
  }

  /// Deletes a thread **from the caller's screen only**.
  ///
  /// The other participant keeps the conversation and every message in it —
  /// nothing is removed from their side. For the caller the thread disappears
  /// from their Chats list and its history stops being readable; if the other
  /// person sends something new, the thread returns carrying only what
  /// arrived after this point.
  static Future<void> deleteForMe(String conversationId) async {
    await supabase.rpc('clear_conversation', params: {'conv': conversationId});
  }

  /// Mutes or unmutes a thread for the signed-in user only. A muted thread
  /// stops counting toward the badge on the Chats icon.
  static Future<void> setMuted(String conversationId, bool muted) async {
    await supabase.rpc(
      'set_conversation_muted',
      params: {'conv': conversationId, 'muted': muted},
    );
  }

  /// Files a thread into (or out of) this user's archive. It leaves their
  /// inbox but stays readable under Chats → Archived, and returns on its own
  /// the moment the other person sends something new.
  static Future<void> setArchived(String conversationId, bool archived) async {
    await supabase.rpc(
      'set_conversation_archived',
      params: {'conv': conversationId, 'archived': archived},
    );
  }
}
