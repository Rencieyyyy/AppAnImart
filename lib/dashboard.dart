import 'package:flutter/material.dart';
import 'seller.dart';
import 'seller_analytics.dart';
import 'buyer.dart';
import 'announcement_page.dart';
import 'profile.dart';
import 'product_detail.dart';
import 'current_user.dart';
import 'main.dart';
import 'services/marketplace_service.dart';
import 'services/notification_service.dart';
import 'services/subscription_service.dart';
import 'widgets/notification_dot.dart';
import 'widgets/top_message.dart';

// ─── Data model ──────────────────────────────────────────────────────────────

class LivestockItem {
  final String label; // listing title
  final String imagePath; // primary image (network URL or asset path)
  final String category;
  final String priceText; // e.g. "₱350"
  final List<String> images; // all image URLs
  final String description;
  final String condition;
  final String location;
  final String sellerName;
  final String breed;
  final String age;
  final String weight;
  final String id; // listing row id
  final String sellerId; // owner's user id
  final String createdAt; // ISO timestamp
  final String status; // 'active' | 'disabled'
  final String sellerTier; // 'Free' | 'Premium' | 'Super Premium'

  const LivestockItem({
    required this.label,
    required this.imagePath,
    required this.category,
    this.priceText = '',
    this.images = const [],
    this.description = '',
    this.condition = '',
    this.location = '',
    this.sellerName = '',
    this.breed = '',
    this.age = '',
    this.weight = '',
    this.id = '',
    this.sellerId = '',
    this.createdAt = '',
    this.status = 'active',
    this.sellerTier = 'Free',
  });
}


// ─── Page ────────────────────────────────────────────────────────────────────

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
  
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 0;

  // Category filter
  static bool _planDialogShown = false;
  String _selectedCategory = 'Poultry';
  // "All" is the default landing section; a specific category is a filter.
  bool _showAllCategories = true;

  final List<String> _categories = [
    'Poultry',
    'Small Livestock',
    'Large Livestock',
    'Aquaculture',
    'Ornamental Fish',
    'Hatching & Breeding Products',
  ];

  // Search & filter
  String _searchQuery = '';
  String _filterSortBy = 'Default';
  final TextEditingController _searchController = TextEditingController();

  // Favourites — persisted in Supabase by listing id (same as Explore).
  Set<String> _favourites = {};

  // Sellers the user has blocked; their listings are hidden from the feed.
  Set<String> _blockedSellers = {};

  // Listings currently reserved FOR this user (as the winning buyer), by
  // listing id — they stay open/tappable for them while locked for others.
  Set<String> _reservedForMe = {};

  // Signed-in user's name (loaded from the `users` table).
  String _userName = '';

  // Listings from all users, loaded from the `listings` table.
  List<LivestockItem> _allItems = [];
  bool _loadingItems = true;

  // Feed pagination (other users' listings load a page at a time).
  int _feedPage = 0;
  bool _hasMoreItems = true;
  bool _loadingMore = false;

  // Server-side search results (all listings, not just loaded pages).
  List<LivestockItem> _searchResults = [];

  // Red dot on the announcements nav icon while unseen announcements exist.
  bool _hasUnseenAnnouncements = false;

  // ── Show plan popup on first load ─────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _loadItems();
    _loadFavorites();
    _loadBlocked();
    _loadReservedForMe();
    NotificationService.hasUnseenAnnouncements().then((v) {
      if (mounted && v) setState(() => _hasUnseenAnnouncements = true);
    });
    if (!_planDialogShown) {
      // Once per app session, after the first frame renders, decide what to
      // show the user: Super Premium members see a compact sales snapshot
      // popup with a shortcut to their full analytics page (an exclusive perk
      // of that tier); free members see the "choose a plan" popup; Premium
      // members see neither.
      _planDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final plan = await SubscriptionService.activePlanLabel();
        if (!mounted) return;
        if (plan == 'Super Premium') {
          showAnalyticsSnapshot(context, plan);
        } else if (plan != 'Premium') {
          _showPlanDialog();
        }
      });
    }
  }

  Future<void> _loadUserName() async {
    final name = await fetchCurrentUserName();
    if (mounted) setState(() => _userName = name);
  }

  /// Loads the user's saved favourites (by listing id) from Supabase.
  Future<void> _loadFavorites() async {
    final ids = await MarketplaceService.fetchFavoriteIds();
    if (!mounted) return;
    setState(() => _favourites = ids);
  }

  /// Loads the user's blocked sellers so their listings can be hidden.
  Future<void> _loadBlocked() async {
    final ids = await MarketplaceService.fetchBlockedIds();
    if (!mounted) return;
    setState(() => _blockedSellers = ids);
  }

  /// Loads which listings are reserved for this user as the winning buyer,
  /// so those cards stay tappable and show "RESERVED FOR YOU".
  Future<void> _loadReservedForMe() async {
    final txs = await MarketplaceService.fetchTransactions(asSeller: false);
    if (!mounted) return;
    setState(() => _reservedForMe = {
          for (final t in txs)
            if (t.isReserved) t.listingId,
        });
  }

  /// Whether the signed-in user owns [item] (owners can't favourite their
  /// own listings).
  bool _isMine(LivestockItem item) =>
      item.sellerId.isNotEmpty &&
      item.sellerId == supabase.auth.currentUser?.id;

  /// Persists a favourite toggle and updates local state optimistically.
  Future<void> _toggleFavorite(String listingId) async {
    if (listingId.isEmpty) return;
    // Sellers can't favourite their own listings.
    if (_allItems.any((i) => i.id == listingId && _isMine(i))) return;
    final wasFav = _favourites.contains(listingId);
    setState(() {
      wasFav ? _favourites.remove(listingId) : _favourites.add(listingId);
    });
    final nowFav = await MarketplaceService.toggleFavorite(
      listingId,
      currentlyFavorited: wasFav,
    );
    // Reconcile with the server result if the write failed.
    if (!mounted) return;
    if (nowFav != !wasFav) {
      setState(() {
        nowFav ? _favourites.add(listingId) : _favourites.remove(listingId);
      });
    }
  }

  /// One page of feed rows. The feed is paged so the query cost stays flat
  /// no matter how many listings exist.
  static const int _pageSize = 30;

  /// Loads the first page of the feed plus all of the user's own listings
  /// (shown in the "My Listings" section regardless of paging).
  Future<void> _loadItems() async {
    final uid = supabase.auth.currentUser?.id;
    try {
      // Sold/reserved listings stay in the feed greyed out (they can't be
      // opened by other users); disabled ones stay hidden.
      var othersQuery = supabase
          .from('listings')
          .select('*, users(name)')
          .inFilter('status', ['active', 'sold', 'reserved']);
      if (uid != null) othersQuery = othersQuery.neq('seller_id', uid);
      final results = await Future.wait([
        othersQuery
            .order('created_at', ascending: false)
            .range(0, _pageSize - 1),
        if (uid != null)
          supabase
              .from('listings')
              .select('*, users(name)')
              .eq('seller_id', uid)
              .inFilter('status', ['active', 'sold', 'reserved'])
              .order('created_at', ascending: false),
      ]);

      final otherRows = results[0] as List;
      final myRows = results.length > 1 ? results[1] as List : const [];
      final others = await _mapRows(otherRows);
      final mine = await _mapRows(myRows);

      if (!mounted) return;
      setState(() {
        _allItems = [...others, ...mine];
        _feedPage = 0;
        _hasMoreItems = otherRows.length == _pageSize;
        _loadingItems = false;
      });
    } catch (e) {
      debugPrint('Failed to load listings: $e');
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  /// Appends the next page of other users' listings to the feed.
  Future<void> _loadMoreItems() async {
    if (_loadingMore || !_hasMoreItems) return;
    setState(() => _loadingMore = true);
    final uid = supabase.auth.currentUser?.id;
    final nextPage = _feedPage + 1;
    try {
      var query = supabase
          .from('listings')
          .select('*, users(name)')
          .inFilter('status', ['active', 'sold', 'reserved']);
      if (uid != null) query = query.neq('seller_id', uid);
      final rows = await query.order('created_at', ascending: false).range(
          nextPage * _pageSize, nextPage * _pageSize + _pageSize - 1);
      final items = await _mapRows(rows as List);
      if (!mounted) return;
      setState(() {
        // Own listings live at the end of _allItems; new pages slot before
        // them, but order within sections is preserved by _filteredItems.
        _allItems = [..._allItems, ...items];
        _feedPage = nextPage;
        _hasMoreItems = rows.length == _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('Failed to load more listings: $e');
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Server-side search across every listing (not just loaded pages).
  /// Runs debounced from the search box; results replace the "others"
  /// section while a query is active.
  Future<void> _runServerSearch(String query) async {
    final q = query.trim();
    if (q.length < 2) return;
    try {
      final uid = supabase.auth.currentUser?.id;
      var search = supabase
          .from('listings')
          .select('*, users(name)')
          .inFilter('status', ['active', 'sold', 'reserved']).or(
              'title.ilike.%$q%,category.ilike.%$q%,breed.ilike.%$q%');
      if (uid != null) search = search.neq('seller_id', uid);
      final rows =
          await search.order('created_at', ascending: false).limit(50);
      final items = await _mapRows(rows as List);
      // Stale responses (query changed while in flight) are dropped.
      if (!mounted || _searchQuery.trim() != q) return;
      setState(() => _searchResults = items);
    } catch (e) {
      debugPrint('Server search failed: $e');
    }
  }

  /// Pull-to-refresh: reloads the feed plus the per-user state behind it.
  Future<void> _refreshAll() => Future.wait([
        _loadItems(),
        _loadFavorites(),
        _loadBlocked(),
        _loadReservedForMe(),
      ]);

  /// Shared row → item mapping, including the seller-tier lookup.
  Future<List<LivestockItem>> _mapRows(List rows) async {
    if (rows.isEmpty) return const [];
    // Resolve each seller's current tier so Super Premium sellers can be
    // given priority placement in the feed. Buyers can't read others'
    // subscriptions directly (RLS), so we go through the seller_tiers RPC.
    final sellerIds = <String>{
      for (final r in rows)
        if ('${(r as Map)['seller_id'] ?? ''}'.isNotEmpty) '${r['seller_id']}'
    }.toList();
    final tierBySeller = <String, String>{};
    if (sellerIds.isNotEmpty) {
      try {
        final tiers = await supabase
            .rpc('seller_tiers', params: {'seller_ids': sellerIds});
        for (final t in (tiers as List)) {
          tierBySeller['${(t as Map)['user_id']}'] = '${t['tier']}';
        }
      } catch (e) {
        debugPrint('Failed to load seller tiers: $e');
      }
    }

    return rows.map((r) {
      final row = r as Map<String, dynamic>;
      final priceValue = (row['price'] is num)
          ? (row['price'] as num).toDouble()
          : (double.tryParse('${row['price']}') ?? 0);
      final img = (row['image_url'] as String?)?.trim() ?? '';
      final imgs = (row['image_urls'] as List?)
              ?.map((e) => '$e')
              .where((e) => e.trim().isNotEmpty)
              .toList() ??
          <String>[];
      final seller = row['users'] as Map<String, dynamic>?;
      final sellerId = '${row['seller_id'] ?? ''}';
      return LivestockItem(
        label: (row['title'] as String?) ?? 'Untitled',
        imagePath: img.isNotEmpty ? img : 'images/chicken.png',
        category: (row['category'] as String?) ?? 'Uncategorized',
        priceText: _formatPrice(priceValue),
        images: imgs,
        description: (row['description'] as String?) ?? '',
        condition: (row['condition'] as String?) ?? '',
        location: (row['location'] as String?) ?? '',
        sellerName: (seller?['name'] as String?) ?? '',
        breed: (row['breed'] as String?) ?? '',
        age: (row['age'] as String?) ?? '',
        weight: (row['weight'] as String?) ?? '',
        id: '${row['id'] ?? ''}',
        sellerId: sellerId,
        createdAt: '${row['created_at'] ?? ''}',
        status: (row['status'] as String?) ?? 'active',
        sellerTier: tierBySeller[sellerId] ?? 'Free',
      );
    }).toList();
  }

  String _formatPrice(double value) {
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
    return '₱$text';
  }

  // First word of the name for a friendly greeting (e.g. "Rencee").
  String get _firstName =>
      _userName.trim().isEmpty ? '' : _userName.trim().split(' ').first;

  // ── Plan selection dialog ─────────────────────────────────────────────────

  void _showPlanDialog() {
    String selectedPlan = 'free';

    final List<AppPlan> plans = SubscriptionService.plans;

    // Live prices + promo discounts from the `prices` table; the static
    // plan prices show until (or if) this loads.
    Map<String, PlanPricing> pricing = const {};
    bool pricingRequested = false;

    String peso(double value) {
      final text = value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toStringAsFixed(2);
      return '₱$text';
    }

    showDialog(
      context: context,
      barrierDismissible: false, // must tap X or Continue to dismiss
      builder: (ctx) {
        // Paid plans use the pay-first flow on the full plans page: pay via
        // GCash, attach the receipt, and only then is the request submitted.
        // Free just closes the popup — it needs no approval.
        void submit() {
          final plan = SubscriptionService.planById(selectedPlan);
          Navigator.pop(ctx);
          if (plan.isFree) {
            showTopMessage(context, "You're on the Free plan.",
                isError: false);
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const PremiumSubscriptionPage()),
          );
        }

        return StatefulBuilder(
          builder: (ctx, setDialog) {
            if (!pricingRequested) {
              pricingRequested = true;
              SubscriptionService.fetchPricing().then((p) {
                if (p.isNotEmpty && ctx.mounted) setDialog(() => pricing = p);
              });
            }
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── X Button ────────────────────────────────────
                    Align(
                      alignment: Alignment.topRight,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.shade100,
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // ── Crown Icon ──────────────────────────────────
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFE1F5EE),
                      ),
                      child: const Icon(
                        Icons.workspace_premium,
                        color: Color(0xFF1D9E75),
                        size: 26,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Title ───────────────────────────────────────
                    const Text(
                      'Choose your plan',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Select the plan that fits your needs',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),

                    const SizedBox(height: 20),

                    // ── Plan Cards ──────────────────────────────────
                    ...plans.map((plan) {
                      final isSelected = selectedPlan == plan.id;
                      final planPricing = pricing[plan.id];
                      final discounted = planPricing?.discounted ?? false;
                      final pct = planPricing?.discountPercent ?? 0;
                      return GestureDetector(
                        onTap: () =>
                            setDialog(() => selectedPlan = plan.id),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF6DBF99)
                                  : Colors.grey.shade200,
                              width: isSelected ? 2 : 1,
                            ),
                            color: isSelected
                                ? const Color(0xFFE8F8F1)
                                : Colors.white,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                plan.id == 'free'
                                    ? Icons.person_outline
                                    : plan.id == 'premium'
                                        ? Icons.star_outline
                                        : Icons.workspace_premium,
                                color: const Color(0xFF6DBF99),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            plan.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                        // Promo chip, e.g. "-19% OFF".
                                        if (discounted) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF43F5E),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              '-${pct == pct.roundToDouble() ? pct.toInt() : pct}% OFF',
                                              style: const TextStyle(
                                                fontSize: 8,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.5,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      plan.description,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (discounted)
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    // Pre-discount price, struck through.
                                    Text(
                                      peso(planPricing!.price),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.black38,
                                        decoration:
                                            TextDecoration.lineThrough,
                                      ),
                                    ),
                                    Text(
                                      '${peso(planPricing.effectivePrice)} / mo',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1D9E75),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  planPricing != null
                                      ? '${peso(planPricing.price)} / mo'
                                      : plan.priceLabel,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1D9E75),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 6),

                    // ── Continue Button ─────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6DBF99),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'You can change your plan anytime in settings.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Derived list ──────────────────────────────────────────────────────────

  List<LivestockItem> get _filteredItems {
    // While searching, other users' listings come from the server-side
    // search (which covers ALL listings, not just loaded pages); the user's
    // own listings are always fully loaded, so they filter client-side.
    final base = _searchQuery.isEmpty
        ? _allItems
        : [
            ..._searchResults,
            ..._allItems.where(_isMine).where((i) =>
                i.label.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                i.category.toLowerCase().contains(_searchQuery.toLowerCase())),
          ];

    // Hide listings from sellers the user has blocked (same as Explore).
    final visible = _blockedSellers.isEmpty
        ? base
        : base.where((i) => !_blockedSellers.contains(i.sellerId)).toList();
    List<LivestockItem> items = _showAllCategories
        ? visible
        : visible.where((i) => i.category == _selectedCategory).toList();

    // Secondary ordering from the chosen sort (default = newest first).
    int secondary(LivestockItem a, LivestockItem b) {
      switch (_filterSortBy) {
        case 'A–Z':
          return a.label.compareTo(b.label);
        case 'Z–A':
          return b.label.compareTo(a.label);
        default:
          return b.createdAt.compareTo(a.createdAt);
      }
    }

    // Super Premium sellers get priority placement — their listings always
    // surface above Premium / Free sellers; ties fall back to the chosen sort.
    int rank(LivestockItem i) => i.sellerTier == 'Super Premium' ? 1 : 0;
    items = [...items]
      ..sort((a, b) {
        final r = rank(b) - rank(a);
        return r != 0 ? r : secondary(a, b);
      });

    return items;
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _onTabTapped(int index) {
    if (index == _selectedIndex) return;
    switch (index) {
      case 0:
        break;
      case 1:
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BuyerPage()));
        break;
      case 2:
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AnnouncementPage()));
        break;
      case 3:
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ProfilePage()));
        break;
    }
  }

  // ── Favourites sheet (same design & behavior as the Explore section) ──────

  /// Fetches the user's favourited listings straight from the server, so the
  /// sheet shows EVERY favourite — not just the ones inside the feed pages
  /// loaded so far.
  Future<List<LivestockItem>> _fetchFavoriteListings() async {
    final ids = (await MarketplaceService.fetchFavoriteIds()).toList();
    if (ids.isEmpty) return const [];
    if (mounted) setState(() => _favourites = ids.toSet());
    try {
      final rows = await supabase
          .from('listings')
          .select('*, users(name)')
          .inFilter('id', ids)
          .inFilter('status', ['active', 'sold', 'reserved'])
          .order('created_at', ascending: false);
      return _mapRows(rows as List);
    } catch (e) {
      debugPrint('Failed to load favourites: $e');
      // Fall back to whatever is already in the loaded pages.
      return _allItems.where((i) => _favourites.contains(i.id)).toList();
    }
  }

  void _showFavourites() {
    final future = _fetchFavoriteListings();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.72,
          child: FutureBuilder<List<LivestockItem>>(
              future: future,
              builder: (ctx, snap) {
                final loadingFavs =
                    snap.connectionState != ConnectionState.done;
                final favs = (snap.data ?? const <LivestockItem>[])
                    .where((i) => _favourites.contains(i.id))
                    .toList();
                return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                          color: Color(0xFFE8F7F1), shape: BoxShape.circle),
                      child: const Icon(Icons.favorite,
                          color: Color(0xFF6DBF99), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('My Favourites',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87)),
                          Text(
                            loadingFavs
                                ? 'Loading…'
                                : favs.isEmpty
                                    ? 'Nothing saved yet'
                                    : '${favs.length} saved ${favs.length == 1 ? 'listing' : 'listings'}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black45),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close,
                          color: Colors.black38, size: 22),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0xFFF0F0F0)),
              // Body
              Expanded(
                child: loadingFavs
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF6DBF99)))
                    : favs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 88,
                              height: 88,
                              decoration: const BoxDecoration(
                                  color: Color(0xFFF4FAF7),
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.favorite_border,
                                  color: Color(0xFF6DBF99), size: 40),
                            ),
                            const SizedBox(height: 16),
                            const Text('No favourites yet',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87)),
                            const SizedBox(height: 6),
                            const Text(
                              'Tap the ♡ on any listing and it will\nshow up here for quick access.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.black45,
                                  height: 1.5),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        itemCount: favs.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final item = favs[i];
                          return GestureDetector(
                            onTap: () {
                              Navigator.pop(ctx);
                              // Sold/reserved listings can't be opened by
                              // non-owners — unless reserved for this user.
                              if ((item.status == 'sold' ||
                                      item.status == 'reserved') &&
                                  !_isMine(item) &&
                                  !_reservedForMe.contains(item.id)) {
                                showTopMessage(
                                    context,
                                    item.status == 'reserved'
                                        ? 'This listing is reserved for another buyer.'
                                        : 'This listing has been sold.');
                                return;
                              }
                              _openListing(item);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border:
                                    Border.all(color: const Color(0xFFEDEDED)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: SizedBox(
                                      width: 68,
                                      height: 68,
                                      child: _cardImage(item.imagePath),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(item.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                color: Colors.black87)),
                                        const SizedBox(height: 3),
                                        Text(item.priceText,
                                            style: const TextStyle(
                                                color: Color(0xFF6DBF99),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14)),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            const Icon(
                                                Icons.location_on_outlined,
                                                size: 12,
                                                color: Colors.black38),
                                            const SizedBox(width: 2),
                                            Expanded(
                                              child: Text(
                                                item.location.isNotEmpty
                                                    ? item.location
                                                    : item.category,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.black38),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Remove from favourites
                                  GestureDetector(
                                    onTap: () async {
                                      await _toggleFavorite(item.id);
                                      if (ctx.mounted) setSheet(() {});
                                    },
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: const BoxDecoration(
                                          color: Color(0xFFE8F7F1),
                                          shape: BoxShape.circle),
                                      child: const Icon(Icons.favorite,
                                          color: Color(0xFF6DBF99), size: 18),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
                );
              }),
        );
      }),
    );
  }

  // ── Search + Filter bottom sheet ──────────────────────────────────────────

  void _showSearchFilter() {
    final tempController = TextEditingController(text: _searchQuery);
    String tempSort = _filterSortBy;
    String tempCategory = _showAllCategories ? 'All' : _selectedCategory;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text('Search',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54)),
                const SizedBox(height: 8),
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F2),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: TextField(
                    controller: tempController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search animals…',
                      hintStyle:
                          TextStyle(color: Colors.black38, fontSize: 14),
                      prefixIcon:
                          Icon(Icons.search, color: Colors.black38, size: 20),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Category',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['All', ..._categories].map((cat) {
                    final sel = tempCategory == cat;
                    return GestureDetector(
                      onTap: () => setSheet(() => tempCategory = cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel
                              ? const Color(0xFF6DBF99)
                              : const Color(0xFFF2F2F2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(cat,
                            style: TextStyle(
                                fontSize: 12,
                                color:
                                    sel ? Colors.white : Colors.black54,
                                fontWeight: sel
                                    ? FontWeight.w600
                                    : FontWeight.normal)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                const Text('Sort by',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54)),
                const SizedBox(height: 10),
                Row(
                  children: ['Default', 'A–Z', 'Z–A'].map((sort) {
                    final sel = tempSort == sort;
                    return GestureDetector(
                      onTap: () => setSheet(() => tempSort = sort),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel
                              ? const Color(0xFF6DBF99)
                              : const Color(0xFFF2F2F2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(sort,
                            style: TextStyle(
                                fontSize: 12,
                                color:
                                    sel ? Colors.white : Colors.black54,
                                fontWeight: sel
                                    ? FontWeight.w600
                                    : FontWeight.normal)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      _runServerSearch(tempController.text.trim());
                      setState(() {
                        _searchQuery = tempController.text.trim();
                        _searchResults = [];
                        _filterSortBy = tempSort;
                        if (tempCategory == 'All') {
                          _showAllCategories = true;
                        } else {
                          _showAllCategories = false;
                          _selectedCategory = tempCategory;
                        }
                      });
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6DBF99),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text('Apply',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  // ── See All dialog ────────────────────────────────────────────────────────

  void _showSeeAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('All Categories',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: _categories.map((cat) {
              final isSelected =
                  !_showAllCategories && _selectedCategory == cat;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF6DBF99)
                        : const Color(0xFFD6F0E4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.pets,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF6DBF99),
                      size: 18),
                ),
                title: Text(cat,
                    style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? const Color(0xFF6DBF99)
                            : Colors.black87)),
                subtitle: Text(
                    '${_allItems.where((i) => i.category == cat).length} animals',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black45)),
                onTap: () {
                  setState(() {
                    _showAllCategories = false;
                    _selectedCategory = cat;
                  });
                  Navigator.pop(ctx);
                },
              );
            }).toList()
              ..insert(
                0,
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _showAllCategories
                          ? const Color(0xFF6DBF99)
                          : const Color(0xFFD6F0E4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.grid_view,
                        color: _showAllCategories
                            ? Colors.white
                            : const Color(0xFF6DBF99),
                        size: 18),
                  ),
                  title: Text('All',
                      style: TextStyle(
                          fontWeight: _showAllCategories
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _showAllCategories
                              ? const Color(0xFF6DBF99)
                              : Colors.black87)),
                  subtitle: Text('${_allItems.length} animals',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black45)),
                  onTap: () {
                    setState(() => _showAllCategories = true);
                    Navigator.pop(ctx);
                  },
                ),
              ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close',
                style: TextStyle(color: Color(0xFF6DBF99))),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    // The signed-in user's own listings are pulled out of the main feed and
    // shown at the bottom under a "My Listings" header.
    final otherItems = items.where((i) => !_isMine(i)).toList();
    final myItems = items.where(_isMine).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF6DBF99),
                onRefresh: _refreshAll,
                child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // ── Top Bar ────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getFormattedDate(),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black45),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _firstName.isEmpty
                                  ? 'Good Morning !'
                                  : 'Good Morning, $_firstName !',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: _showFavourites,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                _favourites.isEmpty
                                    ? Icons.favorite_border
                                    : Icons.favorite,
                                color: _favourites.isEmpty
                                    ? Colors.black54
                                    : const Color(0xFF6DBF99),
                              ),
                              if (_favourites.isNotEmpty)
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF6DBF99),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${_favourites.length}',
                                        style: const TextStyle(
                                            fontSize: 8,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Search Bar ─────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _showSearchFilter,
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F2F2),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 12),
                                  const Icon(Icons.search,
                                      color: Colors.black38, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _searchQuery.isEmpty
                                          ? 'Search'
                                          : _searchQuery,
                                      style: TextStyle(
                                        color: _searchQuery.isEmpty
                                            ? Colors.black38
                                            : Colors.black87,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  if (_searchQuery.isNotEmpty)
                                    GestureDetector(
                                      onTap: () =>
                                          setState(() => _searchQuery = ''),
                                      child: const Padding(
                                        padding: EdgeInsets.only(right: 12),
                                        child: Icon(Icons.close,
                                            color: Colors.black38, size: 18),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _showSearchFilter,
                          child: Container(
                            height: 44,
                            width: 44,
                            decoration: BoxDecoration(
                              color: _filterSortBy != 'Default'
                                  ? const Color(0xFF6DBF99)
                                  : const Color(0xFFF2F2F2),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Icon(
                              Icons.tune,
                              color: _filterSortBy != 'Default'
                                  ? Colors.white
                                  : Colors.black54,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Active filter chips
                    if (_searchQuery.isNotEmpty ||
                        _filterSortBy != 'Default' ||
                        !_showAllCategories)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Wrap(
                          spacing: 6,
                          children: [
                            if (!_showAllCategories)
                              _filterChip(_selectedCategory,
                                  () => setState(() {
                                        _showAllCategories = true;
                                      })),
                            if (_filterSortBy != 'Default')
                              _filterChip(
                                  'Sort: $_filterSortBy',
                                  () => setState(
                                      () => _filterSortBy = 'Default')),
                            if (_searchQuery.isNotEmpty)
                              _filterChip('"$_searchQuery"',
                                  () => setState(() => _searchQuery = '')),
                          ],
                        ),
                      ),

                    const SizedBox(height: 20),

                    // ── Quick Actions Card ─────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6DBF99),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          const Text('Quick Actions',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                          const SizedBox(height: 16),
                          _quickActionButton('Seller', () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const SellerPage()));
                          }),
                          const SizedBox(height: 12),
                          _quickActionButton('Buyer', () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const BuyerPage()));
                          }),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Livestock Category Header ───────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Livestock Category',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87)),
                        GestureDetector(
                          onTap: _showSeeAll,
                          child: const Text('See All',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6DBF99),
                                  fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // ── Category Chips ─────────────────────────────────
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () =>
                                setState(() => _showAllCategories = true),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: _showAllCategories
                                    ? const Color(0xFF6DBF99)
                                    : const Color(0xFFF2F2F2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('All',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: _showAllCategories
                                          ? Colors.white
                                          : Colors.black54,
                                      fontWeight: _showAllCategories
                                          ? FontWeight.w600
                                          : FontWeight.normal)),
                            ),
                          ),
                          ..._categories.map((category) {
                            final isSelected = !_showAllCategories &&
                                _selectedCategory == category;
                            return GestureDetector(
                              onTap: () => setState(() {
                                _showAllCategories = false;
                                _selectedCategory = category;
                              }),
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF6DBF99)
                                      : const Color(0xFFF2F2F2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(category,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.black54,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal)),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── Grid ───────────────────────────────────────────
                    _loadingItems
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 60),
                            child: Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF6DBF99)),
                            ),
                          )
                        : items.isEmpty
                        ? Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Column(
                                children: [
                                  const Icon(Icons.search_off,
                                      color: Colors.black26, size: 48),
                                  const SizedBox(height: 12),
                                  Text(
                                    _searchQuery.isNotEmpty
                                        ? 'No results for "$_searchQuery"'
                                        : 'No listings available yet',
                                    style: const TextStyle(
                                        color: Colors.black45, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (otherItems.isNotEmpty)
                                GridView.count(
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 1.1,
                                  children: otherItems
                                      .map((item) => _buildCategoryCard(item))
                                      .toList(),
                                ),
                              // Next page of the feed (hidden while a search
                              // is active — search already covers everything).
                              if (_hasMoreItems && _searchQuery.isEmpty) ...[
                                const SizedBox(height: 16),
                                Center(
                                  child: OutlinedButton.icon(
                                    onPressed: _loadingMore
                                        ? null
                                        : _loadMoreItems,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          const Color(0xFF1D9E75),
                                      side: const BorderSide(
                                          color: Color(0xFF6DBF99)),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(24)),
                                    ),
                                    icon: _loadingMore
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Color(0xFF6DBF99)),
                                          )
                                        : const Icon(
                                            Icons.expand_more, size: 18),
                                    label: Text(_loadingMore
                                        ? 'Loading…'
                                        : 'Load more listings'),
                                  ),
                                ),
                              ],
                              // The user's own posts always sit at the bottom
                              // of the feed, under their own header.
                              if (myItems.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                const Row(
                                  children: [
                                    Icon(Icons.storefront_outlined,
                                        color: Color(0xFF6DBF99), size: 18),
                                    SizedBox(width: 6),
                                    Text('My Listings',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                GridView.count(
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 1.1,
                                  children: myItems
                                      .map((item) => _buildCategoryCard(item))
                                      .toList(),
                                ),
                              ],
                            ],
                          ),

                    const SizedBox(height: 80),
                  ],
                ),
                ),
              ),
            ),
          ],
        ),
      ),

      // ── Bottom Nav ────────────────────────────────────────────────────────
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onTabTapped,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF6DBF99),
          unselectedItemColor: Colors.black45,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: [
            const BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'Home'),
            const BottomNavigationBarItem(
                icon: Icon(Icons.shopping_cart_outlined),
                activeIcon: Icon(Icons.shopping_cart),
                label: 'Explore'),
            BottomNavigationBarItem(
                icon: NotificationDot(
                    show: _hasUnseenAnnouncements,
                    child: const Icon(Icons.notifications_outlined)),
                activeIcon: NotificationDot(
                    show: _hasUnseenAnnouncements,
                    child: const Icon(Icons.notifications)),
                label: 'Announcements'),
            const BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: 'Profile'),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _quickActionButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
        child: Text(label,
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _filterChip(String label, VoidCallback onRemove) {
    return Chip(
      label: Text(label,
          style: const TextStyle(fontSize: 11, color: Colors.white)),
      backgroundColor: const Color(0xFF6DBF99),
      deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white),
      onDeleted: onRemove,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _cardImage(String path) {
    Widget placeholder() => Container(
          color: const Color(0xFFD6F0E4),
          child: const Icon(Icons.image_not_supported_outlined,
              color: Colors.white54, size: 40),
        );
    return path.startsWith('http')
        ? Image.network(path,
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder())
        : Image.asset(path,
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder());
  }

  /// Opens the full product page for [item] and re-syncs state on return.
  Future<void> _openListing(LivestockItem item) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailPage(
          name: item.label,
          price: item.priceText,
          image: item.imagePath,
          images: item.images,
          description: item.description,
          condition: item.condition,
          sellerName: item.sellerName,
          location: item.location,
          breed: item.breed,
          age: item.age,
          weight: item.weight,
          createdAt: item.createdAt,
          listingId: item.id,
          sellerId: item.sellerId,
          status: item.status,
        ),
      ),
    );
    if (result == 'deleted' || result == 'updated') _loadItems();
    // The detail page can also toggle this listing's favourite, block its
    // seller, or change a reservation (cancel deal / accept an offer).
    _loadFavorites();
    _loadBlocked();
    _loadReservedForMe();
  }

  Widget _buildCategoryCard(LivestockItem item) {
    final isFav = _favourites.contains(item.id);
    final isUnavailable =
        item.status == 'sold' || item.status == 'reserved';
    // The winning buyer keeps full access to the listing reserved for them.
    final reservedForMe =
        item.status == 'reserved' && _reservedForMe.contains(item.id);
    // Locked for everyone else except the owner.
    final locked = isUnavailable && !reservedForMe && !_isMine(item);
    // Grey-out only for people the listing is no longer "for".
    final greyed = isUnavailable && !reservedForMe;
    return GestureDetector(
      onTap: locked
          ? () => showTopMessage(
              context,
              item.status == 'reserved'
                  ? 'This listing is reserved for another buyer.'
                  : 'This listing has been sold.')
          : () => _openListing(item),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFFF5F5F5),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Sold/reserved posts render desaturated so they read as
            // unavailable — except to the buyer they're reserved for.
            if (greyed)
              ColorFiltered(
                colorFilter: const ColorFilter.mode(
                    Colors.grey, BlendMode.saturation),
                child: _cardImage(item.imagePath),
              )
            else
              _cardImage(item.imagePath),
            if (greyed)
              Container(color: Colors.white.withOpacity(0.45)),
            if (isUnavailable)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: reservedForMe
                        ? const Color(0xE61D9E75)
                        : item.status == 'reserved'
                            ? const Color(0xCCE65100)
                            : Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                      reservedForMe
                          ? 'RESERVED FOR YOU'
                          : item.status == 'reserved'
                              ? 'RESERVED'
                              : 'SOLD',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                ),
              ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    if (item.priceText.isNotEmpty)
                      Text(item.priceText,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
            // Owners don't get a fav button on their own listings;
            // sold/reserved listings can't be favourited either.
            if (!_isMine(item) && !isUnavailable)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => _toggleFavorite(item.id),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color:
                          isFav ? const Color(0xFF6DBF99) : Colors.black45,
                      size: 16,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    const days = [
      'Monday', 'Tuesday', 'Wednesday',
      'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }
}