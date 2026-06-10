import 'package:flutter/material.dart';
import 'dashboard.dart';
import 'buyer.dart';
import 'profile.dart';

class AnnouncementPage extends StatefulWidget {
  const AnnouncementPage({super.key});

  @override
  State<AnnouncementPage> createState() => _AnnouncementPageState();
}

class _AnnouncementPageState extends State<AnnouncementPage> {
  int _selectedIndex = 2;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterStatus = 'All'; // 'All', 'Active', 'Pending'

  final List<Map<String, dynamic>> _announcements = [
    {
      'admin': 'Admin',
      'time': '15 days ago',
      'status': 'Active',
      'title': 'Test Announcement',
      'body':
          'Good morning! Please take note of the latest updates regarding our turkey livestock availability this season.',
      'image': 'images/turkey.png',
      'tags': ['Poultry', 'Turkey'],
      'likes': 12,
      'liked': false,
      'views': 84,
      'avatarColor': const Color(0xFF5CC898),
      'comments': <Map<String, String>>[
        {'user': 'Juan dela Cruz', 'text': 'Where can I buy?', 'time': '2 days ago'},
        {'user': 'Maria Santos', 'text': 'How much per kilo?', 'time': '1 day ago'},
      ],
    },
    {
      'admin': 'Admin',
      'time': '15 days ago',
      'status': 'Active',
      'title': 'New Stock Available',
      'body':
          'Good morning! We have a fresh batch of healthy goats ready for sale. Contact us for pricing and delivery.',
      'image': 'images/whitehen.png',
      'tags': ['Livestock', 'Goat'],
      'likes': 7,
      'liked': false,
      'views': 51,
      'avatarColor': const Color(0xFFD85A30),
      'comments': <Map<String, String>>[
        {'user': 'Pedro Reyes', 'text': 'Interested! How many heads available?', 'time': '3 days ago'},
      ],
    },
    {
      'admin': 'Admin',
      'time': '20 days ago',
      'status': 'Pending',
      'title': 'Duck Farm Update',
      'body':
          'Our duck farm is expanding! Pekin and Muscovy ducks will be available by next week. Reserve yours now.',
      'image': 'images/duck.png',
      'tags': ['Aquatics', 'Duck'],
      'likes': 3,
      'liked': false,
      'views': 29,
      'avatarColor': const Color(0xFF378ADD),
      'comments': <Map<String, String>>[],
    },
  ];

  // ── Filtered list ──────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filtered {
    return _announcements.where((item) {
      final q = _searchQuery.toLowerCase();
      final matchesSearch = q.isEmpty ||
          (item['title'] as String).toLowerCase().contains(q) ||
          (item['body'] as String).toLowerCase().contains(q) ||
          (item['tags'] as List<String>).any((t) => t.toLowerCase().contains(q));
      final matchesFilter =
          _filterStatus == 'All' || item['status'] == _filterStatus;
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
                  children: ['All', 'Active', 'Pending'].map((f) {
                    final isSelected = _filterStatus == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _filterStatus = f);
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
                        children: (item['tags'] as List<String>).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F8F1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: const Color(0xFFC2EDD9)),
                            ),
                            child: Text(tag,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF27803F))),
                          );
                        }).toList(),
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
                      const SizedBox(height: 12),
                      // Image
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          item['image'] as String,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: double.infinity,
                            height: 200,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F8F1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                                Icons.image_not_supported_outlined,
                                color: Colors.white54,
                                size: 40),
                          ),
                        ),
                      ),
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

          // ── Filter chips ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                // Section label
                Expanded(
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
                    ],
                  ),
                ),
                // Filter chips
                ...['All', 'Active', 'Pending'].map((f) {
                  final isSelected = _filterStatus == f;
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _filterStatus = f),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
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
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(width: 8),
                // See All
                GestureDetector(
                  onTap: _showSeeAll,
                  child: const Text(
                    'See All',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFF3AA876)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // ── Feed ──────────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
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
                        if (_filterStatus != 'All') ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _filterStatus = 'All'),
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
                  Wrap(
                    spacing: 6,
                    children: (item['tags'] as List<String>).map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F8F1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFC2EDD9)),
                        ),
                        child: Text(tag,
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF27803F))),
                      );
                    }).toList(),
                  ),
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
            ClipRRect(
              child: Image.asset(
                item['image'] as String,
                width: double.infinity,
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: double.infinity,
                  height: 150,
                  color: const Color(0xFFE8F8F1),
                  child: const Icon(Icons.image_not_supported_outlined,
                      color: Colors.white54, size: 40),
                ),
              ),
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