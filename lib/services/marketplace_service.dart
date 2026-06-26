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

/// Centralised Supabase access for the marketplace trust & safety features:
/// favorites, seller reviews, abuse reports and user blocks.
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
  static Future<List<Review>> fetchReviews(String sellerId) async {
    if (sellerId.isEmpty) return const [];
    try {
      final rows = await supabase
          .from('reviews')
          .select('id, reviewer_id, rating, comment, created_at, users:reviewer_id(name)')
          .eq('seller_id', sellerId)
          .order('created_at', ascending: false);
      return (rows as List).map((r) {
        final row = r as Map<String, dynamic>;
        final reviewer = row['users'] as Map<String, dynamic>?;
        return Review(
          id: '${row['id']}',
          reviewerId: '${row['reviewer_id']}',
          reviewerName: (reviewer?['name'] as String?)?.trim().isNotEmpty == true
              ? (reviewer!['name'] as String).trim()
              : 'AniMart User',
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
