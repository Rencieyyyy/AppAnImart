import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/top_message.dart';
import 'main.dart';
import 'cloudinary_function.dart';
import 'services/marketplace_service.dart';
import 'seller_reviews.dart';
import 'supabase_config.dart';

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
  bool _isBlocked = false;
  SellerRating _sellerRating = SellerRating.empty;

  /// Offers buyers have made on this listing — only loaded for the owner.
  List<Offer> _listingOffers = const [];

  /// Owner-side: this listing's deals keyed by offer id.
  Map<String, TransactionInfo> _txByOffer = {};

  /// Buyer-side: the viewer's live (reserved) deals on this listing. A buyer
  /// may hold more than one at once while the listing still has stock.
  List<TransactionInfo> _myReservations = [];
  bool _isDescriptionExpanded = false;
  bool _offerSent = false;

  /// Seller's Facebook Messenger link — the "Message Seller on Messenger"
  /// button opens it; '' when the seller hasn't set one.
  String _sellerMessengerLink = '';

  final PageController _imageController = PageController();
  int _currentImage = 0;

  late String _status = (widget.status?.trim().isNotEmpty ?? false)
      ? widget.status!.trim()
      : 'active';

  /// The listing's total stock. Fetched by id (so every entry point shows it
  /// without having to pass it in); null = unknown/not set. This is the raw
  /// number the seller set — buyers are shown [_available] instead.
  int? _stock;

  /// Units currently reserved in active deals (from other buyers too). Fetched
  /// server-side via the `listing_stock` RPC so no buyer identities leak.
  int _reservedQty = 0;

  /// What a buyer can actually still buy: total stock minus reserved units,
  /// floored at 0. null when stock is unknown.
  int? get _available {
    final s = _stock;
    if (s == null) return null;
    final a = s - _reservedQty;
    return a < 0 ? 0 : a;
  }

  /// The listing's numeric asking price, fetched with the stock — drives the
  /// one-tap "Buy at asking price" offer. null = unknown.
  double? _askingPrice;

  /// Owner edits override the values passed in via the constructor, so the
  /// page reflects a save immediately without re-fetching.
  String? _editTitle, _editPrice, _editDesc, _editBreed, _editAge,
      _editWeight, _editCondition;

  /// Whether the owner saved any edits — reported back on pop so list pages
  /// can refresh.
  bool _edited = false;

  String get _title => _editTitle ?? widget.name;
  String get _priceText => _editPrice ?? widget.price;

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
  void initState() {
    super.initState();
    _loadMarketplaceState();
  }

  /// Loads whether this listing is favourited, the seller's rating, and
  /// whether the viewer has blocked this seller.
  Future<void> _loadMarketplaceState() async {
    final listingId = widget.listingId?.trim() ?? '';
    final sellerId = widget.sellerId?.trim() ?? '';
    final results = await Future.wait([
      listingId.isEmpty
          ? Future.value(false)
          : MarketplaceService.isFavorited(listingId),
      sellerId.isEmpty
          ? Future.value(SellerRating.empty)
          : MarketplaceService.fetchSellerRating(sellerId),
      sellerId.isEmpty
          ? Future.value(false)
          : MarketplaceService.isBlocked(sellerId),
    ]);
    if (!mounted) return;
    setState(() {
      _isFavorited = results[0] as bool;
      _sellerRating = results[1] as SellerRating;
      _isBlocked = results[2] as bool;
    });
    _loadStock(listingId);
    _loadListingOffers(listingId);
    _loadSellerMessengerLink(sellerId);
    _loadTransactions(listingId);
  }

  /// Loads this listing's deal state for the viewer: as the owner, deals
  /// keyed by offer (for Complete/Cancel on the offer rows); as a buyer,
  /// whether the listing is reserved for THEM (drives the banner).
  Future<void> _loadTransactions(String listingId) async {
    if (listingId.isEmpty || supabase.auth.currentUser == null) return;
    final txs =
        await MarketplaceService.fetchTransactions(asSeller: _isOwner);
    if (!mounted) return;
    setState(() {
      if (_isOwner) {
        _txByOffer = {
          for (final t in txs)
            if (t.listingId == listingId && t.offerId.isNotEmpty)
              t.offerId: t,
        };
      } else {
        _myReservations = [
          for (final t in txs)
            if (t.listingId == listingId && t.isReserved) t,
        ];
      }
    });
  }

  /// Re-reads status + stock after a deal completes/cancels, so the page
  /// reflects the relist/sold outcome without reopening it.
  Future<void> _refreshListingState() async {
    final id = widget.listingId?.trim() ?? '';
    if (id.isEmpty) return;
    try {
      final result =
          await supabase.rpc('listing_stock', params: {'p_listing_id': id});
      final rows = (result as List?) ?? const [];
      if (!mounted || rows.isEmpty) return;
      final row = rows.first as Map<String, dynamic>;
      setState(() {
        _status = (row['status'] as String?) ?? _status;
        _stock = (row['stock'] as num?)?.toInt() ?? _stock;
        _reservedQty = (row['reserved'] as num?)?.toInt() ?? 0;
        _edited = true; // list pages refresh on pop
      });
    } catch (e) {
      debugPrint('Failed to refresh listing state: $e');
    }
  }

  /// Owner completes the reserved deal from the offers section.
  Future<void> _completeTx(TransactionInfo tx) async {
    final error = await MarketplaceService.completeTransaction(tx.id);
    if (!mounted) return;
    if (error != null) {
      _showSnackBar(error);
      return;
    }
    _showSnackBar('Sale completed. The buyer can now rate you.');
    _loadListingOffers(widget.listingId?.trim() ?? '');
    _loadTransactions(widget.listingId?.trim() ?? '');
    _refreshListingState();
  }

  /// Cancels the reserved deal (owner from the offers section, or the
  /// winning buyer from their reservation banner).
  Future<void> _cancelTx(TransactionInfo tx) async {
    final error = await MarketplaceService.cancelTransaction(tx.id);
    if (!mounted) return;
    if (error != null) {
      _showSnackBar(error);
      return;
    }
    _showSnackBar('Deal cancelled. The listing is available again.');
    setState(() => _myReservations.removeWhere((r) => r.id == tx.id));
    _loadListingOffers(widget.listingId?.trim() ?? '');
    _loadTransactions(widget.listingId?.trim() ?? '');
    _refreshListingState();
  }

  /// The buyer-facing "Reserved for you" card for one live deal. Rendered once
  /// per reservation so a buyer holding several deals on this listing can see
  /// and cancel each independently.
  Widget _reservationCard(TransactionInfo res) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFE0B2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.handshake_outlined,
                    color: Color(0xFFE65100), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Reserved for you — '
                    '${_formatPeso(res.agreedPrice)}'
                    '${res.quantity > 1 ? ' for ${res.quantity} pcs' : ''}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE65100)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Arrange payment and pickup/delivery with the seller on '
              'Messenger. The seller marks the sale completed once you\'ve '
              'received it.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => _cancelTx(res),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.red.shade300),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Cancel deal',
                      style: TextStyle(
                          color: Colors.red.shade400,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Loads the seller's Messenger link for the contact button.
  Future<void> _loadSellerMessengerLink(String sellerId) async {
    if (sellerId.isEmpty) return;
    try {
      final row = await supabase
          .from('users')
          .select('messenger_link')
          .eq('id', sellerId)
          .maybeSingle();
      final link = (row?['messenger_link'] as String?)?.trim() ?? '';
      if (mounted && link.isNotEmpty) {
        setState(() => _sellerMessengerLink = link);
      }
    } catch (e) {
      debugPrint('Failed to load messenger link: $e');
    }
  }

  /// Owner-only: loads the offers buyers have made on this post.
  Future<void> _loadListingOffers(String listingId) async {
    if (!_isOwner || listingId.isEmpty) return;
    final offers = await MarketplaceService.fetchListingOffers(listingId);
    if (mounted) setState(() => _listingOffers = offers);
  }

  /// Owner accepts or declines one of this post's offers.
  Future<void> _respondToOffer(Offer offer, {required bool accept}) async {
    final error =
        await MarketplaceService.respondToOffer(offer.id, accept: accept);
    if (!mounted) return;
    if (error != null) {
      _showSnackBar(error);
      return;
    }
    _showSnackBar(accept ? 'Offer accepted.' : 'Offer declined.');
    final id = widget.listingId?.trim() ?? '';
    _loadListingOffers(id);
    if (accept) {
      // A new reserved deal now exists — pull it in so this offer row shows
      // Complete/Cancel, and refresh the listing's status/stock.
      _loadTransactions(id);
      _refreshListingState();
    }
  }

  /// Fetches the stock quantity and numeric price from the listing row;
  /// callers don't pass them in.
  Future<void> _loadStock(String listingId) async {
    if (listingId.isEmpty) return;
    try {
      final result = await supabase
          .rpc('listing_stock', params: {'p_listing_id': listingId});
      final rows = (result as List?) ?? const [];
      if (!mounted || rows.isEmpty) return;
      final row = rows.first as Map<String, dynamic>;
      final stock = (row['stock'] as num?)?.toInt();
      final price = (row['price'] as num?)?.toDouble();
      setState(() {
        if (stock != null) _stock = stock;
        _reservedQty = (row['reserved'] as num?)?.toInt() ?? 0;
        if (price != null && price > 0) _askingPrice = price;
      });
    } catch (e) {
      debugPrint('Failed to load stock: $e');
    }
  }

  /// One-tap "Buy at asking price": sends an offer pre-filled with the
  /// listed price (× quantity), so the deal starts with a paper trail the
  /// seller only has to accept.
  Future<void> _buyAtAskingPrice() async {
    final price = _askingPrice;
    if (price == null || price <= 0) return;
    if (supabase.auth.currentUser == null) {
      _showSnackBar('Please log in to buy.');
      return;
    }

    int qty = 1;
    final maxQty = (_available != null && _available! > 0) ? _available! : 1;
    bool sending = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) {
          final total = price * qty;
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Buy at asking price',
                style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This sends the seller an offer at the listed price — no '
                  'haggling. Once they accept, the listing is reserved for '
                  'you.',
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Text(
                  'Listed price: ${_formatPeso(price)}'
                  '${_available != null ? ' · $_available available' : ''}',
                  style: const TextStyle(fontSize: 12.5, color: Colors.black45),
                ),
                const SizedBox(height: 14),
                if (maxQty > 1)
                  Row(
                    children: [
                      const Text('Quantity',
                          style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      IconButton(
                        onPressed: qty > 1
                            ? () => setLocal(() => qty--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                        color: const Color(0xFF6DBF99),
                      ),
                      Text('$qty',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      IconButton(
                        onPressed: qty < maxQty
                            ? () => setLocal(() => qty++)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                        color: const Color(0xFF6DBF99),
                      ),
                    ],
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                    Text(_formatPeso(total),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1D9E75))),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.black54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6DBF99),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: sending
                    ? null
                    : () async {
                        setLocal(() => sending = true);
                        final error = await MarketplaceService.submitOffer(
                          listingId: widget.listingId?.trim() ?? '',
                          sellerId: widget.sellerId?.trim() ?? '',
                          amount: price * qty,
                          quantity: qty,
                          note: 'Buy at asking price',
                        );
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        if (!mounted) return;
                        if (error == null) {
                          setState(() => _offerSent = true);
                          _showSnackBar(
                              'Offer sent at the asking price — you\'ll be '
                              'notified when the seller accepts.');
                        } else {
                          _showSnackBar(error);
                        }
                      },
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Text('Send offer',
                        style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
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
    final c = _editCondition ?? widget.condition?.trim() ?? '';
    if (c.isNotEmpty) return c;
    return 'Good';
  }

  String get _description {
    final d = _editDesc ?? widget.description?.trim() ?? '';
    if (d.isNotEmpty) return d;
    return _details[widget.name]?['description'] ?? 'No description available.';
  }

  String get _breed {
    final b = _editBreed ?? widget.breed?.trim() ?? '';
    if (b.isNotEmpty) return b;
    return _details[widget.name]?['breed'] ?? 'Unknown';
  }

  String get _age {
    final a = _editAge ?? widget.age?.trim() ?? '';
    if (a.isNotEmpty) return a;
    return _details[widget.name]?['age'] ?? 'Unknown';
  }

  String get _weight {
    final w = _editWeight ?? widget.weight?.trim() ?? '';
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
              _buildSheetOption(Icons.edit_outlined, 'Edit Listing',
                  const Color(0xFF6DBF99), () {
                Navigator.pop(context);
                _showEditListing();
              }),
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
              _buildSheetOption(Icons.copy_outlined, 'Copy Link', Colors.black87, () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(
                  text: 'https://farm.app/listing/${widget.name.toLowerCase().replaceAll(' ', '-')}',
                ));
                _showSnackBar('Link copied to clipboard!');
              }),
              if (_status != 'sold')
                _buildSheetOption(Icons.flag_outlined, 'Mark as Sold', Colors.orange, () {
                  Navigator.pop(context);
                  _markAsSold();
                }),
            ],
            // Visitors only get the trust & safety actions.
            if (!_isOwner) ...[
              _buildSheetOption(Icons.report_outlined, 'Report Listing', Colors.red, () {
                Navigator.pop(context);
                _showReportDialog(targetType: 'listing');
              }),
              _buildSheetOption(Icons.gavel_outlined, 'Report Seller', Colors.red, () {
                Navigator.pop(context);
                _showReportDialog(targetType: 'seller');
              }),
              _buildSheetOption(
                _isBlocked ? Icons.person_add_alt_1 : Icons.block_outlined,
                _isBlocked ? 'Unblock Seller' : 'Block Seller',
                Colors.black87,
                () {
                  Navigator.pop(context);
                  _toggleBlockSeller();
                },
              ),
            ],
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

  /// Marks the listing sold out: stock is zeroed (so "Sold" always means no
  /// stock, never a leftover quantity), any still-pending offers are declined,
  /// and it goes grey in the feed. Blocked while a deal is still reserved — the
  /// seller must finish or cancel those first. To sell again, edit the stock.
  Future<void> _markAsSold() async {
    final id = widget.listingId;
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark as sold out?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: const Text(
          'This sets the stock to 0, hides the listing from buyers, and '
          'declines any pending offers. You can put it back on the market '
          'later by editing its stock.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6DBF99)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark Sold', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      // Zeroing stock trips the guard trigger if any unit is still reserved,
      // which surfaces a readable message here.
      await supabase
          .from('listings')
          .update({'stock': 0, 'status': 'sold'}).eq('id', id);
      // Best-effort: give pending bidders closure (fires their notification).
      final uid = supabase.auth.currentUser?.id;
      if (uid != null) {
        try {
          await supabase
              .from('offers')
              .update({'status': 'declined'})
              .eq('listing_id', id)
              .eq('seller_id', uid)
              .eq('status', 'pending');
        } catch (_) {/* non-fatal */}
      }
      if (!mounted) return;
      setState(() {
        _status = 'sold';
        _stock = 0;
        _edited = true; // so list pages refresh on pop
      });
      _loadListingOffers(id);
      _showSnackBar('Listing marked as sold out.');
    } on PostgrestException catch (e) {
      if (mounted) _showSnackBar(e.message);
    } catch (e) {
      if (mounted) _showSnackBar('Could not update listing. Please try again.');
    }
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

  /// Owner-only: edit the listing's content in place. Saves to the `listings`
  /// row and updates the page immediately via the _edit* overrides.
  void _showEditListing() {
    final id = widget.listingId?.trim() ?? '';
    if (id.isEmpty) return;
    final titleCtrl = TextEditingController(text: _title);
    final priceCtrl = TextEditingController(
        text: _priceText.replaceAll(RegExp(r'[^0-9.]'), ''));
    final breedCtrl = TextEditingController(text: _breed);
    final ageCtrl = TextEditingController(text: _age);
    final weightCtrl = TextEditingController(text: _weight);
    final stockCtrl = TextEditingController(text: '${_stock ?? ''}');
    final descCtrl = TextEditingController(text: _description);
    const conditions = ['Good', 'Excellent', 'Fair'];
    String condition =
        conditions.contains(_condition) ? _condition : conditions.first;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Edit Listing',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _editField(titleCtrl, 'Title'),
                const SizedBox(height: 12),
                _editField(priceCtrl, 'Price',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    prefixText: '₱ '),
                const SizedBox(height: 12),
                _editField(breedCtrl, 'Breed'),
                const SizedBox(height: 12),
                _editField(ageCtrl, 'Age'),
                const SizedBox(height: 12),
                _editField(weightCtrl, 'Weight (e.g. 1.5 kg)'),
                const SizedBox(height: 12),
                _editField(stockCtrl, 'Stock (quantity available)',
                    keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: condition,
                      icon: const Icon(Icons.keyboard_arrow_down,
                          color: Colors.black38),
                      items: conditions
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (val) =>
                          setSheet(() => condition = val ?? condition),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _editField(descCtrl, 'Description', maxLines: 4),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: saving
                        ? null
                        : () async {
                            final title = titleCtrl.text.trim();
                            final priceValue =
                                num.tryParse(priceCtrl.text.trim());
                            final stockValue =
                                int.tryParse(stockCtrl.text.trim());
                            if (title.isEmpty ||
                                priceValue == null ||
                                stockValue == null ||
                                stockValue < 0) {
                              showTopMessage(sheetCtx,
                                  'Please enter a valid title, price and stock.');
                              return;
                            }
                            // Restocking a sold listing puts it back online —
                            // make that an explicit choice, never a silent
                            // side effect of saving other edits.
                            final relist =
                                _status == 'sold' && stockValue > 0;
                            if (relist) {
                              final ok = await showDialog<bool>(
                                context: sheetCtx,
                                builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                  title: const Text(
                                    'Put this listing back on the market?',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                  content: Text(
                                    'It will become visible to buyers again '
                                    'with $stockValue in stock.',
                                    style: const TextStyle(
                                        fontSize: 13, color: Colors.black54),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancel',
                                          style: TextStyle(
                                              color: Colors.black54)),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF6DBF99)),
                                      onPressed: () =>
                                          Navigator.pop(ctx, true),
                                      child: const Text('Relist',
                                          style:
                                              TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                              if (ok != true) return;
                            }
                            setSheet(() => saving = true);
                            try {
                              await supabase.from('listings').update({
                                'title': title,
                                'price': priceValue,
                                'breed': breedCtrl.text.trim(),
                                'age': ageCtrl.text.trim(),
                                'weight': weightCtrl.text.trim(),
                                'stock': stockValue,
                                'condition': condition,
                                'description': descCtrl.text.trim(),
                                if (relist) 'status': 'active',
                              }).eq('id', id);
                            } catch (e) {
                              if (sheetCtx.mounted) {
                                setSheet(() => saving = false);
                                showTopMessage(sheetCtx,
                                    'Could not save changes: $e');
                              }
                              return;
                            }
                            if (!mounted) return;
                            setState(() {
                              _editTitle = title;
                              _editPrice = _formatPeso(priceValue);
                              _editBreed = breedCtrl.text.trim();
                              _editAge = ageCtrl.text.trim();
                              _editWeight = weightCtrl.text.trim();
                              _stock = stockValue;
                              _editCondition = condition;
                              _editDesc = descCtrl.text.trim();
                              if (relist) _status = 'active';
                              _edited = true;
                            });
                            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                            _showSnackBar(relist
                                ? 'Listing updated — it\'s back online for buyers.'
                                : 'Listing updated.');
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6DBF99),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: saving
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text('Save Changes',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _editField(TextEditingController controller, String hint,
      {TextInputType keyboardType = TextInputType.text,
      String? prefixText,
      int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          labelText: hint,
          prefixText: prefixText,
          labelStyle: const TextStyle(color: Colors.black45, fontSize: 13),
          hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  /// Formats a numeric price as e.g. "₱350" (no trailing ".0").
  String _formatPeso(num value) {
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
    return '₱$text';
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

  /// Unified report dialog for either a listing or its seller. Persists the
  /// report to the `reports` table via [MarketplaceService].
  void _showReportDialog({required String targetType}) {
    if (supabase.auth.currentUser == null) {
      _showSnackBar('Please log in to submit a report.');
      return;
    }
    final isSeller = targetType == 'seller';
    final TextEditingController detailsController = TextEditingController();
    final List<String> reasons = isSeller
        ? ['Fraud / scam', 'Poor communication', 'Misleading listings', 'Other']
        : ['Prohibited animal', 'Misleading info', 'Wrong category', 'Spam', 'Other'];
    String selectedReason = reasons.first;
    bool submitting = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(isSeller ? 'Report Seller' : 'Report Listing',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isSeller
                    ? 'Why are you reporting this seller?'
                    : 'Why are you reporting this listing?',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              DropdownButton<String>(
                value: selectedReason,
                isExpanded: true,
                items: reasons
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (val) => setLocalState(() => selectedReason = val!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: detailsController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Additional details (optional)...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: submitting
                  ? null
                  : () async {
                      setLocalState(() => submitting = true);
                      final error = await MarketplaceService.submitReport(
                        targetType: targetType,
                        listingId: widget.listingId?.trim(),
                        sellerId: widget.sellerId?.trim(),
                        reason: selectedReason,
                        details: detailsController.text,
                      );
                      if (!dialogCtx.mounted) return;
                      Navigator.pop(dialogCtx);
                      _showSnackBar(error ??
                          'Report submitted. Our team will review it. Thank you.');
                    },
              child: const Text('Submit Report', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  /// Blocks or unblocks the seller. Blocked sellers' listings are hidden from
  /// the buyer's browse page.
  Future<void> _toggleBlockSeller() async {
    final sellerId = widget.sellerId?.trim() ?? '';
    if (sellerId.isEmpty) {
      _showSnackBar('Blocking is unavailable for this listing.');
      return;
    }
    if (supabase.auth.currentUser == null) {
      _showSnackBar('Please log in to block a seller.');
      return;
    }
    if (sellerId == supabase.auth.currentUser?.id) {
      _showSnackBar('You cannot block yourself.');
      return;
    }
    final wasBlocked = _isBlocked;
    final nowBlocked = await MarketplaceService.toggleBlock(
      sellerId,
      currentlyBlocked: wasBlocked,
    );
    if (!mounted) return;
    setState(() => _isBlocked = nowBlocked);
    _showSnackBar(nowBlocked
        ? 'Seller blocked. Their listings are now hidden.'
        : 'Seller unblocked.');
  }

  /// Opens the seller's Messenger link in the Messenger app / browser.
  Future<void> _openMessenger() async {
    final link = _sellerMessengerLink;
    if (link.isEmpty) {
      _showSnackBar("This seller hasn't added a Messenger link yet.");
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri == null) {
      _showSnackBar('Could not open Messenger.');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _showSnackBar('Could not open Messenger.');
  }

  void _showMakeOfferDialog() {
    if (supabase.auth.currentUser == null) {
      _showSnackBar('Please log in to make an offer.');
      return;
    }
    final TextEditingController offerController = TextEditingController();
    final TextEditingController qtyController =
        TextEditingController(text: '1');
    final TextEditingController noteController = TextEditingController();
    bool sending = false;

    InputDecoration fieldDecoration(String hint, {String? prefix}) =>
        InputDecoration(
          prefixText: prefix,
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF6DBF99)),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        );

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Make an Offer', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Listed price: ${widget.price}'
                '${_available != null ? (_isOwner ? ' · $_stock in stock' : ' · $_available available') : ''}',
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: offerController,
                keyboardType: TextInputType.number,
                decoration:
                    fieldDecoration('Your total offer', prefix: '₱ '),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: fieldDecoration('Quantity'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                maxLines: 2,
                maxLength: 200,
                decoration:
                    fieldDecoration('Message to the seller (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6DBF99),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: sending
                  ? null
                  : () async {
                      final amount =
                          double.tryParse(offerController.text.trim());
                      if (amount == null || amount <= 0) {
                        _showSnackBar('Please enter a valid offer amount.');
                        return;
                      }
                      final qty =
                          int.tryParse(qtyController.text.trim()) ?? 1;
                      if (qty < 1 ||
                          (_available != null &&
                              _available! > 0 &&
                              qty > _available!)) {
                        _showSnackBar(
                            'Please enter a quantity between 1 and ${_available ?? qty}.');
                        return;
                      }
                      setLocalState(() => sending = true);
                      // Persist the offer so it shows up in the seller's
                      // dashboard "Offers" section.
                      final error = await MarketplaceService.submitOffer(
                        listingId: widget.listingId?.trim() ?? '',
                        sellerId: widget.sellerId?.trim() ?? '',
                        amount: amount,
                        quantity: qty,
                        note: noteController.text,
                      );
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      if (!mounted) return;
                      if (error == null) {
                        setState(() => _offerSent = true);
                        _showSnackBar(
                            'Offer of ${_formatPeso(amount)} sent to seller!');
                      } else {
                        _showSnackBar(error);
                      }
                    },
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Text('Send Offer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _shareProduct() {
    // Real share URL: the listing-page edge function renders a public
    // preview of this listing (with OpenGraph tags for chat unfurls).
    final id = widget.listingId?.trim() ?? '';
    final link = id.isEmpty
        ? ''
        : '${SupabaseConfig.url}/functions/v1/listing-page?id=$id';

    final shareText =
        '🐔 Check out this listing!\n\n'
        '$_title — $_priceText\n'
        'Location: $_location\n'
        'Seller: $_sellerName'
        '${link.isEmpty ? '' : '\n\n$link'}';

    // Copy to clipboard as a simple share fallback
    Clipboard.setData(ClipboardData(text: shareText));
    _showSnackBar('Listing link copied! You can now paste it to share.');
  }

  Future<void> _toggleFavorite() async {
    final listingId = widget.listingId?.trim() ?? '';
    if (listingId.isEmpty) {
      _showSnackBar('Sign in and open a real listing to save favourites.');
      return;
    }
    if (supabase.auth.currentUser == null) {
      _showSnackBar('Please log in to save favourites.');
      return;
    }
    final wasFav = _isFavorited;
    setState(() => _isFavorited = !wasFav);
    _showSnackBar(!wasFav ? 'Added to favorites!' : 'Removed from favorites.');
    final nowFav = await MarketplaceService.toggleFavorite(
      listingId,
      currentlyFavorited: wasFav,
    );
    if (mounted && nowFav != !wasFav) {
      setState(() => _isFavorited = nowFav);
    }
  }

  /// Opens the seller's public reviews & rating page.
  void _openSellerReviews() {
    final sellerId = widget.sellerId?.trim() ?? '';
    if (sellerId.isEmpty) {
      _showSnackBar('Seller reviews are unavailable for this listing.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SellerReviewsPage(
          sellerId: sellerId,
          sellerName: _sellerName,
        ),
      ),
    ).then((_) => _loadMarketplaceState());
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
          sellerId: widget.sellerId?.trim() ?? '',
          rating: _sellerRating,
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
                      onPressed: () =>
                          Navigator.of(context).maybePop(_edited ? 'updated' : null),
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
                    Text(_title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    Text(_priceText,
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
                            child: Text(
                              _status == 'sold'
                                  ? 'Sold'
                                  : _status == 'reserved'
                                      ? 'Reserved'
                                      : 'Disabled',
                              style: const TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Owner banner (own listing: no messaging yourself) ─
              if (_isOwner)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F8F1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.storefront_outlined,
                            color: Color(0xFF1D9E75), size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('This is your listing.',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A2E22))),
                        ),
                        GestureDetector(
                          onTap: _showEditListing,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6DBF99),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Edit',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Reserved-for-you banners (one per live deal) ──────
              // A buyer can hold several deals on the same listing while it
              // still has stock, so each reservation gets its own card.
              if (!_isOwner && _myReservations.isNotEmpty)
                ..._myReservations.map(_reservationCard),

              // ── Offers on this post (owner only) ─────────────────
              if (_isOwner && _listingOffers.isNotEmpty) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildOffersSection(),
                ),
              ],

              // ── Message Seller on Messenger ──────────────────────
              // Chat happens on Facebook Messenger via the seller's link
              // (saved when they became a seller).
              if (!_isOwner)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _openMessenger,
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('Message Seller on Messenger',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0084FF),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),

              // ── Buy at asking price (one-tap offer) ───────────────
              // Available whenever the listing still has stock ('active'),
              // even if the buyer already holds a reservation on it.
              if (!_isOwner &&
                  _status == 'active' &&
                  (_askingPrice ?? 0) > 0) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _buyAtAskingPrice,
                      icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                      label: Text(
                          'Buy at asking price — ${_formatPeso(_askingPrice!)}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6DBF99),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // ── Action Buttons ───────────────────────────────────
              // Owners can't offer on or favourite their own listing; they
              // only get the share action.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // No offers on your own post or while the listing isn't
                    // active; a buyer with a reservation can still offer for
                    // more while stock remains.
                    if (!_isOwner && _status == 'active')
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
                    if (!_isOwner)
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
              // Hidden on the owner's own listing — the "This is your
              // listing." banner already says whose post it is, and a
              // "Visit" button to your own profile makes no sense.
              if (!_isOwner) ...[
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
                              GestureDetector(
                                onTap: _openSellerReviews,
                                child: Row(
                                  children: [
                                    const Icon(Icons.star_rounded,
                                        color: Color(0xFFFFB300), size: 14),
                                    const SizedBox(width: 2),
                                    Text(
                                      _sellerRating.hasReviews
                                          ? '${_sellerRating.average.toStringAsFixed(1)} (${_sellerRating.count})'
                                          : 'No reviews yet',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black54),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text('· See reviews',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF6DBF99),
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
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
              ],

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
                    if (_available != null) ...[
                      const SizedBox(height: 6),
                      _buildDetailRow(
                          Icons.inventory_2_outlined,
                          'Stock',
                          // The owner sees their real total (plus how many are
                          // tied up in deals); buyers see what's still free.
                          _isOwner
                              ? (_reservedQty > 0
                                  ? '$_stock in stock · $_reservedQty reserved'
                                  : '$_stock in stock')
                              : _stock == 0
                                  ? 'Out of stock'
                                  : _available == 0
                                      ? 'Fully reserved'
                                      : '$_available available',
                          valueColor: (!_isOwner && _available == 0)
                              ? Colors.red
                              : Colors.black54),
                    ],
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

  /// Owner-only card listing every buyer offer on this post, with the
  /// buyer's profile picture, name and Accept/Decline actions.
  Widget _buildOffersSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pan_tool_outlined,
                  color: Color(0xFF1D9E75), size: 18),
              const SizedBox(width: 8),
              Text(
                'Offers (${_listingOffers.length})',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ..._listingOffers.map(_buildOfferRow),
        ],
      ),
    );
  }

  Widget _buildOfferRow(Offer offer) {
    final isPending = offer.status == 'pending';
    final tx = _txByOffer[offer.id];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Buyer's profile picture (falls back to a person icon).
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
                color: Color(0xFFD6F0E4), shape: BoxShape.circle),
            clipBehavior: Clip.antiAlias,
            child: offer.buyerAvatar.isNotEmpty
                ? Image.network(offer.buyerAvatar,
                    fit: BoxFit.cover,
                    errorBuilder: (_, e, s) => const Icon(Icons.person,
                        color: Color(0xFF6DBF99), size: 20))
                : const Icon(Icons.person, color: Color(0xFF6DBF99), size: 20),
          ),
          const SizedBox(width: 10),
          // The action buttons live BELOW the buyer info (and wrap among
          // themselves) so they never fight the text for horizontal space —
          // keeps the row overflow-free on any device width or text scale.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(offer.buyerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
                Text(
                    'Offered ${_formatPeso(offer.amount)}'
                    '${offer.quantity > 1 ? ' for ${offer.quantity} pcs' : ''}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1D9E75))),
                if (offer.note.isNotEmpty)
                  Text('“${offer.note}”',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Colors.black38)),
                const SizedBox(height: 8),
                _buildOfferActions(offer, tx, isPending),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Trailing controls for an offer row, in a [Wrap] so a button drops to the
  /// next line on narrow screens instead of overflowing.
  Widget _buildOfferActions(Offer offer, TransactionInfo? tx, bool isPending) {
    final List<Widget> children;
    if (tx != null && tx.isReserved) {
      // Live deal: finish it or free the listing back up.
      children = [
        _offerActionButton('Complete',
            filled: true, onTap: () => _completeTx(tx)),
        _offerActionButton('Cancel',
            filled: false, onTap: () => _cancelTx(tx)),
      ];
    } else if (isPending) {
      children = [
        _offerActionButton('Accept',
            filled: true, onTap: () => _respondToOffer(offer, accept: true)),
        _offerActionButton('Decline',
            filled: false, onTap: () => _respondToOffer(offer, accept: false)),
      ];
    } else {
      // Deal state wins over the raw offer state.
      final String label;
      final Color bg;
      final Color fg;
      if (tx != null && tx.status == 'completed') {
        label = 'Completed';
        bg = const Color(0xFFE8F7F1);
        fg = const Color(0xFF1D9E75);
      } else if (tx != null && tx.status == 'cancelled') {
        label = 'Cancelled';
        bg = const Color(0xFFF2F2F2);
        fg = Colors.black45;
      } else if (offer.status == 'accepted') {
        label = 'Accepted';
        bg = const Color(0xFFE8F7F1);
        fg = const Color(0xFF1D9E75);
      } else {
        label = 'Declined';
        bg = const Color(0xFFFDECEC);
        fg = Colors.red.shade400;
      }
      children = [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
        ),
      ];
    }
    return Wrap(spacing: 6, runSpacing: 6, children: children);
  }

  Widget _offerActionButton(String label,
      {required bool filled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? const Color(0xFF6DBF99) : null,
          border: filled ? null : Border.all(color: Colors.red.shade300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: filled ? Colors.white : Colors.red.shade400,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
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

// ── Seller Profile Page ────────────────────────────────────────────────────
class _SellerProfilePage extends StatefulWidget {
  final String sellerName;
  final String sellerJoined;
  final String? breederSince;
  final String location;
  final String sellerId;
  final SellerRating rating;

  const _SellerProfilePage({
    required this.sellerName,
    required this.sellerJoined,
    this.breederSince,
    required this.location,
    required this.sellerId,
    required this.rating,
  });

  @override
  State<_SellerProfilePage> createState() => _SellerProfilePageState();
}

class _SellerProfilePageState extends State<_SellerProfilePage> {
  String get sellerName => widget.sellerName;
  String get sellerJoined => widget.sellerJoined;
  String? get breederSince => widget.breederSince;
  String get location => widget.location;
  String get sellerId => widget.sellerId;
  SellerRating get rating => widget.rating;

  // The seller's avatar and their active listings, loaded from Supabase.
  String _avatarUrl = '';
  String _messengerLink = '';
  List<Map<String, dynamic>> _sellerListings = [];
  bool _loadingListings = true;

  /// "Verified Seller" is only for sellers on a paid tier
  /// (Premium / Super Premium), resolved via the seller_tiers RPC.
  bool _isVerifiedSeller = false;

  @override
  void initState() {
    super.initState();
    _loadSellerDetails();
    _loadSellerListings();
    _loadSellerTier();
  }

  Future<void> _loadSellerTier() async {
    if (sellerId.isEmpty) return;
    try {
      final tiers = await supabase.rpc('seller_tiers', params: {
        'seller_ids': [sellerId]
      });
      final tier = (tiers is List && tiers.isNotEmpty)
          ? '${(tiers.first as Map)['tier']}'
          : 'Free';
      if (mounted) {
        setState(() =>
            _isVerifiedSeller = tier == 'Premium' || tier == 'Super Premium');
      }
    } catch (e) {
      debugPrint('Failed to load seller tier: $e');
    }
  }

  Future<void> _loadSellerDetails() async {
    if (sellerId.isEmpty) return;
    try {
      final row = await supabase
          .from('users')
          .select('avatar_url, messenger_link')
          .eq('id', sellerId)
          .maybeSingle();
      final url = (row?['avatar_url'] as String?)?.trim() ?? '';
      final link = (row?['messenger_link'] as String?)?.trim() ?? '';
      if (!mounted) return;
      setState(() {
        if (url.isNotEmpty) _avatarUrl = url;
        _messengerLink = link;
      });
    } catch (_) {
      // Fall back to the default person icon.
    }
  }

  /// Opens the seller's Messenger link.
  Future<void> _openMessenger() async {
    if (_messengerLink.isEmpty) {
      showTopMessage(context, "This seller hasn't added a Messenger link yet.",
          isError: false,
          backgroundColor: const Color(0xFF3A3A3A),
          icon: Icons.info_outline);
      return;
    }
    final uri = Uri.tryParse(_messengerLink);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Loads everything this seller currently has posted (active listings).
  Future<void> _loadSellerListings() async {
    if (sellerId.isEmpty) {
      setState(() => _loadingListings = false);
      return;
    }
    try {
      final rows = await supabase
          .from('listings')
          .select()
          .eq('seller_id', sellerId)
          .eq('status', 'active')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _sellerListings = (rows as List)
            .map((r) => r as Map<String, dynamic>)
            .toList();
        _loadingListings = false;
      });
    } catch (e) {
      debugPrint('Failed to load seller listings: $e');
      if (mounted) setState(() => _loadingListings = false);
    }
  }

  String _formatPrice(dynamic raw) {
    final value = raw is num ? raw : (num.tryParse('$raw') ?? 0);
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
    return '₱$text';
  }

  void _openListing(Map<String, dynamic> row) {
    final img = (row['image_url'] as String?)?.trim() ?? '';
    final imgs = (row['image_urls'] as List?)
            ?.map((e) => '$e')
            .where((e) => e.trim().isNotEmpty)
            .toList() ??
        <String>[];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailPage(
          name: (row['title'] as String?) ?? 'Untitled',
          price: _formatPrice(row['price']),
          image: img.isNotEmpty ? img : 'images/chicken.png',
          images: imgs,
          description: (row['description'] as String?) ?? '',
          condition: (row['condition'] as String?) ?? '',
          sellerName: sellerName,
          location: (row['location'] as String?) ?? '',
          breed: (row['breed'] as String?) ?? '',
          age: (row['age'] as String?) ?? '',
          weight: (row['weight'] as String?) ?? '',
          createdAt: '${row['created_at'] ?? ''}',
          listingId: '${row['id'] ?? ''}',
          sellerId: '${row['seller_id'] ?? ''}',
          status: (row['status'] as String?) ?? 'active',
        ),
      ),
    );
  }

  Widget _listingThumb(String path) {
    Widget placeholder() => Container(
          color: const Color(0xFFD6F0E4),
          child: const Icon(Icons.image_not_supported_outlined,
              color: Colors.white54, size: 32),
        );
    return path.startsWith('http')
        ? Image.network(path,
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder())
        : Image.asset(path,
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder());
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
              clipBehavior: Clip.antiAlias,
              child: _avatarUrl.isNotEmpty
                  ? Image.network(_avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.person,
                          color: Color(0xFF6DBF99), size: 44))
                  : const Icon(Icons.person, color: Color(0xFF6DBF99), size: 44),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(sellerName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                if (_isVerifiedSeller) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified, color: Colors.blue, size: 20),
                ],
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
                _buildStat(
                    'Rating',
                    rating.hasReviews
                        ? '${rating.average.toStringAsFixed(1)} ⭐'
                        : '—'),
                _buildStat('Reviews', '${rating.count}'),
                _buildStat('Trust',
                    rating.hasReviews ? '${rating.trustPercent}%' : '—'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6DBF99),
                  side: const BorderSide(color: Color(0xFF6DBF99)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: sellerId.isEmpty
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SellerReviewsPage(
                              sellerId: sellerId,
                              sellerName: sellerName,
                            ),
                          ),
                        ),
                icon: const Icon(Icons.reviews_outlined, size: 18),
                label: const Text('See all reviews',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
            if (_isVerifiedSeller) ...[
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
            ],
            const SizedBox(height: 24),

            // ── Seller's posted listings ─────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Listings by $sellerName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                ),
                if (!_loadingListings)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F7F1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${_sellerListings.length}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6DBF99),
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingListings)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF6DBF99)),
                ),
              )
            else if (_sellerListings.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F9F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.storefront_outlined,
                        color: Colors.black26, size: 36),
                    SizedBox(height: 8),
                    Text('No active listings right now',
                        style: TextStyle(fontSize: 13, color: Colors.black45)),
                  ],
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _sellerListings.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemBuilder: (context, index) {
                  final row = _sellerListings[index];
                  final img = (row['image_url'] as String?)?.trim() ?? '';
                  return GestureDetector(
                    onTap: () => _openListing(row),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: const Color(0xFF6DBF99), width: 1.5),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SizedBox(
                              width: double.infinity,
                              child: ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(10),
                                  topRight: Radius.circular(10),
                                ),
                                child: _listingThumb(
                                    img.isNotEmpty ? img : 'images/chicken.png'),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text((row['title'] as String?) ?? 'Untitled',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Text(_formatPrice(row['price']),
                                    style: const TextStyle(
                                        color: Color(0xFF6DBF99),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                                const SizedBox(height: 2),
                                Text((row['category'] as String?) ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.black38)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6DBF99),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _openMessenger,
                child: const Text('Message Seller on Messenger',
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
