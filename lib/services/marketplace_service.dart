import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestFilterBuilder;

import '../friendly_error.dart';
import '../main.dart';

/// A seller's reputation: review scores plus their real deal history
/// (completed sales and self-cancelled deals). Feeds the 0..100 trust score.
class SellerRating {
  final double average;
  final int count;

  /// Deals this user cancelled in the last 90 days (both roles) — recency
  /// signal for the behavioural penalty.
  final int recentCancellations;

  /// Deals this user completed as the seller (all time) — their sales record.
  final int completedSales;

  /// Deals where this user was the seller and they backed out (all time) —
  /// the reliability signal.
  final int cancelledAsSeller;

  const SellerRating({
    required this.average,
    required this.count,
    this.recentCancellations = 0,
    this.completedSales = 0,
    this.cancelledAsSeller = 0,
  });

  static const empty = SellerRating(average: 0, count: 0);

  bool get hasReviews => count > 0;

  /// Whether there's any reputation signal at all (reviews or deal history).
  /// Screens show "—" for trust when this is false.
  bool get hasTrustSignal =>
      count > 0 || completedSales > 0 || cancelledAsSeller > 0;

  /// A 0..100 trust score blending three weighted components, so a single
  /// glowing review can't read as fully trusted and proven sellers rank
  /// higher. All terms are bounded, so the result is always 0..100.
  ///
  ///  • Rating quality (50%) — the average star score, Bayesian-smoothed
  ///    toward an assumed-average prior so a handful of reviews carries less
  ///    weight than a large, consistent history.
  ///  • Sales experience (30%) — completed sales on a saturating curve
  ///    (diminishing returns: ~10 sales ≈ half credit).
  ///  • Reliability (20%) — the seller's completion rate (completed vs. their
  ///    own cancellations); neutral until they have any deals.
  ///
  /// Then a behavioural penalty subtracts for deals cancelled in the last 90
  /// days, so recent flakiness bites regardless of lifetime stats.
  int get trustPercent {
    // 1. Rating quality — Bayesian average (prior: 3.5★ worth 5 reviews).
    const priorMean = 3.5;
    const priorWeight = 5.0;
    final bayesAvg =
        (priorWeight * priorMean + average * count) / (priorWeight + count);
    final ratingScore = bayesAvg / 5 * 100;

    // 2. Sales experience — saturating (half-credit at 10 sales).
    const halfSat = 10.0;
    final salesScore = 100 * completedSales / (completedSales + halfSat);

    // 3. Reliability — completion rate as a seller; 70 (neutral) when unproven.
    final deals = completedSales + cancelledAsSeller;
    final reliabilityScore =
        deals == 0 ? 70.0 : 100 * completedSales / deals;

    var score =
        0.50 * ratingScore + 0.30 * salesScore + 0.20 * reliabilityScore;

    // Behavioural penalty: 4 pts per recent (90-day) cancellation, capped.
    final recent = recentCancellations > 5 ? 5 : recentCancellations;
    score -= 4.0 * recent;

    return score.round().clamp(0, 100);
  }
}

/// A user's deal-cancellation standing, from the cancellation_stats RPC.
class CancellationStats {
  /// Deals this user cancelled in the last 90 days.
  final int cancelled90d;

  /// Deals they completed (all time, either side — buyer or seller).
  final int completedTotal;

  /// Deals they completed specifically as the seller — their real sales
  /// record (excludes their own purchases).
  final int completedAsSeller;

  /// Deals where they were the seller and they cancelled — reliability signal.
  final int cancelledAsSeller;

  const CancellationStats({
    required this.cancelled90d,
    required this.completedTotal,
    this.completedAsSeller = 0,
    this.cancelledAsSeller = 0,
  });

  /// Enough repeat cancellations to warn the other party.
  bool get cancelsOften => cancelled90d >= 2;
}

/// A single seller review with the reviewer's display name.
class Review {
  final String id;
  final String reviewerId;
  final String reviewerName;
  final int rating;
  final String comment;
  final DateTime createdAt;

  /// When the reviewer last changed this review. Equal to [createdAt] on a
  /// brand-new review; later once they edit it.
  final DateTime updatedAt;

  const Review({
    required this.id,
    required this.reviewerId,
    required this.reviewerName,
    required this.rating,
    required this.comment,
    required this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  /// True when the review was edited after it was first posted. A few seconds'
  /// tolerance absorbs the small clock skew between the insert's server
  /// `created_at` default and the client-set `updated_at`.
  bool get edited => updatedAt.difference(createdAt).inSeconds > 5;
}

/// A buyer's price offer on a listing, with the buyer's display name joined
/// in for the seller's "Offers" dashboard section.
class Offer {
  final String id;
  final String listingId;
  final String sellerId;
  final String buyerId;
  final String buyerName;

  /// Buyer's profile picture URL ('' when they have none).
  final String buyerAvatar;
  final double amount;

  /// How many units the offer is for (the amount is the total price).
  final int quantity;

  /// Optional message from the buyer to the seller.
  final String note;
  final String status; // 'pending' | 'accepted' | 'declined'
  final DateTime createdAt;

  const Offer({
    required this.id,
    required this.listingId,
    this.sellerId = '',
    required this.buyerId,
    required this.buyerName,
    this.buyerAvatar = '',
    required this.amount,
    this.quantity = 1,
    this.note = '',
    required this.status,
    required this.createdAt,
  });
}

/// One deal record: created automatically when a seller accepts an offer
/// (status 'reserved'), then completed or cancelled via the RPCs.
class TransactionInfo {
  final String id;
  final String listingId;
  final String offerId;
  final String sellerId;
  final String buyerId;
  final int quantity;

  /// Total agreed price for [quantity] units.
  final double agreedPrice;
  final String status; // 'reserved' | 'completed' | 'cancelled'
  final DateTime createdAt;

  /// When the buyer confirmed receiving the order (null until they do;
  /// auto-set by the server 7 days after completion).
  final DateTime? buyerConfirmedAt;

  const TransactionInfo({
    required this.id,
    required this.listingId,
    required this.offerId,
    required this.sellerId,
    required this.buyerId,
    required this.quantity,
    required this.agreedPrice,
    required this.status,
    required this.createdAt,
    this.buyerConfirmedAt,
  });

  bool get isReserved => status == 'reserved';

  /// Seller marked it done but the buyer hasn't confirmed receipt yet.
  bool get awaitingBuyerConfirm =>
      status == 'completed' && buyerConfirmedAt == null;
}

/// A user the current user has blocked, for the "Blocked Sellers" list.
class BlockedUser {
  final String id;
  final String name;

  /// Profile picture URL ('' when they have none).
  final String avatarUrl;

  const BlockedUser({
    required this.id,
    required this.name,
    this.avatarUrl = '',
  });
}

/// Centralised Supabase access for the marketplace trust & safety features:
/// favorites, seller reviews, abuse reports, user blocks and buyer offers.
///
/// Every method is best-effort and swallows errors into sensible defaults so a
/// transient network/RLS failure never crashes a screen — callers can show a
/// message based on the boolean/empty results.
class MarketplaceService {
  MarketplaceService._();

  static String? get _uid => supabase.auth.currentUser?.id;

  // ── Favorites ─────────────────────────────────────────────────────────────

  /// The set of listing ids the current user has favourited.
  static Future<Set<String>> fetchFavoriteIds() async {
    final uid = _uid;
    if (uid == null) return <String>{};
    try {
      final rows = await supabase
          .from('favorites')
          .select('listing_id')
          .eq('user_id', uid);
      return (rows as List)
          .map((r) => '${(r as Map)['listing_id']}')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// Adds or removes a favourite. Returns the new favourited state, or the
  /// original [currentlyFavorited] value if the write failed.
  static Future<bool> toggleFavorite(
    String listingId, {
    required bool currentlyFavorited,
  }) async {
    final uid = _uid;
    if (uid == null || listingId.isEmpty) return currentlyFavorited;
    try {
      if (currentlyFavorited) {
        await supabase
            .from('favorites')
            .delete()
            .eq('user_id', uid)
            .eq('listing_id', listingId);
        return false;
      } else {
        await supabase.from('favorites').upsert({
          'user_id': uid,
          'listing_id': listingId,
        });
        return true;
      }
    } catch (_) {
      return currentlyFavorited;
    }
  }

  static Future<bool> isFavorited(String listingId) async {
    final uid = _uid;
    if (uid == null || listingId.isEmpty) return false;
    try {
      final row = await supabase
          .from('favorites')
          .select('listing_id')
          .eq('user_id', uid)
          .eq('listing_id', listingId)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  // ── Reviews ───────────────────────────────────────────────────────────────

  /// Average rating + count for a seller, with their recent cancellations
  /// folded in so [SellerRating.trustPercent] reflects standing.
  static Future<SellerRating> fetchSellerRating(String sellerId) async {
    if (sellerId.isEmpty) return SellerRating.empty;
    try {
      final rows =
          await supabase.from('reviews').select('rating').eq('seller_id', sellerId);
      final ratings = (rows as List)
          .map((r) => ((r as Map)['rating'] as num?)?.toDouble() ?? 0)
          .where((r) => r > 0)
          .toList();
      final stats = await fetchCancellationStats([sellerId]);
      final s = stats[sellerId];
      final cancels = s?.cancelled90d ?? 0;
      final sales = s?.completedAsSeller ?? 0;
      final sellerCancels = s?.cancelledAsSeller ?? 0;
      if (ratings.isEmpty) {
        return SellerRating(
          average: 0,
          count: 0,
          recentCancellations: cancels,
          completedSales: sales,
          cancelledAsSeller: sellerCancels,
        );
      }
      final avg = ratings.reduce((a, b) => a + b) / ratings.length;
      return SellerRating(
        average: avg,
        count: ratings.length,
        recentCancellations: cancels,
        completedSales: sales,
        cancelledAsSeller: sellerCancels,
      );
    } catch (_) {
      return SellerRating.empty;
    }
  }

  /// Deal-cancellation standing for a batch of users (max 100), keyed by
  /// user id. Empty map on failure.
  static Future<Map<String, CancellationStats>> fetchCancellationStats(
      List<String> userIds) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty || _uid == null) return const {};
    try {
      final rows = await supabase
          .rpc('cancellation_stats', params: {'p_users': ids});
      final result = <String, CancellationStats>{};
      for (final r in (rows as List)) {
        final m = r as Map<String, dynamic>;
        result['${m['user_id']}'] = CancellationStats(
          cancelled90d: (m['cancelled_90d'] as num?)?.toInt() ?? 0,
          completedTotal: (m['completed_total'] as num?)?.toInt() ?? 0,
          completedAsSeller: (m['completed_as_seller'] as num?)?.toInt() ?? 0,
          cancelledAsSeller: (m['cancelled_as_seller'] as num?)?.toInt() ?? 0,
        );
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// All reviews for a seller, newest first, with reviewer names joined in.
  ///
  /// Reviewer names are resolved with a second query instead of a PostgREST
  /// embed: `reviews`' foreign keys reference `auth.users` (not
  /// `public.users`), so an embed like `users:reviewer_id(name)` fails with
  /// PGRST200 ("no relationship found") and would silently empty the list.
  static Future<List<Review>> fetchReviews(String sellerId) async {
    if (sellerId.isEmpty) return const [];
    try {
      final rows = await supabase
          .from('reviews')
          .select('id, reviewer_id, rating, comment, created_at, updated_at')
          .eq('seller_id', sellerId)
          .order('created_at', ascending: false);
      final list =
          (rows as List).map((r) => r as Map<String, dynamic>).toList();

      final reviewerIds = list
          .map((r) => '${r['reviewer_id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final namesById = <String, String>{};
      if (reviewerIds.isNotEmpty) {
        try {
          final userRows = await supabase
              .from('public_profiles')
              .select('id, name')
              .inFilter('id', reviewerIds);
          for (final u in (userRows as List)) {
            final m = u as Map<String, dynamic>;
            namesById['${m['id']}'] = ((m['name'] as String?) ?? '').trim();
          }
        } catch (_) {
          // Names fall back to the placeholder below.
        }
      }

      return list.map((row) {
        final name = namesById['${row['reviewer_id']}'] ?? '';
        return Review(
          id: '${row['id']}',
          reviewerId: '${row['reviewer_id']}',
          reviewerName: name.isNotEmpty ? name : 'AniMart User',
          rating: (row['rating'] as num?)?.toInt() ?? 0,
          comment: (row['comment'] as String?)?.trim() ?? '',
          createdAt:
              DateTime.tryParse('${row['created_at']}')?.toLocal() ?? DateTime.now(),
          updatedAt: DateTime.tryParse('${row['updated_at']}')?.toLocal(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// The current user's existing review for [sellerId], if any.
  static Future<Review?> fetchMyReview(String sellerId) async {
    final uid = _uid;
    if (uid == null || sellerId.isEmpty) return null;
    try {
      final row = await supabase
          .from('reviews')
          .select('id, reviewer_id, rating, comment, created_at, updated_at')
          .eq('seller_id', sellerId)
          .eq('reviewer_id', uid)
          .maybeSingle();
      if (row == null) return null;
      return Review(
        id: '${row['id']}',
        reviewerId: '${row['reviewer_id']}',
        reviewerName: 'You',
        rating: (row['rating'] as num?)?.toInt() ?? 0,
        comment: (row['comment'] as String?)?.trim() ?? '',
        createdAt:
            DateTime.tryParse('${row['created_at']}')?.toLocal() ?? DateTime.now(),
        updatedAt: DateTime.tryParse('${row['updated_at']}')?.toLocal(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Inserts or updates the current user's review of a seller.
  /// Returns null on success, or an error message to show the user.
  static Future<String?> submitReview({
    required String sellerId,
    required int rating,
    required String comment,
  }) async {
    final uid = _uid;
    if (uid == null) return 'You must be signed in to leave a review.';
    if (sellerId.isEmpty) return 'Unknown seller.';
    if (sellerId == uid) return 'You cannot review yourself.';
    if (rating < 1 || rating > 5) return 'Please choose a star rating.';
    try {
      await supabase.from('reviews').upsert({
        'seller_id': sellerId,
        'reviewer_id': uid,
        'rating': rating,
        'comment': comment.trim().isEmpty ? null : comment.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'seller_id,reviewer_id');
      return null;
    } catch (e) {
      return friendlyError(e,
          action: 'submit_review',
          fallback: 'Could not send your review. Please try again.');
    }
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  /// Files an abuse report against a listing, a seller, or a transaction
  /// ("Report a problem" on a deal — pass [transactionId] so the report
  /// carries the deal context). Returns null on success, or an error message.
  static Future<String?> submitReport({
    required String targetType, // 'listing' | 'seller' | 'transaction'
    String? listingId,
    String? sellerId,
    String? transactionId,
    required String reason,
    String details = '',
  }) async {
    final uid = _uid;
    if (uid == null) return 'You must be signed in to report.';
    try {
      await supabase.from('reports').insert({
        'reporter_id': uid,
        'target_type': targetType,
        'listing_id': listingId,
        'seller_id': (sellerId != null && sellerId.isNotEmpty) ? sellerId : null,
        'transaction_id':
            (transactionId != null && transactionId.isNotEmpty)
                ? transactionId
                : null,
        'reason': reason,
        'details': details.trim().isEmpty ? null : details.trim(),
      });
      return null;
    } catch (e) {
      // Server-side guards (e.g. the daily report rate limit) raise clean,
      // user-facing sentences; friendlyError passes those through and hides
      // anything technical behind the fallback.
      return friendlyError(e,
          action: 'submit_report',
          fallback: 'Could not send your report. Please try again.');
    }
  }

  // ── Offers ────────────────────────────────────────────────────────────────

  /// Submits (or revises) the current user's offer on a listing.
  /// Returns null on success, or an error message to show the user.
  static Future<String?> submitOffer({
    required String listingId,
    required String sellerId,
    required double amount,
    int quantity = 1,
    String note = '',
  }) async {
    final uid = _uid;
    if (uid == null) return 'You must be signed in to make an offer.';
    if (listingId.isEmpty || sellerId.isEmpty) {
      return 'Offers are unavailable for this listing.';
    }
    if (sellerId == uid) return 'You cannot make an offer on your own listing.';
    if (amount <= 0) return 'Please enter a valid offer amount.';
    if (quantity < 1) return 'Please enter a valid quantity.';
    try {
      // A buyer can buy the same listing again over its lifetime, so each
      // purchase is its own offer row. NEVER reuse a row that already has a
      // deal attached (status 'accepted') — a second acceptance would bind two
      // transactions to one offer and the app's offer→deal mapping would
      // collapse. Reuse only a still-open row (pending/declined never have a
      // transaction) to revise it; otherwise insert a fresh offer.
      final payload = {
        'amount': amount,
        'quantity': quantity,
        'note': note.trim().isEmpty ? null : note.trim(),
        'status': 'pending',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final existing = await supabase
          .from('offers')
          .select('id')
          .eq('listing_id', listingId)
          .eq('buyer_id', uid)
          .inFilter('status', ['pending', 'declined'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        await supabase.from('offers').update(payload).eq('id', existing['id']);
      } else {
        await supabase.from('offers').insert({
          'listing_id': listingId,
          'seller_id': sellerId,
          'buyer_id': uid,
          ...payload,
        });
      }
      return null;
    } catch (e) {
      // Server-side guards (offer rate limit, listing-not-active) raise
      // clean, user-facing sentences; friendlyError passes those through.
      return friendlyError(e,
          action: 'submit_offer',
          fallback: 'Could not send your offer. Please try again.');
    }
  }

  /// All offers the current user has made (as a buyer), newest first.
  static Future<List<Offer>> fetchSentOffers() async {
    final uid = _uid;
    if (uid == null) return const [];
    return _fetchOffers((q) => q.eq('buyer_id', uid));
  }

  /// Buyer withdraws their own pending offer. Returns null on success.
  static Future<String?> withdrawOffer(String offerId) async {
    final uid = _uid;
    if (uid == null) return 'You must be signed in.';
    if (offerId.isEmpty) return 'Unknown offer.';
    try {
      await supabase
          .from('offers')
          .delete()
          .eq('id', offerId)
          .eq('buyer_id', uid)
          .eq('status', 'pending');
      return null;
    } catch (e) {
      return friendlyError(e,
          action: 'withdraw_offer',
          fallback: 'Could not withdraw your offer. Please try again.');
    }
  }

  /// All offers received by the current user (as a seller), newest first.
  static Future<List<Offer>> fetchReceivedOffers() async {
    final uid = _uid;
    if (uid == null) return const [];
    return _fetchOffers((q) => q.eq('seller_id', uid));
  }

  /// All offers on one listing. RLS already limits the rows to ones the
  /// caller is involved in, so on the owner's own listing this is every
  /// offer made on that post.
  static Future<List<Offer>> fetchListingOffers(String listingId) async {
    if (_uid == null || listingId.isEmpty) return const [];
    return _fetchOffers((q) => q.eq('listing_id', listingId));
  }

  /// Shared offers query with buyer names/avatars joined in via a second
  /// `users` query (the offers FKs reference auth.users, so a PostgREST
  /// embed is not possible — same approach as [fetchReviews]).
  static Future<List<Offer>> _fetchOffers(
    PostgrestFilterBuilder<List<Map<String, dynamic>>> Function(
            PostgrestFilterBuilder<List<Map<String, dynamic>>>)
        filter,
  ) async {
    try {
      final rows = await filter(supabase.from('offers').select(
              'id, listing_id, seller_id, buyer_id, amount, quantity, note, status, created_at'))
          .order('created_at', ascending: false);
      final list = rows.map((r) => Map<String, dynamic>.from(r)).toList();

      final buyerIds = list
          .map((r) => '${r['buyer_id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final namesById = <String, String>{};
      final avatarsById = <String, String>{};
      if (buyerIds.isNotEmpty) {
        try {
          final userRows = await supabase
              .from('public_profiles')
              .select('id, name, avatar_url')
              .inFilter('id', buyerIds);
          for (final u in (userRows as List)) {
            final m = u as Map<String, dynamic>;
            namesById['${m['id']}'] = ((m['name'] as String?) ?? '').trim();
            avatarsById['${m['id']}'] =
                ((m['avatar_url'] as String?) ?? '').trim();
          }
        } catch (_) {
          // Names fall back to the placeholder below.
        }
      }

      return list.map((row) {
        final name = namesById['${row['buyer_id']}'] ?? '';
        return Offer(
          id: '${row['id']}',
          listingId: '${row['listing_id']}',
          sellerId: '${row['seller_id'] ?? ''}',
          buyerId: '${row['buyer_id']}',
          buyerName: name.isNotEmpty ? name : 'AniMart User',
          buyerAvatar: avatarsById['${row['buyer_id']}'] ?? '',
          amount: (row['amount'] as num?)?.toDouble() ?? 0,
          quantity: (row['quantity'] as num?)?.toInt() ?? 1,
          note: (row['note'] as String?)?.trim() ?? '',
          status: (row['status'] as String?) ?? 'pending',
          createdAt: DateTime.tryParse('${row['created_at']}')?.toLocal() ??
              DateTime.now(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  // ── Transactions ──────────────────────────────────────────────────────────

  /// The current user's deals — as the seller when [asSeller], else as the
  /// buyer. Newest first.
  static Future<List<TransactionInfo>> fetchTransactions(
      {required bool asSeller}) async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final rows = await supabase
          .from('transactions')
          .select()
          .eq(asSeller ? 'seller_id' : 'buyer_id', uid)
          .order('created_at', ascending: false);
      return (rows as List).map((r) {
        final row = r as Map<String, dynamic>;
        return TransactionInfo(
          id: '${row['id']}',
          listingId: '${row['listing_id']}',
          offerId: '${row['offer_id'] ?? ''}',
          sellerId: '${row['seller_id']}',
          buyerId: '${row['buyer_id']}',
          quantity: (row['quantity'] as num?)?.toInt() ?? 1,
          agreedPrice: (row['agreed_price'] as num?)?.toDouble() ?? 0,
          status: (row['status'] as String?) ?? 'reserved',
          createdAt: DateTime.tryParse('${row['created_at']}')?.toLocal() ??
              DateTime.now(),
          buyerConfirmedAt: row['buyer_confirmed_at'] == null
              ? null
              : DateTime.tryParse('${row['buyer_confirmed_at']}')?.toLocal(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Buyer confirms they received a completed deal ("Did you receive it?").
  /// Returns null on success.
  static Future<String?> confirmTransactionReceived(String txId) async {
    try {
      final result = await supabase
          .rpc('confirm_transaction_received', params: {'p_tx': txId});
      return result as String?;
    } catch (e) {
      return friendlyError(e,
          action: 'confirm_transaction_received',
          fallback: 'Could not confirm the item. Please try again.');
    }
  }

  /// Seller marks a reserved deal as done (decrements stock; the listing
  /// auto-relists or goes to 'sold'). Returns null on success.
  static Future<String?> completeTransaction(String txId) async {
    try {
      final result = await supabase
          .rpc('complete_transaction', params: {'p_tx': txId});
      return result as String?;
    } catch (e) {
      return friendlyError(e,
          action: 'complete_transaction',
          fallback: 'Could not finish this deal. Please try again.');
    }
  }

  /// Either party cancels a reserved deal (the listing goes back online).
  /// Returns null on success.
  static Future<String?> cancelTransaction(String txId,
      {String reason = ''}) async {
    try {
      final result = await supabase.rpc('cancel_transaction', params: {
        'p_tx': txId,
        'p_reason': reason.trim().isEmpty ? null : reason.trim(),
      });
      return result as String?;
    } catch (e) {
      return friendlyError(e,
          action: 'cancel_transaction',
          fallback: 'Could not cancel this deal. Please try again.');
    }
  }

  /// Whether the current user may review [sellerId] — true only after a
  /// completed purchase from them (mirrors the reviews RLS policy).
  static Future<bool> canReviewSeller(String sellerId) async {
    final uid = _uid;
    if (uid == null || sellerId.isEmpty || sellerId == uid) return false;
    try {
      final rows = await supabase
          .from('transactions')
          .select('id')
          .eq('buyer_id', uid)
          .eq('seller_id', sellerId)
          .eq('status', 'completed')
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Number of completed sales the current user has made as a seller.
  static Future<int> completedSalesCount() async {
    final uid = _uid;
    if (uid == null) return 0;
    try {
      final rows = await supabase
          .from('transactions')
          .select('id')
          .eq('seller_id', uid)
          .eq('status', 'completed');
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// Seller accepts or declines an offer. Returns null on success, or an
  /// error message.
  static Future<String?> respondToOffer(
    String offerId, {
    required bool accept,
  }) async {
    final uid = _uid;
    if (uid == null) return 'You must be signed in.';
    if (offerId.isEmpty) return 'Unknown offer.';
    try {
      await supabase
          .from('offers')
          .update({
            'status': accept ? 'accepted' : 'declined',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', offerId)
          .eq('seller_id', uid);
      return null;
    } catch (e) {
      // The reserve trigger raises a readable message when a listing has no
      // stock left to reserve — friendlyError surfaces that as-is.
      return friendlyError(e,
          action: 'respond_to_offer',
          fallback: 'Could not update this offer. Please try again.');
    }
  }

  // ── Blocks ────────────────────────────────────────────────────────────────

  /// The set of user ids the current user has blocked.
  static Future<Set<String>> fetchBlockedIds() async {
    final uid = _uid;
    if (uid == null) return <String>{};
    try {
      final rows = await supabase
          .from('user_blocks')
          .select('blocked_id')
          .eq('blocker_id', uid);
      return (rows as List)
          .map((r) => '${(r as Map)['blocked_id']}')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// The users the current user has blocked, with their display name and
  /// avatar, for the profile page's "Blocked Sellers" list.
  static Future<List<BlockedUser>> fetchBlockedUsers() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final ids = (await fetchBlockedIds()).toList();
      if (ids.isEmpty) return const [];
      // auth.users FKs can't embed, so resolve the profiles separately.
      final rows = await supabase
          .from('public_profiles')
          .select('id, name, avatar_url')
          .inFilter('id', ids);
      final byId = <String, Map<String, dynamic>>{
        for (final r in (rows as List))
          '${(r as Map)['id']}': r as Map<String, dynamic>,
      };
      return ids.map((id) {
        final row = byId[id];
        final name = (row?['name'] as String?)?.trim() ?? '';
        return BlockedUser(
          id: id,
          name: name.isNotEmpty ? name : 'AniMart User',
          avatarUrl: (row?['avatar_url'] as String?)?.trim() ?? '',
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> isBlocked(String userId) async {
    final uid = _uid;
    if (uid == null || userId.isEmpty) return false;
    try {
      final row = await supabase
          .from('user_blocks')
          .select('blocked_id')
          .eq('blocker_id', uid)
          .eq('blocked_id', userId)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  /// Blocks or unblocks a user. Returns the new blocked state, or the original
  /// [currentlyBlocked] value if the write failed.
  static Future<bool> toggleBlock(
    String userId, {
    required bool currentlyBlocked,
  }) async {
    final uid = _uid;
    if (uid == null || userId.isEmpty || userId == uid) return currentlyBlocked;
    try {
      if (currentlyBlocked) {
        await supabase
            .from('user_blocks')
            .delete()
            .eq('blocker_id', uid)
            .eq('blocked_id', userId);
        return false;
      } else {
        await supabase.from('user_blocks').upsert({
          'blocker_id': uid,
          'blocked_id': userId,
        });
        return true;
      }
    } catch (_) {
      return currentlyBlocked;
    }
  }
}
