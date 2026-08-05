import 'package:flutter/material.dart';

import 'main.dart';
import 'services/marketplace_service.dart';
import 'widgets/top_message.dart';

/// Full-screen list of a seller's reviews, with a form for the signed-in user
/// to leave or update their own rating.
class SellerReviewsPage extends StatefulWidget {
  final String sellerId;
  final String sellerName;

  const SellerReviewsPage({
    super.key,
    required this.sellerId,
    required this.sellerName,
  });

  @override
  State<SellerReviewsPage> createState() => _SellerReviewsPageState();
}

class _SellerReviewsPageState extends State<SellerReviewsPage> {
  static const Color _green = Color(0xFF1D9E75);
  static const Color _amber = Color(0xFFFFB300);

  SellerRating _rating = SellerRating.empty;
  List<Review> _reviews = const [];
  Review? _myReview;
  bool _loading = true;
  bool _submitting = false;

  /// Reviews are verified-purchase only: true once the signed-in user has a
  /// completed transaction with this seller (mirrors the reviews RLS).
  bool _canReview = false;

  /// First image of the seller's most recent listing, shown in the summary
  /// card so the reviews have a visual anchor to what the seller sells.
  String _listingImage = '';

  bool get _isOwnProfile =>
      supabase.auth.currentUser?.id == widget.sellerId;

  @override
  void initState() {
    super.initState();
    _load();
    _loadListingImage();
  }

  /// Loads the first image of the seller's most recent listing (active or
  /// sold), for the summary card thumbnail.
  Future<void> _loadListingImage() async {
    if (widget.sellerId.isEmpty) return;
    try {
      final rows = await supabase
          .from('listings')
          .select('image_url, image_urls, created_at')
          .eq('seller_id', widget.sellerId)
          .inFilter('status', ['active', 'sold'])
          .order('created_at', ascending: false)
          .limit(1);
      final list = rows as List;
      if (list.isEmpty) return;
      final row = list.first as Map<String, dynamic>;
      var img = (row['image_url'] as String?)?.trim() ?? '';
      if (img.isEmpty) {
        final imgs = (row['image_urls'] as List?)
                ?.map((e) => '$e')
                .where((e) => e.trim().isNotEmpty)
                .toList() ??
            const <String>[];
        if (imgs.isNotEmpty) img = imgs.first;
      }
      if (!mounted || img.isEmpty) return;
      setState(() => _listingImage = img);
    } catch (_) {
      // No thumbnail — the card just renders without it.
    }
  }

  Future<void> _load() async {
    final results = await Future.wait([
      MarketplaceService.fetchSellerRating(widget.sellerId),
      MarketplaceService.fetchReviews(widget.sellerId),
      MarketplaceService.fetchMyReview(widget.sellerId),
      MarketplaceService.canReviewSeller(widget.sellerId),
    ]);
    if (!mounted) return;
    setState(() {
      _rating = results[0] as SellerRating;
      _reviews = results[1] as List<Review>;
      _myReview = results[2] as Review?;
      _canReview = results[3] as bool;
      _loading = false;
    });
  }

  Future<void> _openReviewForm() async {
    if (!_canReview && _myReview == null) {
      showTopMessage(
        context,
        'Reviews are for verified buyers — you can rate '
        '${widget.sellerName} after a completed purchase from them.',
      );
      return;
    }
    int stars = _myReview?.rating ?? 0;
    final commentCtrl =
        TextEditingController(text: _myReview?.comment ?? '');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _myReview == null
                      ? 'Rate ${widget.sellerName}'
                      : 'Update your review',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A2E22)),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    return GestureDetector(
                      onTap: () => setSheet(() => stars = i + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          i < stars
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 40,
                          color: _amber,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: commentCtrl,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Share your experience (optional)',
                    hintStyle:
                        const TextStyle(color: Colors.black38, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFF4FAF7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: stars == 0 || _submitting
                        ? null
                        : () => _submit(ctx, stars, commentCtrl.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.black12,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: Text(
                      _myReview == null ? 'Submit Review' : 'Update Review',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext sheetCtx, int stars, String comment) async {
    setState(() => _submitting = true);
    final error = await MarketplaceService.submitReview(
      sellerId: widget.sellerId,
      rating: stars,
      comment: comment,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (error != null) {
      showTopMessage(context, error);
      return;
    }
    Navigator.pop(sheetCtx);
    showTopMessage(context, 'Thanks for your review!',
        isError: false, backgroundColor: _green);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAF7),
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${widget.sellerName} · Reviews'),
      ),
      // Only buyers who completed a purchase from this seller (or who already
      // left one) can review — otherwise the button is hidden entirely instead
      // of showing then rejecting them. Enforced server-side by the reviews
      // RLS too; this just keeps the UI honest.
      floatingActionButton: (_isOwnProfile ||
              _loading ||
              (!_canReview && _myReview == null))
          ? null
          : FloatingActionButton.extended(
              onPressed: _openReviewForm,
              backgroundColor: _green,
              icon: Icon(_myReview == null ? Icons.rate_review : Icons.edit),
              label: Text(_myReview == null ? 'Write a review' : 'Edit review'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : RefreshIndicator(
              color: _green,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  _summaryCard(),
                  const SizedBox(height: 16),
                  if (_reviews.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          Icon(Icons.reviews_outlined,
                              size: 52, color: Colors.black26),
                          SizedBox(height: 12),
                          Text('No reviews yet',
                              style: TextStyle(
                                  color: Colors.black45, fontSize: 14)),
                        ],
                      ),
                    )
                  else
                    ..._reviews.map(_reviewTile),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7F0EB)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                _rating.hasReviews ? _rating.average.toStringAsFixed(1) : '—',
                style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A2E22)),
              ),
              _starRow(_rating.average, size: 16),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _rating.hasReviews
                      ? '${_rating.count} review${_rating.count == 1 ? '' : 's'}'
                      : 'Be the first to review',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A2E22)),
                ),
                const SizedBox(height: 4),
                Text(
                  _rating.hasReviews
                      ? 'Trust score ${_rating.trustPercent}%'
                      : 'Ratings build seller trust',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          if (_listingImage.isNotEmpty) ...[
            const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                _listingImage,
                width: 104,
                height: 66,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 104,
                  height: 66,
                  color: const Color(0xFFD6F0E4),
                  child: const Icon(Icons.image_not_supported_outlined,
                      color: Colors.white70, size: 24),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reviewTile(Review r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEF4F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFD6F0E4),
                child: Text(
                  r.reviewerName.isNotEmpty
                      ? r.reviewerName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: _green, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.reviewerName,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    _starRow(r.rating.toDouble(), size: 13),
                  ],
                ),
              ),
              Text(_timeAgo(r.createdAt),
                  style:
                      const TextStyle(fontSize: 11, color: Colors.black38)),
            ],
          ),
          if (r.comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(r.comment,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF3D5247), height: 1.4)),
          ],
          if (r.edited) ...[
            const SizedBox(height: 6),
            const Text('Edited',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.black38,
                    fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  Widget _starRow(double value, {double size = 14}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < value.round();
        return Icon(
          filled ? Icons.star_rounded : Icons.star_border_rounded,
          size: size,
          color: _amber,
        );
      }),
    );
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inDays > 30) return '${(d.inDays / 30).floor()}mo ago';
    if (d.inDays > 0) return '${d.inDays}d ago';
    if (d.inHours > 0) return '${d.inHours}h ago';
    if (d.inMinutes > 0) return '${d.inMinutes}m ago';
    return 'just now';
  }
}
