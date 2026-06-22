import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'widgets/top_message.dart';
import 'main.dart';
import 'cloudinary_function.dart';

/// Lets scrollables (e.g. the image carousel) be dragged with a mouse/trackpad
/// on web & desktop, not just touch — Flutter disables mouse drag by default.
class _DragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class ProductDetailPage extends StatefulWidget {
  final String name;
  final String price;
  final String image;
  final List<String>? images;
  final String? description;
  final String? condition;
  final String? sellerName;
  final String? location;
  final String? breed;
  final String? age;
  final String? weight;

  /// ISO-8601 timestamp of when the listing was created (for "x days ago").
  final String? createdAt;

  /// Listing row id — required for the owner delete/disable actions.
  final String? listingId;

  /// Seller's user id — used to detect whether the viewer owns this listing.
  final String? sellerId;

  /// Listing status, e.g. 'active' or 'disabled'.
  final String? status;

  const ProductDetailPage({
    super.key,
    required this.name,
    required this.price,
    required this.image,
    this.images,
    this.description,
    this.condition,
    this.sellerName,
    this.location,
    this.breed,
    this.age,
    this.weight,
    this.createdAt,
    this.listingId,
    this.sellerId,
    this.status,
  });

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  bool _isFavorited = false;
  bool _isDescriptionExpanded = false;
  final TextEditingController _messageController = TextEditingController();
  String _messageText = 'Good afternoon,\nis this still available?';
  bool _offerSent = false;

  final PageController _imageController = PageController();
  int _currentImage = 0;

  late String _status = (widget.status?.trim().isNotEmpty ?? false)
      ? widget.status!.trim()
      : 'active';

  /// True when the current signed-in user owns this listing, so the
  /// delete/disable actions should be offered.
  bool get _isOwner {
    final id = widget.listingId?.trim() ?? '';
    final owner = widget.sellerId?.trim() ?? '';
    if (id.isEmpty || owner.isEmpty) return false;
    return supabase.auth.currentUser?.id == owner;
  }

  /// Human-friendly age of the post, e.g. "3 days ago". Falls back to
  /// "Just listed" when no timestamp is available.
  String get _postAge {
    final dt = DateTime.tryParse(widget.createdAt ?? '');
    if (dt == null) return 'Just listed';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 365) {
      final y = diff.inDays ~/ 365;
      return '$y year${y == 1 ? '' : 's'} ago';
    }
    if (diff.inDays >= 30) {
      final m = diff.inDays ~/ 30;
      return '$m month${m == 1 ? '' : 's'} ago';
    }
    if (diff.inDays >= 1) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    if (diff.inHours >= 1) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    if (diff.inMinutes >= 1) {
      return '${diff.inMinutes} min${diff.inMinutes == 1 ? '' : 's'} ago';
    }
    return 'Just now';
  }

  /// All images to show, ignoring blanks; falls back to the single [image].
  List<String> get _images {
    final list = (widget.images ?? const <String>[])
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (list.isNotEmpty) return list;
    return widget.image.trim().isNotEmpty ? [widget.image] : <String>[];
  }

  static const Map<String, Map<String, String>> _details = {
    'Chicken': {
      'breed': 'Native Broiler',
      'age': '3 months',
      'weight': '1.5 kg',
      'location': 'Tanauan, Batangas',
      'seller': 'Mang Juan',
      'sellerJoined': '2022',
      'breederSince': '2020',
      'description':
          'Healthy native broiler chicken raised in a free-range environment. Fed with organic feed. Ready for harvest. Our chickens are raised with care and attention to ensure the best quality meat. They roam freely in our farm and are given fresh water and organic feed daily.',
    },
    'White Hen': {
      'breed': 'White Leghorn',
      'age': '5 months',
      'weight': '1.8 kg',
      'location': 'Lipa City, Batangas',
      'seller': 'Aling Rosa',
      'sellerJoined': '2023',
      'breederSince': '2021',
      'description':
          'Pure white Leghorn hen, good layer and meat source. Vaccinated and well-cared for. These hens are known for their high egg production and quality meat. They have been raised in a clean environment with proper nutrition and veterinary care.',
    },
    'Duck': {
      'breed': 'Pateros Duck',
      'age': '4 months',
      'weight': '1.2 kg',
      'location': 'Pateros, Metro Manila',
      'seller': 'Mang Pedro',
      'sellerJoined': '2021',
      'breederSince': '2018',
      'description':
          'Pateros duck raised near clean water sources. Great for balut and itlog na maalat production. Our ducks follow the traditional Pateros method of raising, ensuring authentic flavor and quality. They are healthy, active, and ready for purchase.',
    },
    'Turkey': {
      'breed': 'Bronze Turkey',
      'age': '8 months',
      'weight': '5.0 kg',
      'location': 'Sto. Tomas, Batangas',
      'seller': 'Kuya Ben',
      'sellerJoined': '2024',
      'breederSince': '2024',
      'description':
          'Large bronze turkey perfect for special occasions and fiestas. Naturally raised with no artificial growth hormones. This turkey has been carefully nurtured over 8 months and is now at peak condition. Ideal for large family gatherings and celebrations.',
    },
  };

  @override
  void dispose() {
    _messageController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  // Prefer values passed from the listing; fall back to the sample _details map.
  String get _sellerName {
    final s = widget.sellerName?.trim() ?? '';
    if (s.isNotEmpty) return s;
    return _details[widget.name]?['seller'] ?? 'Unknown';
  }

  String get _location {
    final l = widget.location?.trim() ?? '';
    if (l.isNotEmpty) return l;
    return _details[widget.name]?['location'] ?? 'Unknown';
  }

  String get _condition {
    final c = widget.condition?.trim() ?? '';
    if (c.isNotEmpty) return c;
    return 'Good';
  }

  String get _description {
    final d = widget.description?.trim() ?? '';
    if (d.isNotEmpty) return d;
    return _details[widget.name]?['description'] ?? 'No description available.';
  }

  String get _breed {
    final b = widget.breed?.trim() ?? '';
    if (b.isNotEmpty) return b;
    return _details[widget.name]?['breed'] ?? 'Unknown';
  }

  String get _age {
    final a = widget.age?.trim() ?? '';
    if (a.isNotEmpty) return a;
    return _details[widget.name]?['age'] ?? 'Unknown';
  }

  String get _weight {
    final w = widget.weight?.trim() ?? '';
    if (w.isNotEmpty) return w;
    return _details[widget.name]?['weight'] ?? 'Unknown';
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Owner-only actions ─────────────────────────────────────
            if (_isOwner) ...[
              _buildSheetOption(
                _status == 'active' ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                _status == 'active' ? 'Disable Listing' : 'Enable Listing',
                Colors.orange,
                () {
                  Navigator.pop(context);
                  _toggleDisableListing();
                },
              ),
              _buildSheetOption(Icons.delete_outline, 'Delete Listing', Colors.red, () {
                Navigator.pop(context);
                _confirmDeleteListing();
              }),
              const Divider(height: 8),
            ],
            _buildSheetOption(Icons.report_outlined, 'Report Listing', Colors.red, () {
              Navigator.pop(context);
              _showSnackBar('Report submitted. We\'ll review this listing.');
            }),
            _buildSheetOption(Icons.gavel_outlined, 'Report Seller', Colors.red, () {
              Navigator.pop(context);
              _showReportSellerDialog();
            }),
            _buildSheetOption(Icons.block_outlined, 'Block Seller', Colors.black87, () {
              Navigator.pop(context);
              _showSnackBar('Seller has been blocked.');
            }),
            _buildSheetOption(Icons.copy_outlined, 'Copy Link', Colors.black87, () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(
                text: 'https://farm.app/listing/${widget.name.toLowerCase().replaceAll(' ', '-')}',
              ));
              _showSnackBar('Link copied to clipboard!');
            }),
            _buildSheetOption(Icons.flag_outlined, 'Mark as Sold', Colors.orange, () {
              Navigator.pop(context);
              _showSnackBar('Listing marked as sold.');
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetOption(IconData icon, String label, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }

  /// Toggles the listing between 'active' and 'disabled'. A disabled listing
  /// is hidden from the public browse pages (which filter on status='active').
  Future<void> _toggleDisableListing() async {
    final id = widget.listingId;
    if (id == null) return;
    final newStatus = _status == 'active' ? 'disabled' : 'active';
    try {
      await supabase.from('listings').update({'status': newStatus}).eq('id', id);
      if (!mounted) return;
      setState(() => _status = newStatus);
      _showSnackBar(newStatus == 'disabled'
          ? 'Listing disabled. Buyers can no longer see it.'
          : 'Listing enabled. It\'s visible to buyers again.');
    } catch (e) {
      if (mounted) _showSnackBar('Could not update listing. Please try again.');
    }
  }

  void _confirmDeleteListing() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Listing', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'This will permanently remove this listing. This action cannot be undone.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteListing();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteListing() async {
    final id = widget.listingId;
    if (id == null) return;
    try {
      // Best-effort cleanup of the hosted images before removing the row, so
      // they don't linger in Cloudinary as orphans. Must run before the row is
      // deleted — the function reads the row to verify ownership.
      await deleteListingImages(id);

      await supabase.from('listings').delete().eq('id', id);
      if (!mounted) return;
      _showSnackBar('Listing deleted.');
      // Return a result so the previous page can refresh its list.
      Navigator.of(context).pop('deleted');
    } catch (e) {
      if (mounted) _showSnackBar('Could not delete listing. Please try again.');
    }
  }

  void _showReportSellerDialog() {
    final TextEditingController reportController = TextEditingController();
    String selectedReason = 'Fraud';
    final List<String> reasons = ['Fraud', 'Inaccurate Listings', 'Poor Communication', 'Other'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Report Seller', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Why are you reporting this seller?', style: TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 12),
              DropdownButton<String>(
                value: selectedReason,
                isExpanded: true,
                items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (val) => setLocalState(() => selectedReason = val!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reportController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Additional details...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(context);
                _showSnackBar('Seller report submitted for "$selectedReason".');
              },
              child: const Text('Submit Report', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage() {
    if (_messageText.trim().isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ChatPage(
          sellerName: _sellerName,
          productName: widget.name,
          initialMessage: _messageText,
        ),
      ),
    );
  }

  void _showMakeOfferDialog() {
    final TextEditingController offerController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Make an Offer', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Listed price: ${widget.price}',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: offerController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixText: '₱ ',
                hintText: 'Enter your offer',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF6DBF99)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6DBF99),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(context);
              if (offerController.text.isNotEmpty) {
                setState(() => _offerSent = true);
                _showSnackBar('Offer of ₱${offerController.text} sent to seller!');
              }
            },
            child: const Text('Send Offer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _shareProduct() {
    final shareText =
        '🐔 Check out this listing!\n\n'
        '${widget.name} — ${widget.price}\n'
        'Location: $_location\n'
        'Seller: $_sellerName\n\n'
        'https://farm.app/listing/${widget.name.toLowerCase().replaceAll(' ', '-')}';

    // Copy to clipboard as a simple share fallback
    Clipboard.setData(ClipboardData(text: shareText));
    _showSnackBar('Listing info copied! You can now paste it to share.');
  }

  void _toggleFavorite() {
    setState(() => _isFavorited = !_isFavorited);
    _showSnackBar(_isFavorited ? 'Added to favorites!' : 'Removed from favorites.');
  }

  void _visitSeller() {
    final info = _details[widget.name] ?? {};
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _SellerProfilePage(
          sellerName: _sellerName,
          sellerJoined: info['sellerJoined'] ?? '2024',
          breederSince: info['breederSince'],
          location: _location,
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    showTopMessage(
      context,
      message,
      isError: false,
      backgroundColor: const Color(0xFF3A3A3A),
      icon: Icons.info_outline,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _details[widget.name] ?? {
      'breed': 'Unknown',
      'age': 'Unknown',
      'weight': 'Unknown',
      'location': 'Unknown',
      'seller': 'Unknown',
      'sellerJoined': 'Joined in 2024',
      'description': 'No description available.',
    };

    final fullDescription = _description;
    final shortDescription = fullDescription.length > 100
        ? '${fullDescription.substring(0, 100)}...'
        : fullDescription;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top Bar ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close, color: Colors.black87, size: 26),
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                    ),
                    GestureDetector(
                      onTap: _showMoreOptions,
                      child: const Icon(Icons.more_horiz, color: Colors.black87, size: 24),
                    ),
                  ],
                ),
              ),

              // ── Product Image(s) — swipeable ─────────────────────
              SizedBox(
                width: double.infinity,
                height: 280,
                child: _images.isEmpty
                    ? _imageFallback()
                    : ScrollConfiguration(
                        behavior: _DragScrollBehavior(),
                        child: PageView.builder(
                          controller: _imageController,
                          itemCount: _images.length,
                          onPageChanged: (i) => setState(() => _currentImage = i),
                          itemBuilder: (context, index) => _carouselImage(_images[index]),
                        ),
                      ),
              ),

              const SizedBox(height: 10),

              // ── Dots indicator ───────────────────────────────────
              if (_images.length > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_images.length, (i) {
                    final active = i == _currentImage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF6DBF99) : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),

              const SizedBox(height: 16),

              // ── Name + Price ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    Text(widget.price,
                      style: const TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(_postAge,
                          style: const TextStyle(fontSize: 12, color: Colors.black45),
                        ),
                        if (_status != 'active') ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Disabled',
                              style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Message Seller Box ───────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28, height: 28,
                            decoration: const BoxDecoration(color: Color(0xFF6DBF99), shape: BoxShape.circle),
                            child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 16),
                          ),
                          const SizedBox(width: 8),
                          const Text('Message Seller',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                // Show editable message dialog
                                _messageController.text = _messageText;
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Text('Edit Message'),
                                    content: TextField(
                                      controller: _messageController,
                                      maxLines: 3,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(color: Color(0xFF6DBF99)),
                                        ),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF6DBF99),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        onPressed: () {
                                          setState(() => _messageText = _messageController.text);
                                          Navigator.pop(context);
                                        },
                                        child: const Text('Save', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Text(
                                  _messageText,
                                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _sendMessage,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6DBF99),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text('Send',
                                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Action Buttons ───────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(
                      icon: _offerSent ? Icons.pan_tool : Icons.pan_tool_outlined,
                      color: _offerSent ? const Color(0xFF6DBF99) : null,
                      onTap: _showMakeOfferDialog,
                      tooltip: 'Make Offer',
                    ),
                    _buildActionButton(
                      icon: Icons.share_outlined,
                      onTap: _shareProduct,
                      tooltip: 'Share',
                    ),
                    _buildActionButton(
                      icon: _isFavorited ? Icons.favorite : Icons.favorite_border,
                      color: _isFavorited ? Colors.red : null,
                      onTap: _toggleFavorite,
                      tooltip: _isFavorited ? 'Unfavorite' : 'Favorite',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Description ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Description',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        if (fullDescription.length > 100)
                          GestureDetector(
                            onTap: () => setState(() => _isDescriptionExpanded = !_isDescriptionExpanded),
                            child: Text(
                              _isDescriptionExpanded ? 'See less' : 'See more',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF6DBF99)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    AnimatedCrossFade(
                      firstChild: Text(
                        shortDescription,
                        style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.5),
                      ),
                      secondChild: Text(
                        fullDescription,
                        style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.5),
                      ),
                      crossFadeState: _isDescriptionExpanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 200),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Seller Info ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Seller',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: const BoxDecoration(color: Color(0xFFD6F0E4), shape: BoxShape.circle),
                          child: const Icon(Icons.person, color: Color(0xFF6DBF99), size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_sellerName,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
                              ),
                              Row(
                                children: [
                                  Icon(Icons.verified, color: Colors.blue, size: 12),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(color: Color(0xFFFFB300), borderRadius: BorderRadius.circular(4)),
                                    child: const Text('Trusted Seller', 
                                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              Text('Member since ${info['sellerJoined']}',
                                style: const TextStyle(fontSize: 11, color: Colors.black45),
                              ),
                              if (info.containsKey('breederSince'))
                                Text('Breeder since ${info['breederSince']}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF6DBF99), fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: _visitSeller,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6DBF99),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Visit',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Details ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Details',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(Icons.pets_outlined,           'Breed',     _breed),
                    const SizedBox(height: 6),
                    _buildDetailRow(Icons.cake_outlined,           'Age',       _age),
                    const SizedBox(height: 6),
                    _buildDetailRow(Icons.monitor_weight_outlined, 'Weight',    _weight),
                    const SizedBox(height: 6),
                    _buildDetailRow(Icons.location_on_outlined,    'Location',  _location,
                        valueColor: const Color(0xFF6DBF99)),
                    const SizedBox(height: 6),
                    _buildDetailRow(Icons.check_circle_outline,    'Condition', _condition),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageFallback() => Container(
        color: const Color(0xFFD6F0E4),
        child: const Icon(Icons.image_not_supported_outlined,
            color: Colors.white54, size: 60),
      );

  Widget _carouselImage(String path) {
    return path.startsWith('http')
        ? Image.network(path,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _imageFallback())
        : Image.asset(path,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _imageFallback());
  }

  Widget _buildDetailRow(IconData icon, String label, String value,
      {Color valueColor = Colors.black54}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6DBF99)),
        const SizedBox(width: 8),
        Text('$label:  ', style: const TextStyle(fontSize: 13, color: Colors.black54)),
        Expanded(
          child: Text(value,
            style: TextStyle(fontSize: 13, color: valueColor, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color ?? const Color(0xFF6DBF99),
              width: 1.5,
            ),
          ),
          child: Icon(icon, color: color ?? const Color(0xFF6DBF99), size: 22),
        ),
      ),
    );
  }
}

// ── Chat Page ──────────────────────────────────────────────────────────────
class _ChatPage extends StatefulWidget {
  final String sellerName;
  final String productName;
  final String initialMessage;

  const _ChatPage({
    required this.sellerName,
    required this.productName,
    required this.initialMessage,
  });

  @override
  State<_ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<_ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _sellerReplied = false;

  @override
  void initState() {
    super.initState();
    // Add the initial message automatically
    _messages.add({'text': widget.initialMessage, 'isMine': true});
    // Simulate seller reply after delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _messages.add({
            'text': 'Hi! Yes, it\'s still available. Are you interested?',
            'isMine': false,
          });
          _sellerReplied = true;
        });
      }
    });
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;
    setState(() {
      _messages.add({'text': _controller.text, 'isMine': true});
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            Container(
              width: 34, height: 34,
              decoration: const BoxDecoration(color: Color(0xFFD6F0E4), shape: BoxShape.circle),
              child: const Icon(Icons.person, color: Color(0xFF6DBF99), size: 18),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.sellerName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
                Text(widget.productName,
                  style: const TextStyle(fontSize: 11, color: Colors.black45)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMine = msg['isMine'] as bool;
                return Align(
                  alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                    decoration: BoxDecoration(
                      color: isMine ? const Color(0xFF6DBF99) : const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      msg['text'] as String,
                      style: TextStyle(
                        fontSize: 13,
                        color: isMine ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: Color(0xFF6DBF99)),
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 44, height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFF6DBF99),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Seller Profile Page ────────────────────────────────────────────────────
class _SellerProfilePage extends StatelessWidget {
  final String sellerName;
  final String sellerJoined;
  final String? breederSince;
  final String location;

  const _SellerProfilePage({
    required this.sellerName,
    required this.sellerJoined,
    this.breederSince,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Seller Profile',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              width: 80, height: 80,
              decoration: const BoxDecoration(color: Color(0xFFD6F0E4), shape: BoxShape.circle),
              child: const Icon(Icons.person, color: Color(0xFF6DBF99), size: 44),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(sellerName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(width: 4),
                const Icon(Icons.verified, color: Colors.blue, size: 20),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB300),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Trusted Seller',
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 4),
            Text('Member since $sellerJoined',
              style: const TextStyle(fontSize: 13, color: Colors.black45)),
            if (breederSince != null) ...[
              const SizedBox(height: 2),
              Text('Breeder since $breederSince',
                style: const TextStyle(fontSize: 13, color: Color(0xFF6DBF99), fontWeight: FontWeight.w500)),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF6DBF99)),
                const SizedBox(width: 4),
                Text(location,
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStat('Listings', '12'),
                _buildStat('Rating', '4.8 ⭐'),
                _buildStat('Sales', '47'),
                _buildStat('Trust', '98%'),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_outlined, color: Color(0xFF6DBF99), size: 18),
                  SizedBox(width: 8),
                  Text('Verified Seller',
                    style: TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6DBF99),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Message Seller',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black45)),
      ],
    );
  }
}
