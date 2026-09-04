import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';

import 'chats_page.dart' show ChatAvatar;
import 'friendly_error.dart';
import 'main.dart';
import 'product_detail.dart' show ProductDetailPage, SellerProfilePage;
import 'services/chat_service.dart';
import 'services/marketplace_service.dart';
import 'widgets/top_message.dart';

/// A live 1:1 conversation between the signed-in user and one other user.
///
/// Open it either with a known [conversationId] (from the Chats list) or with
/// just an [otherUserId] — in that case the thread is created on the fly by
/// `start_conversation()`, so "Message Seller" works on first contact.
///
/// Only the two participants can read this thread; Row Level Security keeps
/// every other user out (see
/// `supabase/migrations/20260724000000_user_chat.sql`).
class ChatThreadPage extends StatefulWidget {
  final String? conversationId;
  final String otherUserId;
  final String otherName;
  final String otherAvatar;

  /// Listing this chat is about, when opened from one. Recorded on the
  /// thread so the ⋯ menu can offer "View Listing" on later visits too.
  final String? listingId;

  const ChatThreadPage({
    super.key,
    this.conversationId,
    required this.otherUserId,
    required this.otherName,
    this.otherAvatar = '',
    this.listingId,
  });

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  static const Color _brand = Color(0xFF3AA876);

  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  String? _conversationId;
  String? _uid;

  /// This user's own side of the thread: clear watermark, mute/archive flags
  /// and the listing it's about. None of it is visible to the other person.
  ChatThreadState _state = const ChatThreadState();

  /// True once the other user is blocked, so the composer can lock.
  bool _blocked = false;

  Stream<List<Map<String, dynamic>>>? _stream;
  bool _opening = true;
  String _openError = '';
  bool _sending = false;

  /// Guards against re-stamping the read watermark on every rebuild.
  int _lastMarkedCount = -1;

  @override
  void initState() {
    super.initState();
    _uid = supabase.auth.currentUser?.id;
    _open();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Resolves (or creates) the thread, then wires up the realtime stream.
  Future<void> _open() async {
    if (_uid == null) {
      setState(() {
        _opening = false;
        _openError = 'Please sign in to send messages.';
      });
      return;
    }
    try {
      final id =
          widget.conversationId ??
          await ChatService.startConversation(
            widget.otherUserId,
            listingId: widget.listingId,
          );
      final results = await Future.wait([
        ChatService.fetchState(id),
        MarketplaceService.isBlocked(widget.otherUserId),
      ]);
      if (!mounted) return;
      setState(() {
        _conversationId = id;
        _state = results[0] as ChatThreadState;
        _blocked = results[1] as bool;
        _stream = ChatService.messageStream(id);
        _opening = false;
      });
      ChatService.markRead(id);
    } catch (e) {
      debugPrint('Failed to open conversation: $e');
      if (!mounted) return;
      setState(() {
        _opening = false;
        _openError = friendlyError(
          e,
          action: 'open_conversation',
          fallback: 'Could not open this chat. Please try again.',
        );
      });
    }
  }

  /// Messages this user is allowed to see — everything after their own
  /// "delete on my screen" watermark.
  List<Map<String, dynamic>> _visible(List<Map<String, dynamic>> rows) {
    final cleared = _state.clearedAt;
    if (cleared == null) return rows;
    return rows.where((m) {
      final at = DateTime.tryParse('${m['created_at'] ?? ''}');
      return at != null && at.isAfter(cleared);
    }).toList();
  }

  // ── Sending ────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _controller.text.trim();
    final cid = _conversationId;
    if (text.isEmpty || _sending || cid == null) return;

    setState(() => _sending = true);
    _controller.clear();
    try {
      await ChatService.sendMessage(cid, body: text);
      _scrollToBottom();
    } catch (e) {
      debugPrint('Send chat message failed: $e');
      _controller.text = text; // don't lose what they typed
      if (mounted) {
        showTopMessage(
          context,
          friendlyError(
            e,
            action: 'send_chat_message',
            fallback: 'Could not send your message. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage(ImageSource source) async {
    final cid = _conversationId;
    if (_sending || cid == null) return;

    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
    } catch (e) {
      debugPrint('Chat image pick failed: $e');
      if (mounted) {
        showTopMessage(
          context,
          friendlyError(
            e,
            action: 'pick_chat_image',
            fallback: 'Could not open that photo. Please try another one.',
          ),
        );
      }
      return;
    }
    if (picked == null || !mounted) return; // cancelled

    final Uint8List bytes = await picked.readAsBytes();
    if (!mounted) return;
    if (bytes.length > ChatService.maxImageBytes) {
      showTopMessage(context, 'Image is too large — max 5 MB.');
      return;
    }
    final dot = picked.name.lastIndexOf('.');
    final ext = dot < 0 ? '' : picked.name.substring(dot + 1).toLowerCase();
    final contentType = ChatService.imageContentTypes[ext];
    if (contentType == null) {
      showTopMessage(context, 'Please pick a JPG, PNG or WebP image.');
      return;
    }

    final caption = _controller.text.trim();
    setState(() => _sending = true);
    try {
      final path = await ChatService.uploadImage(
        cid,
        bytes,
        ext: ext,
        contentType: contentType,
      );
      await ChatService.sendMessage(cid, body: caption, imagePath: path);
      _controller.clear();
      _scrollToBottom();
    } catch (e) {
      debugPrint('Chat image send failed: $e');
      if (mounted) {
        showTopMessage(
          context,
          friendlyError(
            e,
            action: 'send_chat_image',
            fallback: 'Could not send the picture. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showAttachSheet() {
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
              leading: const Icon(Icons.photo_library_outlined, color: _brand),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _sendImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: _brand),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _sendImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── The ⋯ menu ─────────────────────────────────────────────────────────────

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    final color = danger ? const Color(0xFFE53935) : const Color(0xFF1A2E22);
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 14, color: color)),
        ],
      ),
    );
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'profile':
        _viewSellerProfile();
      case 'listing':
        _viewListing();
      case 'mute':
        _toggleMute();
      case 'archive':
        _toggleArchive();
      case 'clear':
        _clearChat();
      case 'block':
        _blockAndReport();
    }
  }

  /// Opens the other person's public profile — reputation, shop details,
  /// contact options and their listings.
  void _viewSellerProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SellerProfilePage(
          sellerId: widget.otherUserId,
          sellerName: widget.otherName,
        ),
      ),
    );
  }

  /// Opens the listing this chat is about. The row is fetched fresh so price,
  /// stock and status are current rather than whatever they were when the
  /// conversation started.
  Future<void> _viewListing() async {
    final id = _state.listingId;
    if (id.isEmpty) return;
    try {
      final row = await supabase
          .from('listings')
          .select('*, seller:public_profiles(name)')
          .eq('id', id)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        showTopMessage(context, 'That listing is no longer available.');
        return;
      }
      final images = ((row['image_urls'] as List?) ?? const [])
          .map((e) => '$e')
          .where((e) => e.isNotEmpty)
          .toList();
      final price = row['price'];
      final cover = '${row['image_url'] ?? ''}';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailPage(
            name: '${row['title'] ?? ''}',
            price: price == null ? '' : '₱$price',
            image: cover.isNotEmpty
                ? cover
                : (images.isNotEmpty ? images.first : ''),
            images: images,
            description: '${row['description'] ?? ''}',
            condition: '${row['condition'] ?? ''}',
            sellerName:
                '${(row['seller'] as Map?)?['name'] ?? widget.otherName}',
            location: '${row['location'] ?? ''}',
            breed: '${row['breed'] ?? ''}',
            age: '${row['age'] ?? ''}',
            weight: '${row['weight'] ?? ''}',
            createdAt: '${row['created_at'] ?? ''}',
            listingId: '${row['id']}',
            sellerId: '${row['seller_id'] ?? widget.otherUserId}',
            status: '${row['status'] ?? 'active'}',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Open listing from chat failed: $e');
      if (!mounted) return;
      showTopMessage(
        context,
        friendlyError(
          e,
          action: 'open_chat_listing',
          fallback: 'Could not open that listing. Please try again.',
        ),
      );
    }
  }

  /// Mutes/unmutes this thread for the signed-in user only — a muted thread
  /// stops counting toward the badge on the Chats icon.
  Future<void> _toggleMute() async {
    final cid = _conversationId;
    if (cid == null) return;
    final next = !_state.muted;
    setState(() => _state = _state.copyWith(muted: next));
    try {
      await ChatService.setMuted(cid, next);
      if (!mounted) return;
      showTopMessage(
        context,
        next
            ? "Muted. This chat won't light up your Chats icon."
            : "Unmuted. It counts toward your unread badge again.",
        isError: false,
      );
    } catch (e) {
      debugPrint('Mute chat failed: $e');
      if (!mounted) return;
      setState(() => _state = _state.copyWith(muted: !next));
      showTopMessage(
        context,
        friendlyError(
          e,
          action: 'mute_chat',
          fallback: 'Could not change that setting. Please try again.',
        ),
      );
    }
  }

  /// Files the thread into (or out of) this user's archive, then closes the
  /// page so they land back on the list they came from.
  Future<void> _toggleArchive() async {
    final cid = _conversationId;
    if (cid == null) return;
    final next = !_state.archived;
    try {
      await ChatService.setArchived(cid, next);
      if (!mounted) return;
      setState(() => _state = _state.copyWith(archived: next));
      showTopMessage(
        context,
        next
            ? 'Archived. Find it under Chats → Archived.'
            : 'Moved back to your Chats.',
        isError: false,
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Archive chat failed: $e');
      if (!mounted) return;
      showTopMessage(
        context,
        friendlyError(
          e,
          action: 'archive_chat',
          fallback: 'Could not archive that chat. Please try again.',
        ),
      );
    }
  }

  /// Wipes the conversation from THIS user's screen. The other person keeps
  /// every message — see `clear_conversation` in the chat migration.
  Future<void> _clearChat() async {
    final cid = _conversationId;
    if (cid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Clear this chat?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'The messages disappear from your side only. ${widget.otherName} '
          'keeps the whole conversation on theirs.',
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: Colors.black54,
          ),
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
              'Clear',
              style: TextStyle(
                color: Color(0xFFE53935),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ChatService.deleteForMe(cid);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Clear chat failed: $e');
      if (!mounted) return;
      showTopMessage(
        context,
        friendlyError(
          e,
          action: 'clear_chat',
          fallback: 'Could not clear that chat. Please try again.',
        ),
      );
    }
  }

  /// Blocks (or unblocks) the other person, offering to file a report at the
  /// same time. Blocking stops messages in both directions — the insert
  /// policy on `chat_messages` refuses a blocked pair — and hides a blocked
  /// seller's listings from the feeds.
  Future<void> _blockAndReport() async {
    if (supabase.auth.currentUser == null) {
      showTopMessage(context, 'Please log in first.');
      return;
    }

    if (_blocked) {
      final stillBlocked = await MarketplaceService.toggleBlock(
        widget.otherUserId,
        currentlyBlocked: true,
      );
      if (!mounted) return;
      setState(() => _blocked = stillBlocked);
      showTopMessage(
        context,
        stillBlocked
            ? 'Could not unblock them. Please try again.'
            : 'Unblocked. You can message each other again.',
        isError: stillBlocked,
      );
      return;
    }

    const reasons = [
      'Fraud / scam',
      'Harassment or abuse',
      'Spam',
      'Misleading listings',
      'Other',
    ];
    String reason = reasons.first;
    bool alsoReport = true;
    bool working = false;
    final detailsCtrl = TextEditingController();

    final blocked = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Block ${widget.otherName}?',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Neither of you will be able to message the other, and '
                  'their listings are hidden from your feeds. You can unblock '
                  'them later from this same menu.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  value: alsoReport,
                  onChanged: working
                      ? null
                      : (v) => setLocal(() => alsoReport = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: _brand,
                  dense: true,
                  title: const Text(
                    'Also report them to AniMart',
                    style: TextStyle(fontSize: 13.5),
                  ),
                ),
                if (alsoReport) ...[
                  DropdownButton<String>(
                    value: reason,
                    isExpanded: true,
                    items: reasons
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: working
                        ? null
                        : (v) => setLocal(() => reason = v ?? reason),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: detailsCtrl,
                    maxLines: 3,
                    enabled: !working,
                    decoration: InputDecoration(
                      hintText: 'Additional details (optional)…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: working ? null : () => Navigator.pop(ctx, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.black54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
              ),
              onPressed: working
                  ? null
                  : () async {
                      setLocal(() => working = true);
                      // Report first: once blocked, the report still needs to
                      // reach the team either way, and a failure here should
                      // not stop the block itself.
                      if (alsoReport) {
                        final error = await MarketplaceService.submitReport(
                          targetType: 'seller',
                          sellerId: widget.otherUserId,
                          reason: reason,
                          details: detailsCtrl.text,
                        );
                        if (error != null) debugPrint('Chat report: $error');
                      }
                      final nowBlocked = await MarketplaceService.toggleBlock(
                        widget.otherUserId,
                        currentlyBlocked: false,
                      );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx, nowBlocked);
                    },
              child: const Text('Block'),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (blocked == true) {
      setState(() => _blocked = true);
      showTopMessage(
        context,
        'Blocked. Thanks for letting us know.',
        isError: false,
      );
      Navigator.pop(context);
    } else if (blocked == false) {
      // Cancelled, or the block write failed — resync from the server so the
      // menu label matches reality.
      final stillBlocked = await MarketplaceService.isBlocked(
        widget.otherUserId,
      );
      if (mounted) setState(() => _blocked = stillBlocked);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String _formatTime(String? iso) {
    final dt = DateTime.tryParse(iso ?? '')?.toLocal();
    if (dt == null) return '';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: const Color(0xFF1A2E22),
        titleSpacing: 0,
        title: Row(
          children: [
            ChatAvatar(
              url: widget.otherAvatar,
              name: widget.otherName,
              size: 38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.otherName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: Colors.black54),
            position: PopupMenuPosition.under,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: _onMenuSelected,
            itemBuilder: (_) => [
              _menuItem('profile', Icons.person_outline, 'View Seller Profile'),
              if (_state.listingId.isNotEmpty)
                _menuItem('listing', Icons.sell_outlined, 'View Listing'),
              _menuItem(
                'mute',
                _state.muted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                _state.muted ? 'Unmute notifications' : 'Mute notifications',
              ),
              _menuItem(
                'archive',
                _state.archived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                _state.archived ? 'Unarchive chat' : 'Archive chat',
              ),
              _menuItem(
                'clear',
                Icons.delete_outline,
                'Clear chat',
                danger: true,
              ),
              _menuItem(
                'block',
                Icons.flag_outlined,
                _blocked ? 'Unblock and Report' : 'Block and Report',
                danger: true,
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_opening) {
      return const Center(
        child: CircularProgressIndicator(color: _brand, strokeWidth: 2.5),
      );
    }
    if (_openError.isNotEmpty) {
      return _centeredNote(Icons.cloud_off_rounded, _openError);
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _centeredNote(
            Icons.cloud_off_rounded,
            'Chat is unavailable right now. Please try again later.',
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _brand, strokeWidth: 2.5),
          );
        }
        final messages = _visible(snapshot.data!);
        if (messages.isEmpty) return _emptyState();

        // Anything new that just arrived counts as read while the thread is
        // on screen.
        if (messages.length != _lastMarkedCount) {
          _lastMarkedCount = messages.length;
          final cid = _conversationId;
          if (cid != null) ChatService.markRead(cid);
        }
        _scrollToBottom();

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
          itemCount: messages.length,
          itemBuilder: (context, i) {
            final m = messages[i];
            final mine = (m['sender_id'] ?? '').toString() == _uid;
            return _bubble(
              body: (m['body'] as String?) ?? '',
              imagePath: ((m['image_url'] as String?) ?? '').trim(),
              time: _formatTime(m['created_at'] as String?),
              mine: mine,
            );
          },
        );
      },
    );
  }

  Widget _bubble({
    required String body,
    String imagePath = '',
    required String time,
    required bool mine,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            ChatAvatar(
              url: widget.otherAvatar,
              name: widget.otherName,
              size: 28,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: mine ? _brand : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
                border: mine
                    ? null
                    : Border.all(color: Colors.black.withOpacity(0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (imagePath.isNotEmpty) ...[
                    _bubbleImage(imagePath),
                    if (body.trim().isNotEmpty) const SizedBox(height: 8),
                  ],
                  if (body.trim().isNotEmpty)
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: mine ? Colors.white : const Color(0xFF1A2E22),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: mine ? Colors.white70 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubbleImage(String path) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: FutureBuilder<String?>(
        future: ChatService.signedUrl(path),
        builder: (_, snap) {
          final url = snap.data;
          if (url == null) {
            return Container(
              width: 180,
              height: 140,
              color: Colors.black12,
              alignment: Alignment.center,
              child: snap.connectionState == ConnectionState.done
                  ? const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.black26,
                    )
                  : const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
            );
          }
          return GestureDetector(
            onTap: () => _openFullImage(url, path),
            child: Image.network(
              url,
              width: 200,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 180,
                height: 140,
                color: Colors.black12,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.black26,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Full-screen viewer with pinch-zoom and a save-to-device button.
  void _openFullImage(String url, String storagePath) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ChatImageViewer(url: url, storagePath: storagePath),
      ),
    );
  }

  Widget _buildComposer() {
    // A blocked pair can't post either way (the insert policy on
    // chat_messages refuses it), so say so instead of failing on send.
    if (_blocked) {
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFECEFEE))),
          ),
          child: Row(
            children: [
              const Icon(Icons.block, size: 18, color: Colors.black38),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You blocked ${widget.otherName}. Unblock them from the '
                  'menu to message again.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final disabled = _conversationId == null;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFECEFEE))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: disabled || _sending ? null : _showAttachSheet,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              color: _brand,
            ),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F4F3),
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _controller,
                  enabled: !disabled,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Type a message…',
                    hintStyle: TextStyle(color: Colors.black38, fontSize: 14),
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: disabled || _sending ? null : _send,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: disabled || _sending ? Colors.black12 : _brand,
                  shape: BoxShape.circle,
                ),
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChatAvatar(url: widget.otherAvatar, name: widget.otherName, size: 72),
          const SizedBox(height: 14),
          Text(
            widget.otherName,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Say hello and ask about the listing. Only you two can see this '
              'conversation.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.black45,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _centeredNote(IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
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
      ),
    );
  }
}

/// Full-screen view of a chat picture: pinch/drag to zoom, and a download
/// button that saves the original file into the device's gallery.
///
/// The bytes come from the private `user-chat` bucket through the
/// authenticated Storage client, not from the on-screen signed URL, so a save
/// can't fail on an expired signature.
class _ChatImageViewer extends StatefulWidget {
  /// Signed URL used purely for display.
  final String url;

  /// Object path in the bucket — what the download actually fetches.
  final String storagePath;

  const _ChatImageViewer({required this.url, required this.storagePath});

  @override
  State<_ChatImageViewer> createState() => _ChatImageViewerState();
}

class _ChatImageViewerState extends State<_ChatImageViewer> {
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // Android 10+ writes through MediaStore and needs no permission; iOS
      // asks for add-only photo access the first time.
      if (!await Gal.hasAccess()) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          if (mounted) {
            showTopMessage(
              context,
              'Allow photo access to save pictures to your device.',
            );
          }
          return;
        }
      }
      final bytes = await ChatService.downloadImage(widget.storagePath);
      await Gal.putImageBytes(
        bytes,
        name: 'animart_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (mounted) {
        showTopMessage(context, 'Saved to your gallery', isError: false);
      }
    } on GalException catch (e) {
      debugPrint('Save chat image failed: ${e.type}');
      if (!mounted) return;
      showTopMessage(context, switch (e.type) {
        GalExceptionType.accessDenied =>
          'Allow photo access in Settings to save pictures.',
        GalExceptionType.notEnoughSpace =>
          'Not enough space on your device to save this picture.',
        GalExceptionType.notSupportedFormat =>
          "That picture's format can't be saved to the gallery.",
        GalExceptionType.unexpected =>
          'Could not save the picture. Please try again.',
      });
    } catch (e) {
      debugPrint('Save chat image failed: $e');
      if (!mounted) return;
      showTopMessage(
        context,
        friendlyError(
          e,
          action: 'save_chat_image',
          fallback: 'Could not save the picture. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // Scaffold lays its body out with loose constraints, so a bare Stack
      // would shrink to its tallest unpositioned child (the toolbar row) and
      // squash the picture into a strip across the top. Expanding pins the
      // stack to the whole screen, which is what Positioned.fill measures.
      body: SizedBox.expand(
        child: Stack(
          children: [
            // Tapping the backdrop closes; the image itself stays interactive.
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.maybePop(context),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Image.network(
                    widget.url,
                    // Tight, full-screen sizing: without it the image lays
                    // out at its intrinsic pixel size and BoxFit.contain has
                    // no room to scale a small picture up.
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white24,
                        size: 64,
                      ),
                    ),
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _circleButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.maybePop(context),
                      ),
                      _saving
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : _circleButton(
                              icon: Icons.download_rounded,
                              onTap: _save,
                              tooltip: 'Save to device',
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final button = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
