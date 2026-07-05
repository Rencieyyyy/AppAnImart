import 'package:flutter/foundation.dart';

import '../main.dart';

/// Red-dot notification badges.
///
/// Both indicators are watermark based: the user's `users` row stores when
/// they last opened the Announcements page (`announcements_seen_at`) and the
/// seller Offers page (`offers_seen_at`). Anything newer than the watermark
/// shows a red dot; opening the page stamps the watermark and clears it.
/// Every method is best-effort — a network/RLS failure simply means no dot.
class NotificationService {
  NotificationService._();

  static String? get _uid => supabase.auth.currentUser?.id;

  static Future<DateTime?> _seenAt(String column) async {
    final uid = _uid;
    if (uid == null) return null;
    final row = await supabase
        .from('users')
        .select(column)
        .eq('id', uid)
        .maybeSingle();
    return DateTime.tryParse('${row?[column]}');
  }

  static Future<void> _markSeen(String column) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await supabase.from('users').update(
          {column: DateTime.now().toUtc().toIso8601String()}).eq('id', uid);
    } catch (e) {
      debugPrint('Failed to stamp $column: $e');
    }
  }

  // ── Announcements ─────────────────────────────────────────────────────────

  /// True when an announcement visible to this user (the public feed plus
  /// ones addressed to them, e.g. offer notifications) was posted after they
  /// last opened the Announcements page.
  static Future<bool> hasUnseenAnnouncements() async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final seenAt = await _seenAt('announcements_seen_at');

      // Newest first; drafts/pending are not shown in the app, so skip them
      // here too. A handful of rows is plenty to find the newest visible one.
      final rows = await supabase
          .from('announcements')
          .select('created_at, status')
          .isFilter('deleted_at', null)
          .or('recipient_id.is.null,recipient_id.eq.$uid')
          .order('created_at', ascending: false)
          .limit(20);
      for (final r in (rows as List)) {
        final m = r as Map<String, dynamic>;
        final status = ((m['status'] as String?) ?? '').toLowerCase();
        if (status == 'draft' || status == 'pending') continue;
        final createdAt = DateTime.tryParse('${m['created_at']}');
        if (createdAt == null) continue;
        return seenAt == null || createdAt.isAfter(seenAt);
      }
      return false;
    } catch (e) {
      debugPrint('hasUnseenAnnouncements failed: $e');
      return false;
    }
  }

  /// Stamps the announcements watermark (called when the page opens).
  static Future<void> markAnnouncementsSeen() =>
      _markSeen('announcements_seen_at');

  // ── Offers ────────────────────────────────────────────────────────────────

  /// True when the current user (as a seller) has a pending offer that
  /// arrived — or was revised — after they last opened the Offers page.
  static Future<bool> hasNewOffers() async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final seenAt = await _seenAt('offers_seen_at');
      var query = supabase
          .from('offers')
          .select('id')
          .eq('seller_id', uid)
          .eq('status', 'pending');
      if (seenAt != null) {
        // updated_at (not created_at) so a buyer revising their offer counts
        // as new again.
        query = query.gt('updated_at', seenAt.toUtc().toIso8601String());
      }
      final rows = await query.limit(1);
      return (rows as List).isNotEmpty;
    } catch (e) {
      debugPrint('hasNewOffers failed: $e');
      return false;
    }
  }

  /// Stamps the offers watermark (called when the Offers page opens).
  static Future<void> markOffersSeen() => _markSeen('offers_seen_at');
}
