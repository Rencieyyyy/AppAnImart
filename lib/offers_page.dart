import 'package:flutter/material.dart';
import 'main.dart';
import 'product_detail.dart';
import 'services/marketplace_service.dart';
import 'services/notification_service.dart';
import 'widgets/top_message.dart';

/// Seller-side "Offers" screen (opened from the profile page's Seller
/// Dashboard). Shows each of the seller's listing posts with the offers from
/// potential buyers grouped underneath, so the seller can accept or decline
/// them per listing.
class OffersPage extends StatefulWidget {
  const OffersPage({super.key});

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  bool _loading = true;

  /// Offers received by the signed-in seller, grouped by listing id.
  Map<String, List<Offer>> _offersByListing = {};

  /// The seller's listing rows keyed by id, for the post header cards.
  Map<String, Map<String, dynamic>> _listingsById = {};

  @override
  void initState() {
    super.initState();
    _load();
    // Visiting this page clears the red dot on the Seller Dashboard's
    // "Offers" action.
    NotificationService.markOffersSeen();
  }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final offers = await MarketplaceService.fetchReceivedOffers();

      // Fetch this seller's listing rows so each group can show the post
      // (full rows, so tapping a group can open the listing page).
      final listingRows =
          await supabase.from('listings').select().eq('seller_id', uid);

      final byListing = <String, List<Offer>>{};
      for (final o in offers) {
        byListing.putIfAbsent(o.listingId, () => []).add(o);
      }
      final listings = <String, Map<String, dynamic>>{
        for (final r in (listingRows as List))
          '${(r as Map)['id']}': r as Map<String, dynamic>,
      };

      if (!mounted) return;
      setState(() {
        _offersByListing = byListing;
        _listingsById = listings;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Failed to load offers: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(Offer offer, {required bool accept}) async {
    final error =
        await MarketplaceService.respondToOffer(offer.id, accept: accept);
    if (!mounted) return;
    if (error != null) {
      showTopMessage(context, error);
      return;
    }
    showTopMessage(
      context,
      accept
          ? 'Offer accepted. You can now message the buyer to arrange the sale.'
          : 'Offer declined.',
      isError: false,
      backgroundColor: const Color(0xFF6DBF99),
    );
    _load();
  }

  /// Opens the listing this offer group belongs to (it's the seller's own
  /// post) and reloads on return in case it was edited or deleted.
  Future<void> _openListing(Map<String, dynamic>? listing) async {
    if (listing == null) {
      showTopMessage(context, 'This listing is no longer available.');
      return;
    }
    final priceRaw = listing['price'];
    final price = priceRaw is num
        ? priceRaw.toDouble()
        : (double.tryParse('$priceRaw') ?? 0);
    final img = (listing['image_url'] as String?)?.trim() ?? '';
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailPage(
          name: (listing['title'] as String?) ?? 'Untitled',
          price: _formatPeso(price),
          image: img.isNotEmpty ? img : 'images/chicken.png',
          images: (listing['image_urls'] as List?)
                  ?.map((e) => '$e')
                  .where((e) => e.trim().isNotEmpty)
                  .toList() ??
              const [],
          description: (listing['description'] as String?) ?? '',
          condition: (listing['condition'] as String?) ?? '',
          location: (listing['location'] as String?) ?? '',
          breed: (listing['breed'] as String?) ?? '',
          age: (listing['age'] as String?) ?? '',
          weight: (listing['weight'] as String?) ?? '',
          createdAt: '${listing['created_at'] ?? ''}',
          listingId: '${listing['id'] ?? ''}',
          sellerId: '${listing['seller_id'] ?? ''}',
          status: (listing['status'] as String?) ?? 'active',
        ),
      ),
    );
    if (!mounted) return;
    if (result == 'deleted' || result == 'updated') _load();
  }

  String _formatPeso(double value) {
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
    return '₱$text';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 1) return '${diff.inDays} day(s) ago';
    if (diff.inHours >= 1) return '${diff.inHours} hour(s) ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} min(s) ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    final listingIds = _offersByListing.keys.toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Offers',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6DBF99)))
          : listingIds.isEmpty
              ? RefreshIndicator(
                  color: const Color(0xFF6DBF99),
                  onRefresh: _load,
                  child: ListView(
                    children: const [
                      SizedBox(height: 140),
                      Icon(Icons.pan_tool_outlined,
                          size: 60, color: Colors.black26),
                      SizedBox(height: 14),
                      Text(
                        'No offers yet.\nWhen buyers make an offer on your\nlistings, it will show up here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black45, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFF6DBF99),
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: listingIds.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final listingId = listingIds[index];
                      final offers = _offersByListing[listingId]!;
                      final listing = _listingsById[listingId];
                      return _buildListingGroup(listingId, listing, offers);
                    },
                  ),
                ),
    );
  }

  /// One card: the listing post on top, its buyer offers listed underneath.
  Widget _buildListingGroup(
    String listingId,
    Map<String, dynamic>? listing,
    List<Offer> offers,
  ) {
    final title = (listing?['title'] as String?) ?? 'Listing removed';
    final priceRaw = listing?['price'];
    final price = priceRaw is num
        ? priceRaw.toDouble()
        : (double.tryParse('$priceRaw') ?? 0);
    final img = (listing?['image_url'] as String?)?.trim() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEDED)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── The seller's listing post (tap to open it) ────────────────
          InkWell(
            onTap: () => _openListing(listing),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: img.startsWith('http')
                        ? Image.network(img,
                            fit: BoxFit.cover,
                            errorBuilder: (_, e, s) => _thumbPlaceholder())
                        : _thumbPlaceholder(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.black87)),
                      const SizedBox(height: 2),
                      if (listing != null)
                        Text('Listed at ${_formatPeso(price)}',
                            style: const TextStyle(
                                color: Color(0xFF6DBF99),
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F7F1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${offers.length} offer${offers.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF1D9E75),
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          // ── The buyers' offers on this post ───────────────────────────
          ...offers.map(_buildOfferRow),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildOfferRow(Offer offer) {
    final isPending = offer.status == 'pending';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
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
                  'Offered ${_formatPeso(offer.amount)} · ${_timeAgo(offer.createdAt)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isPending) ...[
            // Accept
            GestureDetector(
              onTap: () => _respond(offer, accept: true),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF6DBF99),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Accept',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 6),
            // Decline
            GestureDetector(
              onTap: () => _respond(offer, accept: false),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Decline',
                    style: TextStyle(
                        color: Colors.red.shade400,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ] else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: offer.status == 'accepted'
                    ? const Color(0xFFE8F7F1)
                    : const Color(0xFFFDECEC),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                offer.status == 'accepted' ? 'Accepted' : 'Declined',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: offer.status == 'accepted'
                        ? const Color(0xFF1D9E75)
                        : Colors.red.shade400),
              ),
            ),
        ],
      ),
    );
  }

  Widget _thumbPlaceholder() => Container(
        color: const Color(0xFFD6F0E4),
        child: const Icon(Icons.image_not_supported_outlined,
            color: Colors.white54, size: 26),
      );
}
