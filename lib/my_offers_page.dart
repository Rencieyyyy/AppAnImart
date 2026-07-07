import 'package:flutter/material.dart';

import 'main.dart';
import 'seller_reviews.dart';
import 'services/marketplace_service.dart';
import 'widgets/top_message.dart';

/// Buyer-side "My Offers" screen (opened from the profile page). Shows every
/// offer the signed-in user has made with the listing it was made on, the
/// offer's state, and the resulting deal's state. Pending offers can be
/// withdrawn; reserved deals can be cancelled; completed deals link to the
/// seller's review page.
class MyOffersPage extends StatefulWidget {
  const MyOffersPage({super.key});

  @override
  State<MyOffersPage> createState() => _MyOffersPageState();
}

class _MyOffersPageState extends State<MyOffersPage> {
  bool _loading = true;
  List<Offer> _offers = const [];
  Map<String, Map<String, dynamic>> _listingsById = {};
  Map<String, TransactionInfo> _txByOffer = {};
  Map<String, String> _sellerNames = {};

  /// Offer ids with a request in flight (withdraw/cancel).
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final offers = await MarketplaceService.fetchSentOffers();
      final transactions =
          await MarketplaceService.fetchTransactions(asSeller: false);

      final listingIds = offers
          .map((o) => o.listingId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final listings = <String, Map<String, dynamic>>{};
      if (listingIds.isNotEmpty) {
        final rows = await supabase
            .from('listings')
            .select('id, title, price, image_url, status, seller_id')
            .inFilter('id', listingIds);
        for (final r in (rows as List)) {
          listings['${(r as Map)['id']}'] = r as Map<String, dynamic>;
        }
      }

      // Seller display names for the "Rate seller" flow.
      final sellerIds = offers
          .map((o) => o.sellerId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final names = <String, String>{};
      if (sellerIds.isNotEmpty) {
        try {
          final rows = await supabase
              .from('users')
              .select('id, name')
              .inFilter('id', sellerIds);
          for (final r in (rows as List)) {
            final m = r as Map<String, dynamic>;
            names['${m['id']}'] = ((m['name'] as String?) ?? '').trim();
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _offers = offers;
        _listingsById = listings;
        _txByOffer = {
          for (final t in transactions)
            if (t.offerId.isNotEmpty) t.offerId: t,
        };
        _sellerNames = names;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Failed to load my offers: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _withdraw(Offer offer) async {
    if (_busy.contains(offer.id)) return;
    setState(() => _busy.add(offer.id));
    final error = await MarketplaceService.withdrawOffer(offer.id);
    if (!mounted) return;
    setState(() => _busy.remove(offer.id));
    if (error != null) {
      showTopMessage(context, error);
      return;
    }
    showTopMessage(context, 'Offer withdrawn.',
        isError: false, backgroundColor: const Color(0xFF6DBF99));
    _load();
  }

  Future<void> _cancelDeal(TransactionInfo tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel this deal?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: const Text(
          'The seller will be notified and the listing becomes available to '
          'everyone again.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Keep deal', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel deal',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await MarketplaceService.cancelTransaction(tx.id);
    if (!mounted) return;
    if (error != null) {
      showTopMessage(context, error);
      return;
    }
    showTopMessage(context, 'Deal cancelled.',
        isError: false, backgroundColor: const Color(0xFF6DBF99));
    _load();
  }

  /// "Did you receive it?" — buyer confirms a seller-completed deal.
  Future<void> _confirmReceived(TransactionInfo tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Did you receive your order?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: const Text(
          'Confirming closes the deal and lets the seller know everything '
          'arrived. If something went wrong, use "Report a problem" instead.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Not yet', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6DBF99)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, I received it',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_busy.contains(tx.id)) return;
    setState(() => _busy.add(tx.id));
    final error = await MarketplaceService.confirmTransactionReceived(tx.id);
    if (!mounted) return;
    setState(() => _busy.remove(tx.id));
    if (error != null) {
      showTopMessage(context, error);
      return;
    }
    showTopMessage(context, 'Receipt confirmed. You can now rate the seller.',
        isError: false, backgroundColor: const Color(0xFF6DBF99));
    _load();
  }

  /// "Report a problem" — files a report carrying this deal's context.
  Future<void> _reportProblem(Offer offer, TransactionInfo tx) async {
    const reasons = [
      'Item not received',
      'Item not as described',
      'Seller is unresponsive',
      'Payment problem',
      'Other',
    ];
    String reason = reasons.first;
    final detailsCtrl = TextEditingController();
    bool sending = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Report a problem',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Our team will review this report together with the deal\'s '
                'details.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: reason,
                items: reasons
                    .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text(r, style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (v) => setLocal(() => reason = v ?? reason),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: detailsCtrl,
                maxLines: 3,
                maxLength: 400,
                decoration: InputDecoration(
                  hintText: 'Tell us what happened (optional)',
                  hintStyle:
                      const TextStyle(fontSize: 13, color: Colors.black38),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: sending
                  ? null
                  : () async {
                      setLocal(() => sending = true);
                      final error = await MarketplaceService.submitReport(
                        targetType: 'transaction',
                        listingId:
                            offer.listingId.isEmpty ? null : offer.listingId,
                        sellerId: offer.sellerId,
                        transactionId: tx.id,
                        reason: reason,
                        details: detailsCtrl.text,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (!mounted) return;
                      showTopMessage(
                        context,
                        error ??
                            'Report submitted. Our team will review this deal.',
                        isError: error != null,
                        backgroundColor: error == null
                            ? const Color(0xFF6DBF99)
                            : null,
                      );
                    },
              child: const Text('Submit report',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _rateSeller(Offer offer) {
    if (offer.sellerId.isEmpty) return;
    final name = _sellerNames[offer.sellerId] ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SellerReviewsPage(
          sellerId: offer.sellerId,
          sellerName: name.isNotEmpty ? name : 'AniMart Seller',
        ),
      ),
    );
  }

  String _formatPeso(double value) {
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
    return '₱$text';
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
        title: const Text('My Offers',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6DBF99)))
          : _offers.isEmpty
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
                        'No offers yet.\nOffers you make on listings will\nshow up here with their status.',
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
                    itemCount: _offers.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _buildOfferCard(_offers[index]),
                  ),
                ),
    );
  }

  Widget _buildOfferCard(Offer offer) {
    final listing = _listingsById[offer.listingId];
    final tx = _txByOffer[offer.id];
    final title = (listing?['title'] as String?) ?? 'Listing removed';
    final img = (listing?['image_url'] as String?)?.trim() ?? '';
    final busy =
        _busy.contains(offer.id) || (tx != null && _busy.contains(tx.id));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEDED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 52,
                  height: 52,
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
                    Text(
                      'You offered ${_formatPeso(offer.amount)}'
                      '${offer.quantity > 1 ? ' for ${offer.quantity} pcs' : ''}',
                      style: const TextStyle(
                          color: Color(0xFF6DBF99),
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusPill(offer, tx),
            ],
          ),
          // ── Row of contextual actions ────────────────────────────────
          if (_actionFor(offer, tx, busy) != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: _actionFor(offer, tx, busy)!,
            ),
          ],
        ],
      ),
    );
  }

  /// The one action that makes sense for this offer's state, or null.
  Widget? _actionFor(Offer offer, TransactionInfo? tx, bool busy) {
    if (busy) {
      return const SizedBox(
        width: 18,
        height: 18,
        child:
            CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6DBF99)),
      );
    }
    if (offer.status == 'pending') {
      return _pillButton('Withdraw offer', outline: true,
          color: Colors.red.shade400, onTap: () => _withdraw(offer));
    }
    if (tx != null && tx.isReserved) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text('Arrange the sale with the seller on Messenger.',
              style: TextStyle(fontSize: 11, color: Colors.black45)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _pillButton('Report a problem',
                  outline: true,
                  color: Colors.black45,
                  onTap: () => _reportProblem(offer, tx)),
              _pillButton('Cancel deal',
                  outline: true,
                  color: Colors.red.shade400,
                  onTap: () => _cancelDeal(tx)),
            ],
          ),
        ],
      );
    }
    if (tx != null && tx.awaitingBuyerConfirm) {
      // Seller says it's done — ask the buyer to confirm receipt.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text('Did you receive this order?',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFB28704))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _pillButton('Report a problem',
                  outline: true,
                  color: Colors.red.shade400,
                  onTap: () => _reportProblem(offer, tx)),
              _pillButton('Yes, I received it',
                  color: const Color(0xFF6DBF99),
                  onTap: () => _confirmReceived(tx)),
            ],
          ),
        ],
      );
    }
    if (tx != null && tx.status == 'completed') {
      return Wrap(
        spacing: 8,
        children: [
          _pillButton('Report a problem',
              outline: true,
              color: Colors.black45,
              onTap: () => _reportProblem(offer, tx)),
          _pillButton('Rate seller',
              color: const Color(0xFF6DBF99), onTap: () => _rateSeller(offer)),
        ],
      );
    }
    return null;
  }

  Widget _pillButton(String label,
      {required Color color, bool outline = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: outline ? Colors.white : color,
          border: outline ? Border.all(color: color) : null,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: outline ? color : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _statusPill(Offer offer, TransactionInfo? tx) {
    String label;
    Color bg;
    Color fg;
    if (tx != null && tx.isReserved) {
      label = 'Reserved for you';
      bg = const Color(0xFFFFF3E0);
      fg = const Color(0xFFE65100);
    } else if (tx != null && tx.awaitingBuyerConfirm) {
      label = 'Confirm receipt';
      bg = const Color(0xFFFFF8E1);
      fg = const Color(0xFFB28704);
    } else if (tx != null && tx.status == 'completed') {
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
    } else if (offer.status == 'declined') {
      label = 'Declined';
      bg = const Color(0xFFFDECEC);
      fg = Colors.red.shade400;
    } else {
      label = 'Pending';
      bg = const Color(0xFFFFF8E1);
      fg = const Color(0xFFB28704);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style:
              TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _thumbPlaceholder() => Container(
        color: const Color(0xFFD6F0E4),
        child: const Icon(Icons.image_not_supported_outlined,
            color: Colors.white54, size: 24),
      );
}
