import 'dart:async';

import 'package:flutter/material.dart';

import 'chat_thread_page.dart';
import 'friendly_error.dart';
import 'main.dart';
import 'services/chat_service.dart';
import 'widgets/top_message.dart';

/// The Chats inbox — every 1:1 conversation the signed-in user is part of.
///
/// A thread only ever appears for its two participants (enforced by RLS, see
/// `supabase/migrations/20260724000000_user_chat.sql`), so a buyer's chat with
/// a seller is invisible to every other user.
///
/// The pencil button in the header switches the list into select mode, where
/// chats can be deleted. Deleting only hides the thread on *this* user's
/// screen — see [ChatService.deleteForMe].
class ChatsPage extends StatefulWidget {
  /// True for the Archived view — the same screen, reading the archive
  /// instead of the inbox.
  final bool archived;

  const ChatsPage({super.key, this.archived = false});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  static const Color _brand = Color(0xFF6DBF99);
  static const Color _brandDark = Color(0xFF3AA876);

  final _searchController = TextEditingController();

  List<ChatConversation> _conversations = [];

  /// How many threads sit in the archive, so the inbox can offer a way in.
  int _archivedCount = 0;
  bool _loading = true;
  bool _failed = false;
  String _query = '';

  /// Select mode (the pencil button) and the rows ticked inside it.
  bool _selecting = false;
  final Set<String> _selected = {};

  /// Realtime nudge: any change to one of the user's threads re-runs the
  /// list query, so a new message re-orders the inbox as it lands.
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    try {
      _sub = ChatService.conversationStream().listen(
        (_) => _load(silent: true),
        onError: (e) => debugPrint('Chat list stream error: $e'),
      );
    } catch (e) {
      debugPrint('Chat list stream failed: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final rows = await ChatService.fetchConversations(
        archived: widget.archived,
      );
      // Only the inbox needs the archive's size, for its entry row.
      final archivedCount = widget.archived
          ? 0
          : (await ChatService.fetchConversations(archived: true)).length;
      if (!mounted) return;
      setState(() {
        _conversations = rows;
        _archivedCount = archivedCount;
        // Drop ticks for threads that are no longer in the list.
        _selected.removeWhere((id) => !rows.any((c) => c.id == id));
        _loading = false;
        _failed = false;
      });
    } catch (e) {
      debugPrint('Failed to load conversations: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  List<ChatConversation> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _conversations;
    return _conversations
        .where(
          (c) =>
              c.otherName.toLowerCase().contains(q) ||
              c.lastMessage.toLowerCase().contains(q),
        )
        .toList();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _openThread(ChatConversation c) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatThreadPage(
          conversationId: c.id,
          otherUserId: c.otherId,
          otherName: c.otherName,
          otherAvatar: c.otherAvatar,
        ),
      ),
    ).then((_) => _load(silent: true));
  }

  void _toggleSelectMode() {
    setState(() {
      _selecting = !_selecting;
      _selected.clear();
    });
  }

  /// Confirms, then hides the ticked threads from this user's screen only.
  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final n = _selected.length;
    final ok = await _confirmDelete(
      n == 1 ? 'Delete this chat?' : 'Delete $n chats?',
    );
    if (ok != true) return;

    final ids = _selected.toList();
    try {
      for (final id in ids) {
        await ChatService.deleteForMe(id);
      }
      if (!mounted) return;
      setState(() {
        _conversations.removeWhere((c) => ids.contains(c.id));
        _selected.clear();
        _selecting = false;
      });
      showTopMessage(
        context,
        n == 1 ? 'Chat deleted' : '$n chats deleted',
        isError: false,
      );
    } catch (e) {
      debugPrint('Delete chats failed: $e');
      if (!mounted) return;
      showTopMessage(
        context,
        friendlyError(
          e,
          action: 'delete_chats',
          fallback: 'Could not delete that chat. Please try again.',
        ),
      );
    }
  }

  Future<void> _deleteOne(ChatConversation c) async {
    final ok = await _confirmDelete('Delete this chat?');
    if (ok != true) return;
    try {
      await ChatService.deleteForMe(c.id);
      if (!mounted) return;
      setState(() => _conversations.removeWhere((x) => x.id == c.id));
      showTopMessage(context, 'Chat deleted', isError: false);
    } catch (e) {
      debugPrint('Delete chat failed: $e');
      if (!mounted) return;
      showTopMessage(
        context,
        friendlyError(
          e,
          action: 'delete_chat',
          fallback: 'Could not delete that chat. Please try again.',
        ),
      );
    }
  }

  Future<bool?> _confirmDelete(String title) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'It will be removed from your Chats only. The other person keeps '
          'the conversation on their side.',
          style: TextStyle(fontSize: 13.5, height: 1.5, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.black54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Color(0xFFE53935),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRowActions(ChatConversation c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline, color: _brandDark),
              title: Text('Open chat with ${c.otherName}'),
              onTap: () {
                Navigator.pop(ctx);
                _openThread(c);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Color(0xFFE53935),
              ),
              title: const Text('Delete chat'),
              subtitle: const Text(
                'Removes it from your screen only',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteOne(c);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final signedIn = supabase.auth.currentUser != null;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearch(),
            if (!widget.archived && _archivedCount > 0) _buildArchiveEntry(),
            const SizedBox(height: 4),
            Expanded(
              child: !signedIn
                  ? _note(
                      Icons.lock_outline_rounded,
                      'Please sign in to see your chats.',
                    )
                  : _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: _brand,
                        strokeWidth: 2.5,
                      ),
                    )
                  : _failed
                  ? _note(
                      Icons.cloud_off_rounded,
                      'Chats are unavailable right now.\nPull down to try again.',
                      refreshable: true,
                    )
                  : _buildList(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _selecting && _selected.isNotEmpty
          ? _buildDeleteBar()
          : null,
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          if (!_selecting)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.black87),
            ),
          if (!_selecting) const SizedBox(width: 10),
          Expanded(
            child: Text(
              _selecting
                  ? (_selected.isEmpty
                        ? 'Select chats'
                        : '${_selected.length} selected')
                  : (widget.archived ? 'Archived' : 'Chats'),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
          ),
          // Pencil = manage/delete chats. Tapping again leaves select mode.
          GestureDetector(
            onTap: _toggleSelectMode,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _selecting ? _brand : const Color(0xFFEFF1F0),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _selecting ? Icons.close : Icons.edit_outlined,
                size: 20,
                color: _selecting ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            const Icon(Icons.search, color: Colors.black38, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Search messages',
                  hintStyle: TextStyle(color: Colors.black38, fontSize: 14),
                ),
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ),
            if (_query.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.black38),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Way into the archive. Hidden when nothing has been archived, so it
  /// never adds a dead row to a fresh inbox.
  Widget _buildArchiveEntry() {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatsPage(archived: true)),
      ).then((_) => _load(silent: true)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        child: Row(
          children: [
            const Icon(Icons.archive_outlined, size: 20, color: _brandDark),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Archived',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            Text(
              '$_archivedCount',
              style: const TextStyle(fontSize: 13, color: Colors.black45),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Colors.black26),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final rows = _visible;
    if (rows.isEmpty) {
      return RefreshIndicator(
        color: _brand,
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [const SizedBox(height: 80), _emptyState()],
        ),
      );
    }
    return RefreshIndicator(
      color: _brand,
      onRefresh: () => _load(silent: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        itemCount: rows.length,
        itemBuilder: (_, i) => _buildRow(rows[i]),
      ),
    );
  }

  Widget _buildRow(ChatConversation c) {
    final ticked = _selected.contains(c.id);
    final unread = c.hasUnread;
    final preview = c.lastMessage.isEmpty
        ? 'Say hello 👋'
        : '${c.sentByMe ? 'You: ' : ''}${c.lastMessage}';

    return InkWell(
      onTap: () {
        if (_selecting) {
          setState(() => ticked ? _selected.remove(c.id) : _selected.add(c.id));
        } else {
          _openThread(c);
        }
      },
      onLongPress: _selecting ? null : () => _showRowActions(c),
      child: Container(
        color: ticked ? const Color(0xFFF1FAF6) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (_selecting) ...[
              Icon(
                ticked
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                color: ticked ? _brandDark : Colors.black26,
                size: 22,
              ),
              const SizedBox(width: 12),
            ],
            _Avatar(
              url: c.otherAvatar,
              name: c.otherName,
              seller: c.otherIsSeller,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.otherName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: unread ? Colors.black87 : Colors.black54,
                          ),
                        ),
                      ),
                      Text(
                        ' · ${_shortTime(c.lastMessageAt)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: unread ? Colors.black54 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (c.muted)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.notifications_off,
                  size: 15,
                  color: Colors.black26,
                ),
              ),
            if (!_selecting && unread)
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: _brandDark,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _deleteSelected,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(
              _selected.length == 1
                  ? 'Delete chat'
                  : 'Delete ${_selected.length} chats',
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: const BoxDecoration(
            color: Color(0xFFF4FAF7),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.forum_outlined, color: _brand, size: 40),
        ),
        const SizedBox(height: 16),
        Text(
          _query.isNotEmpty
              ? 'No chats match that search'
              : widget.archived
              ? 'Nothing archived'
              : 'No chats yet',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            _query.isNotEmpty
                ? 'Try a different name or word.'
                : widget.archived
                ? 'Archive a chat from its menu and it\nwaits for you here.'
                : 'Open a listing and tap "Message Seller" to\nstart a conversation.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              color: Colors.black45,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _note(IconData icon, String text, {bool refreshable = false}) {
    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Colors.black26),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black45,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
    if (!refreshable) return content;
    return RefreshIndicator(
      color: _brand,
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [const SizedBox(height: 120), content],
      ),
    );
  }
}

/// "6m" / "3h" / "2d" / "Sep 4" — the compact stamp on each inbox row.
String _shortTime(DateTime? at) {
  if (at == null) return '';
  final d = DateTime.now().difference(at.toLocal());
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final l = at.toLocal();
  return '${months[l.month - 1]} ${l.day}';
}

/// Round profile picture, falling back to the person's initials.
class _Avatar extends StatelessWidget {
  final String url;
  final String name;
  final bool seller;
  final double size;

  const _Avatar({
    required this.url,
    required this.name,
    this.seller = false,
    this.size = 52,
  });

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFE8F7F1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? Text(
              _initials,
              style: TextStyle(
                fontSize: size * 0.34,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3AA876),
              ),
            )
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Text(
                _initials,
                style: TextStyle(
                  fontSize: size * 0.34,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3AA876),
                ),
              ),
            ),
    );

    if (!seller) return circle;
    // Small badge marking the other person as a seller.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        circle,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              color: const Color(0xFF3AA876),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.storefront, size: 9, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

/// Reusable elsewhere (the chat thread's app bar shows the same avatar).
class ChatAvatar extends StatelessWidget {
  final String url;
  final String name;
  final double size;

  const ChatAvatar({
    super.key,
    required this.url,
    required this.name,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) =>
      _Avatar(url: url, name: name, size: size);
}
