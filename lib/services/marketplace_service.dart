import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestFilterBuilder;

import '../main.dart';

/// Aggregate rating for a seller (average stars + number of reviews).
class SellerRating {
  final double average;
  final int count;

  const SellerRating({required this.average, required this.count});

  static const empty = SellerRating(average: 0, count: 0);

  bool get hasReviews => count > 0;

  /// Average mapped onto a 0..100 "trust" percentage (5★ => 100%).
  int get trustPercent => (average / 5 * 100).round();
}

/// A single seller review with the reviewer's display name.
class Review {
  final String id;
  final String reviewerId;
  final String reviewerName;
  final int rating;
  final String comment;
  final DateTime createdAt;

  const Review({
    required this.id,
    required this.reviewerId,
    required this.reviewerName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });
}

/// A buyer's price offer on a listing, with the buyer's display name joined
/// in for the seller's "Offers" dashboard section.
class Offer {
  final String id;
  final String listingId;
  final String buyerId;
  final String buyerName;

  /// Buyer's profile picture URL ('' when they have none).
  final String buyerAvatar;
  final double amount;
  final String status; // 'pending' | 'accepted' | 'declined'
  final DateTime createdAt;

  const Offer({
    required this.id,
    required this.listingId,
    required this.buyerId,
    required this.buyerName,
    this.buyerAvatar = '',
    required this.amount,
    required this.status,
    required this.createdAt,
  });
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

  /// Average rating + count for a seller.
  static Future<SellerRating> fetchSellerRating(String sellerId) async {
    if (sellerId.isEmpty) return SellerRating.empty;
    try {
      final rows =
          await supabase.from('reviews').select('rating').eq('seller_id', sellerId);
      final ratings = (rows as List)
          .map((r) => ((r as Map)['rating'] as num?)?.toDouble() ?? 0)
          .where((r) => r > 0)
          .toList();
      if (ratings.isEmpty) return SellerRating.empty;
      final avg = ratings.reduce((a, b) => a + b) / ratings.length;
      return SellerRating(average: avg, count: ratings.length);
    } catch (_) {
      return SellerRating.empty;
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
          .select('id, reviewer_id, rating, comment, created_at')
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
              .from('users')
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
          .select('id, reviewer_id, rating, comment, created_at')
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
      return 'Could not submit review: $e';
    }
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  /// Files an abuse report against a listing or a seller.
  /// Returns null on success, or an error message.
  static Future<String?> submitReport({
    required String targetType, // 'listing' | 'seller'
    String? listingId,
    String? sellerId,
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
        'reason': reason,
        'details': details.trim().isEmpty ? null : details.trim(),
      });
      return null;
    } catch (e) {
      return 'Could not submit report: $e';
    }
  }

  // ── Offers ────────────────────────────────────────────────────────────────

  /// Submits (or revises) the current user's offer on a listing.
  /// Returns null on success, or an error message to show the user.
  static Future<String?> submitOffer({
    required String listingId,
    required String sellerId,
    required double amount,
  }) async {
    final uid = _uid;
    if (uid == null) return 'You must be signed in to make an offer.';
    if (listingId.isEmpty || sellerId.isEmpty) {
      return 'Offers are unavailable for this listing.';
    }
    if (sellerId == uid) return 'You cannot make an offer on your own listing.';
    if (amount <= 0) return 'Please enter a valid offer amount.';
    try {
      // Re-offering replaces the previous offer and resets it to pending so
      // the seller sees the latest amount.
      await supabase.from('offers').upsert({
        'listing_id': listingId,
        'seller_id': sellerId,
        'buyer_id': uid,
        'amount': amount,
        'status': 'pending',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'listing_id,buyer_id');
      return null;
    } catch (e) {
      return 'Could not send offer: $e';
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
      final rows = await filter(supabase
              .from('offers')
              .select('id, listing_id, buyer_id, amount, status, created_at'))
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
              .from('users')
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
          buyerId: '${row['buyer_id']}',
          buyerName: name.isNotEmpty ? name : 'AniMart User',
          buyerAvatar: avatarsById['${row['buyer_id']}'] ?? '',
          amount: (row['amount'] as num?)?.toDouble() ?? 0,
          status: (row['status'] as String?) ?? 'pending',
          createdAt: DateTime.tryParse('${row['created_at']}')?.toLocal() ??
              DateTime.now(),
        );
      }).toList();
    } catch (_) {
      return const [];
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
      return 'Could not update offer: $e';
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
          .from('users')
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
