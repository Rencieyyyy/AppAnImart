import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dashboard.dart';
import 'buyer.dart';
import 'profile.dart';
import 'main.dart';

class AnnouncementPage extends StatefulWidget {
  const AnnouncementPage({super.key});

  @override
  State<AnnouncementPage> createState() => _AnnouncementPageState();
}

class _AnnouncementPageState extends State<AnnouncementPage> {
  int _selectedIndex = 2;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterType = 'All'; // 'All', 'General', 'Urgent', 'Event', 'Promo'

  static const List<String> _typeFilters = ['All', 'General', 'Urgent', 'Event', 'Promo'];

  // Icon shown on each filter tab.
  static const Map<String, IconData> _typeIcons = {
    'All': Icons.grid_view_rounded,
    'General': Icons.info_outline,
    'Urgent': Icons.warning_amber_rounded,
    'Event': Icons.calendar_today_outlined,
    'Promo': Icons.local_offer_outlined,
  };

  // Icon per tag category (keyed lowercase).
  static const Map<String, IconData> _tagIcons = {
    'general': Icons.info_outline,
    'urgent': Icons.warning_amber_rounded,
    'event': Icons.calendar_today_outlined,
    'promo': Icons.local_offer_outlined,
  };

  // Colors per tag category: [background, border, foreground].
  static const Map<String, List<Color>> _tagColors = {
    'general': [Color(0xFFE8F8F1), Color(0xFFC2EDD9), Color(0xFF27803F)],
    'urgent': [Color(0xFFFDECEC), Color(0xFFF5C2C2), Color(0xFFE53E3E)],
    'event': [Color(0xFFE7F0FB), Color(0xFFC3DBF5), Color(0xFF2563EB)],
    'promo': [Color(0xFFFEF3E2), Color(0xFFFDE08D), Color(0xFFB45309)],
  };

  bool _loading = true;
  String? _loadError;
  final List<Map<String, dynamic>> _announcements = [];

  static const List<Color> _avatarColors = [
    Color(0xFF5CC898),
    Color(0xFFD85A30),
    Color(0xFF378ADD),
    Color(0xFF9B59B6),
    Color(0xFFE0A526),
  ];

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rows = await supabase
          .from('announcements')
          .select('*, announcement_tags(tag)')
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);

      final mapped = <Map<String, dynamic>>[];
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i] as Map<String, dynamic>;
        // Drafts are not shown to mobile users.
        if (((r['status'] as String?) ?? '').toLowerCase() == 'draft') continue;
        // Tags come from the announcement_tags join table.
        final tagRows = (r['announcement_tags'] as List?) ?? const [];
        final tags = tagRows
            .map((t) => (t as Map<String, dynamic>)['tag'] as String?)
            .whereType<String>()
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList();
        mapped.add({
          'id': r['id'],
          'admin': 'Admin',
          'time': _timeAgo(r['created_at'] as String?),
          'status': _prettyStatus(r['status'] as String?),
          'type': (r['type'] as String?) ?? '',
          'title': (r['title'] as String?) ?? '',
          'body': (r['body'] as String?) ?? '',
          'image': (r['image_url'] as String?) ?? '',
          'tags': tags,
          'likes': (r['likes_count'] as int?) ?? 0,
          'liked': false,
          'views': (r['views_count'] as int?) ?? 0,
          'avatarColor': _avatarColors[i % _avatarColors.length],
          'comments': <Map<String, String>>[],
        });
      }

      if (!mounted) return;
      setState(() {
        _announcements
          ..clear()
          ..addAll(mapped);
        _loading = false;
      });
    } catch (e) {
      debugPrint('Failed to load announcements: $e');
      if (!mounted) return;
      setState(() {
        _loadError = e is PostgrestException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  String _prettyStatus(String? status) {
    if (status == null || status.isEmpty) return 'Active';
    return status[0].toUpperCase() + status.substring(1).toLowerCase();
  }

  String _timeAgo(String? isoDate) {
    if (isoDate == null) return '';
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()} year(s) ago';
    if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()} month(s) ago';
    if (diff.inDays >= 1) return '${diff.inDays} day(s) ago';
    if (diff.inHours >= 1) return '${diff.inHours} hour(s) ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} minute(s) ago';
    return 'Just now';
  }

  // ── Filtered list ──────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filtered {
    return _announcements.where((item) {
      final q = _searchQuery.toLowerCase();
      final matchesSearch = q.isEmpty ||
          (item['title'] as String).toLowerCase().contains(q) ||
          (item['body'] as String).toLowerCase().contains(q) ||
          (item['tags'] as List<String>).any((t) => t.toLowerCase().contains(q));
      // The announcement's category lives in its tags (announcement_tags.tag).
      final tags =
          (item['tags'] as List<String>).map((t) => t.toLowerCase()).toList();
      final selected = _filterType.toLowerCase();
      final matchesFilter = _filterType == 'All'
          ? true
          : (tags.isEmpty ? selected == 'general' : tags.contains(selected));
      return matchesSearch && matchesFilter;
    }).toList();
  }

  // ── Bottom Nav ─────────────────────────────────────────────────────────
  void _onTabTapped(int index) {
    if (index == _selectedIndex) return;
    switch (index) {
      case 0:
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const DashboardPage()),
          (route) => false,
        );
        break;
      case 1:
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const BuyerPage()),
          (route) => false,
        );
        break;
      case 2:
        break;
      case 3:
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const ProfilePage()),
          (route) => false,
        );
        break;
    }
  }

  // ── Like toggle ────────────────────────────────────────────────────────
  void _toggleLike(int originalIndex) {
    setState(() {
      final liked = _announcements[originalIndex]['liked'] as bool;
      _announcements[originalIndex]['liked'] = !liked;
      _announcements[originalIndex]['likes'] =
          (_announcements[originalIndex]['likes'] as int) + (liked ? -1 : 1);
    });
  }

  // ── See All bottom sheet ───────────────────────────────────────────────
  void _showSeeAll() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF4FAF7),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'All Announcements',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2E22),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close, color: Colors.black45, size: 22),
                    ),
                  ],
                ),
              ),
              // Filter chips inside See All
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: _typeFilters.map((f) {
                    final isSelected = _filterType == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _filterType = f);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF6DBF99)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF6DBF99)
                                  : Colors.black12,
                            ),
                          ),
                          child: Text(
                            f,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: _announcements.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _buildCard(i, compact: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Full detail bottom sheet ───────────────────────────────────────────
  void _showDetail(int originalIndex) {
    final item = _announcements[originalIndex];
    // Increment views
    setState(() {
      _announcements[originalIndex]['views'] =
          (_announcements[originalIndex]['views'] as int) + 1;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.97,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF4FAF7),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Announcement Detail',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2E22),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close,
                          color: Colors.black45, size: 22),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(height: 16, thickness: 0.5),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tags
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: (item['tags'] as List<String>)
                            .map((tag) => _tagChip(tag, fontSize: 11))
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      // Title
                      Text(
                        item['title'] as String,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A2E22),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Admin row
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: item['avatarColor'] as Color,
                            child: Text(
                              (item['admin'] as String)[0],
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(item['admin'] as String,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Color(0xFF1A2E22))),
                          const SizedBox(width: 8),
                          const Icon(Icons.access_time_rounded,
                              size: 11, color: Colors.black38),
                          const SizedBox(width: 3),
                          Text(item['time'] as String,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black38)),
                        ],
                      ),
                      if ((item['image'] as String).isNotEmpty) ...[
                        const SizedBox(height: 12),
                        // Image
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: _announcementImage(item['image'] as String, 200),
                        ),
                      ],
                      const SizedBox(height: 14),
                      // Body
                      Text(
                        item['body'] as String,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF3D5247),
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Like & views row
                      StatefulBuilder(
                        builder: (ctx2, setLocal) {
                          final liked =
                              _announcements[originalIndex]['liked'] as bool;
                          final likes =
                              _announcements[originalIndex]['likes'] as int;
                          return Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  _toggleLike(originalIndex);
                                  setLocal(() {});
                                },
                                child: Row(
                                  children: [
                                    Icon(
                                      liked
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      size: 20,
                                      color: liked
                                          ? Colors.redAccent
                                          : Colors.black38,
                                    ),
                                    const SizedBox(width: 5),
                                    Text('$likes',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.black54)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Icon(Icons.remove_red_eye_outlined,
                                  size: 18, color: Colors.black38),
                              const SizedBox(width: 5),
                              Text(
                                  '${_announcements[originalIndex]['views']}',
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.black54)),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Comments',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A2E22),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Inline comments in detail
                      _buildInlineComments(originalIndex),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineComments(int originalIndex) {
    final comments =
        _announcements[originalIndex]['comments'] as List<Map<String, String>>;
    final TextEditingController commentController = TextEditingController();

    return StatefulBuilder(
      builder: (ctx, setLocal) {
        return Column(
          children: [
            if (comments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No comments yet. Be the first!',
                    style: TextStyle(color: Colors.black38, fontSize: 13)),
              )
            else
              ...comments.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              const Color(0xFF6DBF99).withOpacity(0.2),
                          child: Text(c['user']![0],
                              style: const TextStyle(
                                  color: Color(0xFF3AA876),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF4FAF7),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFF6DBF99)
                                          .withOpacity(0.2)),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(c['user']!,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                            color: Color(0xFF1A2E22))),
                                    const SizedBox(height: 2),
                                    Text(c['text']!,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF3D5247),
                                            height: 1.4)),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 4, top: 3),
                                child: Text(c['time']!,
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.black38)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
            const SizedBox(height: 8),
            // Comment input
            Row(
              children: [
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: Color(0xFF6DBF99),
                  child: Text('R',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFF6DBF99).withOpacity(0.3)),
                    ),
                    child: TextField(
                      controller: commentController,
                      style: const TextStyle(fontSize: 13),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) {
                        final text = commentController.text.trim();
                        if (text.isEmpty) return;
                        setLocal(() {
                          comments.add({
                            'user': 'You',
                            'text': text,
                            'time': 'Just now',
                          });
                        });
                        setState(() {});
                        commentController.clear();
                      },
                      decoration: const InputDecoration(
                        hintText: 'Write a comment...',
                        hintStyle:
                            TextStyle(color: Colors.black38, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    final text = commentController.text.trim();
                    if (text.isEmpty) return;
                    setLocal(() {
                      comments.add({
                        'user': 'You',
                        'text': text,
                        'time': 'Just now',
                      });
                    });
                    setState(() {});
                    commentController.clear();
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Color(0xFF6DBF99),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // ── Comment bottom sheet (from card footer) ────────────────────────────
  void _showComments(int originalIndex) {
    final comments =
        _announcements[originalIndex]['comments'] as List<Map<String, String>>;
    final TextEditingController commentController = TextEditingController();
    final ScrollController scrollController = ScrollController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Comments (${comments.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2E22),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(Icons.close,
                              color: Colors.black45, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(height: 20, thickness: 0.5),
                  ),
                  Expanded(
                    child: comments.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.mode_comment_outlined,
                                    size: 48, color: Colors.black12),
                                SizedBox(height: 10),
                                Text(
                                  'No comments yet.\nBe the first to comment!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.black38,
                                      height: 1.5),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            itemCount: comments.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 14),
                            itemBuilder: (context, i) {
                              final c = comments[i];
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor:
                                        const Color(0xFF6DBF99).withOpacity(0.2),
                                    child: Text(
                                      c['user']![0],
                                      style: const TextStyle(
                                          color: Color(0xFF3AA876),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF4FAF7),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                              color: const Color(0xFF6DBF99)
                                                  .withOpacity(0.2),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(c['user']!,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 12,
                                                      color:
                                                          Color(0xFF1A2E22))),
                                              const SizedBox(height: 3),
                                              Text(c['text']!,
                                                  style: const TextStyle(
                                                      fontSize: 13,
                                                      color: Color(0xFF3D5247),
                                                      height: 1.4)),
                                            ],
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              left: 4, top: 4),
                                          child: Text(c['time']!,
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.black38)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                  Container(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 10,
                      bottom:
                          MediaQuery.of(context).viewInsets.bottom + 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                          top: BorderSide(
                              color: Colors.black.withOpacity(0.07))),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 18,
                          backgroundColor: Color(0xFF6DBF99),
                          child: Text('R',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 42),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4FAF7),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                  color: const Color(0xFF6DBF99)
                                      .withOpacity(0.3)),
                            ),
                            child: TextField(
                              controller: commentController,
                              style: const TextStyle(fontSize: 13),
                              maxLines: null,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _postComment(
                                  comments,
                                  commentController,
                                  setSheetState,
                                  scrollController,
                                  originalIndex),
                              decoration: const InputDecoration(
                                hintText: 'Write a comment...',
                                hintStyle: TextStyle(
                                    color: Colors.black38, fontSize: 13),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 11),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _postComment(
                              comments,
                              commentController,
                              setSheetState,
                              scrollController,
                              originalIndex),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: const BoxDecoration(
                                color: Color(0xFF6DBF99),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.send_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _postComment(
    List<Map<String, String>> comments,
    TextEditingController controller,
    StateSetter setSheetState,
    ScrollController scrollController,
    int originalIndex,
  ) {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    setSheetState(() {
      comments.add({'user': 'You', 'text': text, 'time': 'Just now'});
    });
    setState(() {});
    controller.clear();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAF7),
      body: Column(
        children: [
          // ── Green Header ─────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(
                top: 50, bottom: 20, left: 16, right: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF6DBF99),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button only (search icon removed)
                GestureDetector(
                  onTap: () {
                    if (Navigator.canPop(context)) Navigator.pop(context);
                  },
                  child: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Announcements',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Stay updated with the latest farm news',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(height: 16),
                // ── Functional Search Bar ─────────────────────────
                Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      const Icon(Icons.search,
                          color: Color(0xFF6DBF99), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) =>
                              setState(() => _searchQuery = val),
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black87),
                          decoration: const InputDecoration(
                            hintText: 'Search announcements...',
                            hintStyle:
                                TextStyle(color: Colors.black38, fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Icon(Icons.close,
                                color: Colors.black38, size: 18),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Section label + See All ───────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6DBF99),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Latest Posts',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2E22),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _showSeeAll,
                  child: const Text(
                    'See All',
                    style: TextStyle(fontSize: 12, color: Color(0xFF3AA876)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Type filter chips (scrollable) ────────────────────────
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _typeFilters.map((f) {
                final isSelected = _filterType == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filterType = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF6DBF99)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF6DBF99)
                              : Colors.black12,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _typeIcons[f] ?? Icons.label_outline,
                            size: 14,
                            color: isSelected ? Colors.white : Colors.black45,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            f,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  isSelected ? Colors.white : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 4),

          // ── Feed ──────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF6DBF99)),
                  )
                : _loadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cloud_off_rounded,
                              size: 52, color: Colors.black12),
                          const SizedBox(height: 12),
                          Text(
                            'Could not load announcements.\n$_loadError',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black38, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _loadAnnouncements,
                            child: const Text('Retry',
                                style: TextStyle(
                                    color: Color(0xFF3AA876),
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  )
                : filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_off_rounded,
                            size: 52, color: Colors.black12),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No results for "$_searchQuery"'
                              : 'No announcements found.',
                          style: const TextStyle(
                              color: Colors.black38, fontSize: 14),
                        ),
                        if (_filterType != 'All') ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _filterType = 'All'),
                            child: const Text(
                              'Clear filter',
                              style: TextStyle(
                                  color: Color(0xFF3AA876),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      // Find original index for state mutations
                      final item = filtered[index];
                      final originalIndex = _announcements.indexOf(item);
                      return _buildCard(originalIndex);
                    },
                  ),
          ),
        ],
      ),

      // ── Bottom Nav ────────────────────────────────────────────────
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        selectedItemColor: const Color(0xFF6DBF99),
        unselectedItemColor: Colors.black45,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.shopping_cart_outlined),
              activeIcon: Icon(Icons.shopping_cart),
              label: 'Explore'),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications_outlined),
              activeIcon: Icon(Icons.notifications),
              label: 'Announcements'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }

  /// A tag chip colored + iconed by its category (General/Urgent/Event/Promo).
  /// Unknown tags (e.g. content tags) fall back to a neutral style.
  Widget _tagChip(String tag, {double fontSize = 10}) {
    final key = tag.trim().toLowerCase();
    final colors = _tagColors[key] ??
        const [Color(0xFFEFF3F1), Color(0xFFDDE7E2), Color(0xFF6B8578)];
    final icon = _tagIcons[key];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors[0],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors[1]),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 1, color: colors[2]),
            const SizedBox(width: 4),
          ],
          Text(
            tag,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: colors[2],
            ),
          ),
        ],
      ),
    );
  }

  /// Renders an announcement image from a network URL (Supabase) or a bundled
  /// asset path, with a graceful placeholder on error/while loading.
  Widget _announcementImage(String src, double height) {
    Widget placeholder() => Container(
          width: double.infinity,
          height: height,
          color: const Color(0xFFE8F8F1),
          child: const Icon(Icons.image_not_supported_outlined,
              color: Colors.white54, size: 40),
        );

    if (src.startsWith('http')) {
      return Image.network(
        src,
        width: double.infinity,
        height: height,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: double.infinity,
            height: height,
            color: const Color(0xFFE8F8F1),
            child: const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF6DBF99)),
            ),
          );
        },
        errorBuilder: (_, __, ___) => placeholder(),
      );
    }
    return Image.asset(
      src,
      width: double.infinity,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder(),
    );
  }

  Widget _buildCard(int originalIndex, {bool compact = false}) {
    final item = _announcements[originalIndex];
    final bool isActive = item['status'] == 'Active';
    final comments = item['comments'] as List<Map<String, String>>;
    final bool liked = item['liked'] as bool;

    return GestureDetector(
      onTap: () => _showDetail(originalIndex),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: const Color(0xFF6DBF99).withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: item['avatarColor'] as Color,
                            child: Text(
                              (item['admin'] as String)[0],
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['admin'] as String,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Color(0xFF1A2E22))),
                              Row(
                                children: [
                                  const Icon(Icons.access_time_rounded,
                                      size: 11, color: Colors.black38),
                                  const SizedBox(width: 3),
                                  Text(item['time'] as String,
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.black38)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFFE8F8F1)
                              : const Color(0xFFFEF3E2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isActive
                                ? const Color(0xFFC2EDD9)
                                : const Color(0xFFFDE08D),
                          ),
                        ),
                        child: Text(
                          item['status'] as String,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isActive
                                ? const Color(0xFF27803F)
                                : const Color(0xFFB45309),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if ((item['tags'] as List<String>).isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: (item['tags'] as List<String>)
                          .map((tag) => _tagChip(tag))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(item['title'] as String,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A2E22))),
                  const SizedBox(height: 4),
                  Text(
                    item['body'] as String,
                    maxLines: compact ? 2 : null,
                    overflow:
                        compact ? TextOverflow.ellipsis : TextOverflow.visible,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B8578),
                        height: 1.5),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            if ((item['image'] as String).isNotEmpty)
              ClipRRect(
                child: _announcementImage(item['image'] as String, 150),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Comment button
                  GestureDetector(
                    onTap: () {
                      // Stop card tap from firing
                      _showComments(originalIndex);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        const Icon(Icons.mode_comment_outlined,
                            size: 15, color: Color(0xFF3AA876)),
                        const SizedBox(width: 5),
                        Text(
                          comments.isEmpty
                              ? 'Comment'
                              : 'View Comments (${comments.length})',
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF3AA876),
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  // Like & views
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _toggleLike(originalIndex),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Icon(
                              liked ? Icons.favorite : Icons.favorite_border,
                              size: 14,
                              color: liked ? Colors.redAccent : Colors.black38,
                            ),
                            const SizedBox(width: 3),
                            Text('${item['likes']}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.black38)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.remove_red_eye_outlined,
                          size: 14, color: Colors.black38),
                      const SizedBox(width: 3),
                      Text('${item['views']}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black38)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}