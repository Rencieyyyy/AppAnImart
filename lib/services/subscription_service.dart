import '../main.dart';

/// One purchasable plan as shown in the AniMart app.
///
/// The app and the admin website now share the same three plan names —
/// "Free", "Premium", and "Super Premium" — and that exact [label] is what
/// gets written to `subscriptions.plan`. There is no separate Basic tier and
/// no key-mapping layer anymore.
class AppPlan {
  /// App-facing id used inside the Flutter UI.
  final String id; // 'free' | 'premium' | 'superpremium'

  /// Display name shown to the user AND stored in `subscriptions.plan`.
  final String label; // 'Free' | 'Premium' | 'Super Premium'

  /// Short marketing description shown under the label.
  final String description;

  /// Monthly price in ₱.
  final int price;

  const AppPlan({
    required this.id,
    required this.label,
    required this.description,
    required this.price,
  });

  bool get isFree => price == 0;

  /// e.g. "₱699 / mo" (or "₱0 / mo" for the free tier).
  String get priceLabel => '₱$price / mo';
}

/// Reads and writes the `subscriptions` table that the admin website manages.
class SubscriptionService {
  SubscriptionService._();

  /// The plans offered in-app, in display order. The [label] is the value
  /// stored in `subscriptions.plan`.
  static const List<AppPlan> plans = [
    AppPlan(
      id: 'free',
      label: 'Free',
      description: 'Basic browsing, view listings',
      price: 0,
    ),
    AppPlan(
      id: 'premium',
      label: 'Premium',
      description: 'Post listings, buyer messaging',
      price: 699,
    ),
    AppPlan(
      id: 'superpremium',
      label: 'Super Premium',
      description: 'All features + priority support',
      price: 1299,
    ),
  ];

  /// Looks up an [AppPlan] by its app-facing [id], defaulting to Free.
  static AppPlan planById(String id) =>
      plans.firstWhere((p) => p.id == id, orElse: () => plans.first);

  /// Normalises a `subscriptions.plan` value to the app-facing label.
  ///
  /// New rows already store the label ('Free'/'Premium'/'Super Premium'). This
  /// also folds any legacy keys ('free'/'basic'/'pro'/'elite') onto the new
  /// names so old, un-migrated rows still display correctly.
  static String labelForDbPlan(String? dbPlan) {
    final key = (dbPlan ?? '').toLowerCase().trim();
    switch (key) {
      case '':
      case 'free':
        return 'Free';
      case 'basic': // Basic is retired — fold into Premium.
      case 'pro':
      case 'premium':
        return 'Premium';
      case 'elite':
      case 'super premium':
        return 'Super Premium';
      default:
        // Unknown value: title-case it so it's still readable.
        return key[0].toUpperCase() + key.substring(1);
    }
  }

  /// Subscription statuses that count as a live, paid plan. The admin website
  /// marks an approved request as `'approved'`; `'active'` is kept for any
  /// legacy rows. Anything else (pending / expired / rejected) is treated as
  /// Free.
  static const Set<String> _activeStatuses = {'approved', 'active'};

  /// The app-facing label of the user's currently *active* plan, or 'Free' if
  /// they have no live subscription. A row counts only when its status is
  /// approved/active AND it hasn't passed its `expires_at`.
  static Future<String> activePlanLabel() async {
    final user = supabase.auth.currentUser;
    if (user == null) return 'Free';
    try {
      // Fetch the user's rows and resolve the active one client-side. This is
      // robust to multiple approved rows and avoids depending on the exact
      // status string the admin writes.
      final rows = await supabase
          .from('subscriptions')
          .select('plan, status, expires_at, started_at')
          .eq('user_id', user.id)
          .order('started_at', ascending: false);

      final now = DateTime.now().toUtc();
      for (final row in (rows as List)) {
        final r = row as Map<String, dynamic>;
        final status = (r['status'] as String?)?.toLowerCase().trim() ?? '';
        if (!_activeStatuses.contains(status)) continue;
        final expires = DateTime.tryParse('${r['expires_at']}')?.toUtc();
        if (expires != null && !expires.isAfter(now)) continue; // expired
        return labelForDbPlan(r['plan'] as String?);
      }
      return 'Free';
    } catch (_) {
      return 'Free';
    }
  }

  /// The signed-in user's most recent subscription row, or null if none /
  /// not signed in / unreadable.
  static Future<Map<String, dynamic>?> currentSubscription() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    try {
      return await supabase
          .from('subscriptions')
          .select()
          .eq('user_id', user.id)
          .order('requested_at', ascending: false)
          .limit(1)
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }

  /// Whether the user already has a request awaiting admin approval.
  static Future<bool> hasPendingRequest() async {
    final sub = await currentSubscription();
    return sub != null && '${sub['status']}' == 'pending';
  }

  /// Submits a premium request for [plan].
  ///
  /// Returns `null` on success, or a user-facing error message. Selecting the
  /// free plan is a no-op (it needs no admin approval). The inserted row lands
  /// in the admin website's pending queue with `status = 'pending'`.
  static Future<String?> requestPlan(AppPlan plan) async {
    final user = supabase.auth.currentUser;
    if (user == null) return 'You must be signed in to choose a plan.';
    if (plan.isFree) return null; // free tier needs no approval

    try {
      // Don't stack duplicate pending requests for the same user.
      final existing = await supabase
          .from('subscriptions')
          .select('id')
          .eq('user_id', user.id)
          .eq('status', 'pending')
          .maybeSingle();
      if (existing != null) {
        return 'You already have a request awaiting admin approval.';
      }

      await supabase.from('subscriptions').insert({
        'user_id': user.id,
        'plan': plan.label,
        'price': plan.price,
        'status': 'pending',
        'requested_at': DateTime.now().toUtc().toIso8601String(),
      });
      return null;
    } catch (e) {
      return 'Could not submit request: $e';
    }
  }
}
