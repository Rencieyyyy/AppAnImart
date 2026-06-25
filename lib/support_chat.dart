import 'package:flutter/material.dart';

import 'main.dart';
import 'widgets/top_message.dart';

/// Live customer-support chat between the signed-in user and an admin.
///
/// Messages live in the `support_messages` table (one thread per user, keyed
/// by `user_id`). The user posts rows with `sender = 'user'`; an admin replies
/// from the admin panel with `sender = 'admin'`. Realtime keeps both sides in
/// sync — see `supabase/migrations/20260625000000_support_chat.sql`.
class SupportChatPage extends StatefulWidget {
  const SupportChatPage({super.key});

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage> {
  static const Color _brand = Color(0xFF3AA876);

  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  Stream<List<Map<String, dynamic>>>? _stream;
  String? _uid;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final uid = supabase.auth.currentUser?.id;
    _uid = uid;
    if (uid != null) {
      _stream = supabase
          .from('support_messages')
          .stream(primaryKey: ['id'])
          .eq('user_id', uid)
          .order('created_at', ascending: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending || _uid == null) return;

    setState(() => _sending = true);
    _controller.clear();
    try {
      await supabase.from('support_messages').insert({
        'user_id': _uid,
        'sender': 'user',
        'body': text,
      });
      _scrollToBottom();
    } catch (e) {
      _controller.text = text; // restore so the user doesn't lose their message
      if (mounted) {
        showTopMessage(context, 'Couldn\'t send your message. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

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
            Stack(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3AA876), Color(0xFF2E8B63)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.support_agent_rounded,
                      color: Colors.white, size: 22),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: _brand,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('AniMart Support',
                    style:
                        TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                Text('Typically replies within minutes',
                    style: TextStyle(fontSize: 11.5, color: Colors.black45)),
              ],
            ),
          ],
        ),
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
    if (_uid == null) {
      return _centeredNote(
          Icons.lock_outline_rounded, 'Please sign in to start a chat.');
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _centeredNote(Icons.cloud_off_rounded,
              'Chat is unavailable right now. Please try again later.');
        }
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: _brand, strokeWidth: 2.5));
        }
        final messages = snapshot.data!;
        if (messages.isEmpty) return _emptyState();

        _scrollToBottom();
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
          itemCount: messages.length,
          itemBuilder: (context, i) {
            final m = messages[i];
            final isUser = (m['sender'] as String?) == 'user';
            return _bubble(
              body: (m['body'] as String?) ?? '',
              time: _formatTime(m['created_at'] as String?),
              isUser: isUser,
            );
          },
        );
      },
    );
  }

  Widget _bubble(
      {required String body, required String time, required bool isUser}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              radius: 14,
              backgroundColor: Color(0xFFE8F8F1),
              child: Icon(Icons.support_agent_rounded,
                  size: 16, color: _brand),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? _brand : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser
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
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: isUser ? Colors.white : const Color(0xFF1A2E22),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 10,
                      color: isUser ? Colors.white70 : Colors.black38,
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

  Widget _emptyState() {
    return ListView(
      // ListView so the empty state still allows the keyboard to push content.
      padding: const EdgeInsets.fromLTRB(28, 60, 28, 20),
      children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F8F1),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(Icons.forum_rounded, color: _brand, size: 34),
        ),
        const SizedBox(height: 18),
        const Text(
          'Start a conversation',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A2E22)),
        ),
        const SizedBox(height: 8),
        const Text(
          'Send us a message and our support team will get back to you as soon '
          'as possible. We\'re here to help!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.black45, height: 1.5),
        ),
      ],
    );
  }

  Widget _centeredNote(IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Colors.black26),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF2F4F3),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _send(),
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  hintText: 'Type a message…',
                  hintStyle: TextStyle(color: Colors.black38, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: _brand,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _send,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.2),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
