import 'package:flutter/material.dart';
import 'package:ani_mart/product_detail.dart';
import 'dashboard.dart';
import 'announcement_page.dart';
import 'profile.dart';
import 'main.dart';
import 'services/location_service.dart';
import 'services/marketplace_service.dart';
import 'widgets/city_picker.dart';

// ─── Data model ──────────────────────────────────────────────────────────────

class _Listing {
  final String name;
  final String price;
  final double priceValue;
  final String image;
  final List<String> images;
  final String category;
  final String location;
  // Where the seller lives (from their `users` row); null when not set.
  final double? sellerLat;
  final double? sellerLng;
  final String description;
  final String condition;
  final String sellerName;
  final String breed;
  final String age;
  final String weight;
  final String id;
  final String sellerId;
  final String createdAt;

  /// Seller's subscription tier: 'Free' | 'Premium' | 'Super Premium'.
  /// Drives feed priority and the card's border/tag colors.
  final String sellerTier;

  const _Listing({
    required this.name,
    required this.price,
    required this.priceValue,
    required this.image,
    this.images = const [],
    required this.category,
    required this.location,
    this.sellerLat,
    this.sellerLng,
    this.description = '',
    this.condition = '',
    this.sellerName = '',
    this.breed = '',
    this.age = '',
    this.weight = '',
    this.id = '',
    this.sellerId = '',
    this.createdAt = '',
    this.sellerTier = 'Free',
  });
}

const List<String> _categories = [
  'All',
  'Poultry',
  'Small Livestock',
  'Large Livestock',
  'Aquatics',
];

// ─── Page ─────────────────────────────────────────────────────────────────────

class BuyerPage extends StatefulWidget {
  const BuyerPage({super.key});

  @override
  State<BuyerPage> createState() => _BuyerPageState();
}

class _BuyerPageState extends State<BuyerPage> {
  int _selectedIndex = 1;

  // Filters
  String _selectedCategory = 'All';
  String _searchQuery = '';
  String _sortBy = 'Default'; // Default | Price ↑ | Price ↓ | Nearest
  double? _minPrice;
  double? _maxPrice;
  double? _maxKm; // "within X km" radius; null = any distance

  // Persistent favourites (listing ids) and blocked sellers (user ids).
  Set<String> _favourites = {};
  Set<String> _blockedSellers = {};

  // Listings loaded from the `listings` table.
  List<_Listing> _allListings = [];
  bool _loading = true;

  // The signed-in buyer's saved location — drives "Explore near you".
  UserLocation? _myLocation;

  // Seller distances keyed by listing id, precomputed whenever the listings
  // or the buyer's location change so sorting/filtering never re-runs the
  // Haversine math on every rebuild.
  Map<String, double> _distances = {};

  @override
  void initState() {
    super.initState();
    _loadListings();
    _loadFavorites();
    _loadBlocked();
    _loadMyLocation();
  }

  /// Loads the buyer's saved location so listing distances can be computed.
  /// Users who never picked one default to their profile address.
  Future<void> _loadMyLocation() async {
    final loc = await LocationService.fetchUserLocation() ??
        await LocationService.adoptLocationFromAddress();
    if (!mounted) return;
    setState(() {
      _myLocation = loc;
      _recomputeDistances();
    });
  }

  /// Rebuilds the listing-id → distance map. Call inside setState whenever
  /// `_allListings` or `_myLocation` changes.
  void _recomputeDistances() {
    final me = _myLocation;
    final next = <String, double>{};
    if (me != null) {
      for (final l in _allListings) {
        if (l.id.isEmpty || l.sellerLat == null || l.sellerLng == null) {
          continue;
        }
        next[l.id] = LocationService.distanceKm(
            me.lat, me.lng, l.sellerLat!, l.sellerLng!);
      }
    }
    _distances = next;
  }

  /// Distance in km between the buyer and the listing's seller, or null when
  /// either side has no saved location.
  double? _distanceOf(_Listing l) => _distances[l.id];

  /// Formats a distance as e.g. "3.2 km" or "24 km".
  String _formatDistance(double km) =>
      km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';

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

  /// Persists a favourite toggle and updates local state optimistically.
  Future<void> _toggleFavorite(String listingId) async {
    if (listingId.isEmpty) return;
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

  /// Loads all active listings from Supabase, newest first.
  Future<void> _loadListings() async {
    try {
      final rows = await supabase
          .from('listings')
          .select('*, users(name, latitude, longitude)')
          .eq('status', 'active')
          .order('created_at', ascending: false);

      // Resolve each seller's current subscription tier so paid sellers get
      // priority placement + colored borders. Buyers can't read others'
      // subscriptions directly (RLS), so we go through the seller_tiers RPC.
      final sellerIds = <String>{
        for (final r in (rows as List))
          if ('${(r as Map)['seller_id'] ?? ''}'.isNotEmpty)
            '${r['seller_id']}'
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

      if (!mounted) return;
      setState(() {
        _allListings = rows.map((row) {
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
          return _Listing(
            name: (row['title'] as String?) ?? 'Untitled',
            price: _formatPrice(priceValue),
            priceValue: priceValue,
            image: img.isNotEmpty ? img : 'images/chicken.png',
            images: imgs,
            category: (row['category'] as String?) ?? 'Uncategorized',
            location: (row['location'] as String?) ?? '',
            sellerLat: (seller?['latitude'] as num?)?.toDouble(),
            sellerLng: (seller?['longitude'] as num?)?.toDouble(),
            description: (row['description'] as String?) ?? '',
            condition: (row['condition'] as String?) ?? '',
            sellerName: (seller?['name'] as String?) ?? '',
            breed: (row['breed'] as String?) ?? '',
            age: (row['age'] as String?) ?? '',
            weight: (row['weight'] as String?) ?? '',
            id: '${row['id'] ?? ''}',
            sellerId: '${row['seller_id'] ?? ''}',
            createdAt: '${row['created_at'] ?? ''}',
            sellerTier: tierBySeller['${row['seller_id'] ?? ''}'] ?? 'Free',
          );
        }).toList();
        _recomputeDistances();
        _loading = false;
      });
    } catch (e) {
      debugPrint('Failed to load listings: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Formats a numeric price as e.g. "₱350" (no trailing ".0").
  String _formatPrice(double value) {
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
    return '₱$text';
  }

  // ── Derived list ───────────────────────────────────────────────────────────

  List<_Listing> get _filtered {
    // Hide listings from sellers the user has blocked.
    List<_Listing> list = _blockedSellers.isEmpty
        ? _allListings
        : _allListings
            .where((l) => !_blockedSellers.contains(l.sellerId))
            .toList();

    if (_selectedCategory != 'All') {
      list = list.where((l) => l.category == _selectedCategory).toList();
    }

    if (_minPrice != null) {
      list = list.where((l) => l.priceValue >= _minPrice!).toList();
    }
    if (_maxPrice != null) {
      list = list.where((l) => l.priceValue <= _maxPrice!).toList();
    }

    // "Near you" radius — only meaningful once the buyer has a location.
    if (_maxKm != null && _myLocation != null) {
      list = list.where((l) {
        final d = _distanceOf(l);
        return d != null && d <= _maxKm!;
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((l) =>
              l.name.toLowerCase().contains(q) ||
              l.category.toLowerCase().contains(q) ||
              l.location.toLowerCase().contains(q) ||
              l.breed.toLowerCase().contains(q))
          .toList();
    }

    // Nearest sellers first; listings with unknown distance go last (newest
    // first among themselves).
    int byDistance(_Listing a, _Listing b) {
      final da = _distanceOf(a);
      final db = _distanceOf(b);
      if (da == null && db == null) return b.createdAt.compareTo(a.createdAt);
      if (da == null) return 1;
      if (db == null) return -1;
      final c = da.compareTo(db);
      return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
    }

    // Secondary ordering from the chosen sort.
    int secondary(_Listing a, _Listing b) {
      switch (_sortBy) {
        case 'Price ↑':
          return a.priceValue.compareTo(b.priceValue);
        case 'Price ↓':
          return b.priceValue.compareTo(a.priceValue);
        case 'Nearest':
          return byDistance(a, b);
        default:
          // "Explore near you": once the buyer has set a location, the
          // default ordering is by how close each seller lives.
          return _myLocation != null
              ? byDistance(a, b)
              : b.createdAt.compareTo(a.createdAt);
      }
    }

    // Paid sellers always surface first: Super Premium above Premium above
    // Free; ties fall back to the chosen sort. Applied on every rebuild, so
    // newly loaded listings are ranked by subscription immediately.
    list = [...list]
      ..sort((a, b) {
        final r = _tierRank(b) - _tierRank(a);
        return r != 0 ? r : secondary(a, b);
      });

    return list;
  }

  static int _tierRank(_Listing l) {
    switch (l.sellerTier) {
      case 'Super Premium':
        return 2;
      case 'Premium':
        return 1;
      default:
        return 0;
    }
  }

  /// Accent color for a listing card: violet for Super Premium sellers,
  /// amber for Premium, brand green for everyone else.
  static Color _tierColor(_Listing l) {
    switch (l.sellerTier) {
      case 'Super Premium':
        return const Color(0xFF8E5BE8);
      case 'Premium':
        return const Color(0xFFFFB300);
      default:
        return const Color(0xFF6DBF99);
    }
  }

  // ── Location picker ────────────────────────────────────────────────────────

  /// Lets the buyer pick their city/municipality; saved to their `users` row
  /// so distances can be computed against every seller.
  Future<void> _showLocationPicker() async {
    final city = await showCityPicker(
      context,
      selectedLabel: _myLocation?.name,
      subtitle: 'Pick your city or municipality — anywhere in the '
          'Philippines — to see how far each seller is.',
    );
    if (city == null || !mounted) return;
    // Optimistic update so distances appear immediately.
    final previous = _myLocation;
    setState(() {
      _myLocation =
          UserLocation(name: city.label, lat: city.lat, lng: city.lng);
      _recomputeDistances();
    });
    final ok = await LocationService.saveUserLocation(city);
    if (!mounted || ok) return;
    setState(() {
      _myLocation = previous;
      _recomputeDistances();
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not save your location. Please try again.')));
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _onTabTapped(int index) {
    if (index == _selectedIndex) return;
    switch (index) {
      case 0:
        Navigator.pushAndRemoveUntil(context,
            MaterialPageRoute(builder: (_) => const DashboardPage()),
            (route) => false);
        break;
      case 2:
        Navigator.pushAndRemoveUntil(context,
            MaterialPageRoute(builder: (_) => const AnnouncementPage()),
            (route) => false);
        break;
      case 3:
        Navigator.pushAndRemoveUntil(context,
            MaterialPageRoute(builder: (_) => const ProfilePage()),
            (route) => false);
        break;
    }
  }

  // ── Search bottom sheet ────────────────────────────────────────────────────

  void _showSearchSheet() {
    final ctrl = TextEditingController(text: _searchQuery);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
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
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Search Livestock',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            const SizedBox(height: 12),
            Container(
              height: 48,
              decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(24)),
              child: TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search by name, category, location…',
                  hintStyle: TextStyle(color: Colors.black38, fontSize: 13),
                  prefixIcon:
                      Icon(Icons.search, color: Colors.black38, size: 20),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _searchQuery = ctrl.text.trim());
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6DBF99),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                child: const Text('Search',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Filter bottom sheet ────────────────────────────────────────────────────

  void _showFilterSheet() {
    String tempSort = _sortBy;
    double? tempMaxKm = _maxKm;
    final minCtrl = TextEditingController(
        text: _minPrice != null ? _minPrice!.toInt().toString() : '');
    final maxCtrl = TextEditingController(
        text: _maxPrice != null ? _maxPrice!.toInt().toString() : '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
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
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('Filter & Sort',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 20),
              const Text('Sort by',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Default', 'Price ↑', 'Price ↓', 'Nearest']
                    .map((s) {
                  final sel = tempSort == s;
                  return GestureDetector(
                    onTap: () => setSheet(() => tempSort = s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel
                            ? const Color(0xFF6DBF99)
                            : const Color(0xFFF2F2F2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(s,
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
              const Text('Distance',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54)),
              const SizedBox(height: 10),
              if (_myLocation == null)
                GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _showLocationPicker();
                  },
                  child: const Row(
                    children: [
                      Icon(Icons.near_me_outlined,
                          color: Color(0xFF6DBF99), size: 16),
                      SizedBox(width: 6),
                      Text('Set your location to filter by distance',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6DBF99),
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [null, 10.0, 25.0, 50.0, 100.0].map((km) {
                    final sel = tempMaxKm == km;
                    return GestureDetector(
                      onTap: () => setSheet(() => tempMaxKm = km),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel
                              ? const Color(0xFF6DBF99)
                              : const Color(0xFFF2F2F2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                            km == null ? 'Any' : '${km.toInt()} km',
                            style: TextStyle(
                                fontSize: 12,
                                color: sel ? Colors.white : Colors.black54,
                                fontWeight: sel
                                    ? FontWeight.w600
                                    : FontWeight.normal)),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 20),
              const Text('Price range (₱)',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _priceField(minCtrl, 'Min')),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('–', style: TextStyle(color: Colors.black38)),
                  ),
                  Expanded(child: _priceField(maxCtrl, 'Max')),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _sortBy = 'Default';
                            _minPrice = null;
                            _maxPrice = null;
                            _maxKm = null;
                          });
                          Navigator.pop(ctx);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6DBF99),
                          side: const BorderSide(color: Color(0xFF6DBF99)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                        ),
                        child: const Text('Reset',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _sortBy = tempSort;
                            _minPrice = double.tryParse(minCtrl.text.trim());
                            _maxPrice = double.tryParse(maxCtrl.text.trim());
                            _maxKm = tempMaxKm;
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
                  ),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _priceField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF2F2F2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  // ── Categories bottom sheet ────────────────────────────────────────────────

  void _showCategoriesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
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
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Select Category',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            const SizedBox(height: 16),
            ..._categories.map((cat) {
              final isSelected = _selectedCategory == cat;
              final count = cat == 'All'
                  ? _allListings.length
                  : _allListings.where((l) => l.category == cat).length;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedCategory = cat);
                  Navigator.pop(ctx);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFE8F7F1)
                        : const Color(0xFFF9F9F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isSelected
                            ? const Color(0xFF6DBF99)
                            : Colors.transparent,
                        width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        cat == 'All'
                            ? Icons.grid_view
                            : cat == 'Poultry'
                                ? Icons.egg_alt
                                : cat == 'Aquatics'
                                    ? Icons.water
                                    : Icons.pets,
                        color: isSelected
                            ? const Color(0xFF6DBF99)
                            : Colors.black45,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(cat,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isSelected
                                    ? const Color(0xFF6DBF99)
                                    : Colors.black87)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF6DBF99)
                              : const Color(0xFFEEEEEE),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('$count',
                            style: TextStyle(
                                fontSize: 11,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.black54,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Favourites bottom sheet ────────────────────────────────────────────────

  void _showFavourites() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final favs =
            _allListings.where((l) => _favourites.contains(l.id)).toList();
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.72,
          child: Column(
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
                            favs.isEmpty
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
                child: favs.isEmpty
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
                          final distance = _distanceOf(item);
                          return GestureDetector(
                            onTap: () {
                              Navigator.pop(ctx);
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
                                    child: _listingImage(item.image,
                                        width: 68, height: 68),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(item.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                color: Colors.black87)),
                                        const SizedBox(height: 3),
                                        Text(item.price,
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
                                                distance != null
                                                    ? '${item.location.split(',').first} · ${_formatDistance(distance)} away'
                                                    : item.location,
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
          ),
        );
      }),
    );
  }

  /// Opens the full product page for [item] and re-syncs state on return.
  Future<void> _openListing(_Listing item) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailPage(
          name: item.name,
          price: item.price,
          image: item.image,
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
          status: 'active',
        ),
      ),
    );
    if (result == 'deleted' || result == 'updated') _loadListings();
    _loadFavorites();
    _loadBlocked();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final bool hasPriceFilter = _minPrice != null || _maxPrice != null;
    final bool hasActiveFilters = _selectedCategory != 'All' ||
        _sortBy != 'Default' ||
        _searchQuery.isNotEmpty ||
        hasPriceFilter ||
        _maxKm != null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // ── Green Header ───────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(
                top: 50, bottom: 20, left: 16, right: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF6DBF99),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const DashboardPage()),
                          (route) => false),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 24),
                    ),
                    Row(
                      children: [
                        // ★ Search icon
                        GestureDetector(
                          onTap: _showSearchSheet,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.search,
                                  color: Colors.white, size: 24),
                              if (_searchQuery.isNotEmpty)
                                Positioned(
                                  top: -3,
                                  right: -3,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // ★ Heart icon
                        GestureDetector(
                          onTap: _showFavourites,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                _favourites.isEmpty
                                    ? Icons.favorite_border
                                    : Icons.favorite,
                                color: Colors.white,
                                size: 24,
                              ),
                              if (_favourites.isNotEmpty)
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle),
                                    child: Center(
                                      child: Text(
                                        '${_favourites.length}',
                                        style: const TextStyle(
                                            fontSize: 8,
                                            color: Color(0xFF6DBF99),
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
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Buy Livestock',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    // ★ Filter button
                    Expanded(
                      child: _buildHeaderButton(
                        Icons.filter_list,
                        _sortBy != 'Default' ? 'Sort: $_sortBy' : 'Filter',
                        onTap: _showFilterSheet,
                        active: _sortBy != 'Default' ||
                            hasPriceFilter ||
                            _maxKm != null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // ★ Categories button
                    Expanded(
                      child: _buildHeaderButton(
                        Icons.keyboard_arrow_down,
                        _selectedCategory == 'All'
                            ? 'Categories'
                            : _selectedCategory,
                        onTap: _showCategoriesSheet,
                        active: _selectedCategory != 'All',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Body ───────────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // Results header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'Results for "$_searchQuery"'
                            : 'Available Livestock',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      // Buyer's saved location — tap to set/change it.
                      GestureDetector(
                        onTap: _showLocationPicker,
                        child: Row(
                          children: [
                            const Icon(Icons.location_on,
                                color: Color(0xFF6DBF99), size: 16),
                            const SizedBox(width: 4),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 130),
                              child: Text(
                                _myLocation != null
                                    ? _myLocation!.name.split(',').first
                                    : 'Set location',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down,
                                color: Colors.black38, size: 16),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Nudge to set a location so "near you" distances work.
                  if (!_loading && _myLocation == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: GestureDetector(
                        onTap: _showLocationPicker,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F7F1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.near_me_outlined,
                                  color: Color(0xFF6DBF99), size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Set your location to explore livestock near you',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.black87),
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  color: Colors.black38, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Active filter chips
                  if (hasActiveFilters)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (_selectedCategory != 'All')
                            _filterChip(_selectedCategory,
                                () => setState(() => _selectedCategory = 'All')),
                          if (_sortBy != 'Default')
                            _filterChip('Sort: $_sortBy',
                                () => setState(() => _sortBy = 'Default')),
                          if (_maxKm != null)
                            _filterChip('Within ${_maxKm!.toInt()} km',
                                () => setState(() => _maxKm = null)),
                          if (hasPriceFilter)
                            _filterChip(
                                '₱${_minPrice?.toInt() ?? 0}–${_maxPrice != null ? _maxPrice!.toInt().toString() : '∞'}',
                                () => setState(() {
                                      _minPrice = null;
                                      _maxPrice = null;
                                    })),
                          if (_searchQuery.isNotEmpty)
                            _filterChip('"$_searchQuery"',
                                () => setState(() => _searchQuery = '')),
                        ],
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Grid, loading, or empty state
                  _loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 80),
                          child: Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF6DBF99)),
                          ),
                        )
                      : items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 60),
                          child: Center(
                            child: Column(
                              children: [
                                const Icon(Icons.search_off,
                                    color: Colors.black26, size: 52),
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
                      : GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: items.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.82,
                          ),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final isFav = _favourites.contains(item.id);
                            final distance = _distanceOf(item);
                            final tierColor = _tierColor(item);
                            return GestureDetector(
                              onTap: () => _openListing(item),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: tierColor, width: 1.5),
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.white,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // Image with fav button overlay
                                    Expanded(
                                      child: Stack(
                                        children: [
                                          SizedBox(
                                            width: double.infinity,
                                            height: double.infinity,
                                            child: ClipRRect(
                                              borderRadius:
                                                  const BorderRadius.only(
                                                topLeft: Radius.circular(10),
                                                topRight: Radius.circular(10),
                                              ),
                                              child: _listingImage(item.image,
                                                  width: double.infinity),
                                            ),
                                          ),
                                          // Seller-tier tag (top-left,
                                          // aligned with the fav button).
                                          if (item.sellerTier != 'Free')
                                            Positioned(
                                              top: 6,
                                              left: 6,
                                              child: Container(
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 6,
                                                    vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: tierColor,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                        Icons
                                                            .workspace_premium_rounded,
                                                        size: 10,
                                                        color: Colors.white),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      item.sellerTier
                                                          .toUpperCase(),
                                                      style: const TextStyle(
                                                        fontSize: 7.5,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        letterSpacing: 0.4,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          // ★ Per-card fav toggle
                                          Positioned(
                                            top: 6,
                                            right: 6,
                                            child: GestureDetector(
                                              onTap: () =>
                                                  _toggleFavorite(item.id),
                                              child: Container(
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withOpacity(0.9),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  isFav
                                                      ? Icons.favorite
                                                      : Icons.favorite_border,
                                                  color: isFav
                                                      ? const Color(0xFF6DBF99)
                                                      : Colors.black45,
                                                  size: 15,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Name, price, location
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          8, 6, 8, 8),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(item.name,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 2),
                                          Text(item.price,
                                              style: const TextStyle(
                                                  color: Color(0xFF6DBF99),
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13)),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              const Icon(Icons.location_on,
                                                  size: 11,
                                                  color: Colors.black38),
                                              const SizedBox(width: 2),
                                              Expanded(
                                                child: Text(
                                                  distance != null
                                                      ? '${item.location.split(',').first} · ${_formatDistance(distance)} away'
                                                      : item.location,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.black38),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Bottom Nav ─────────────────────────────────────────────────────────
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        selectedItemColor: const Color(0xFF6DBF99),
        unselectedItemColor: Colors.black45,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.shopping_cart_outlined),
              activeIcon: Icon(Icons.shopping_cart),
              label: 'Explore'),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications_outlined),
              activeIcon: Icon(Icons.notifications),
              label: 'Announcements'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _buildHeaderButton(
    IconData icon,
    String label, {
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.white.withOpacity(0.25) : Colors.transparent,
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Renders a listing image from either a network URL or a bundled asset.
  Widget _listingImage(String path,
      {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    Widget placeholder() => Container(
          width: width,
          height: height,
          color: const Color(0xFFD6F0E4),
          child: const Icon(Icons.image_not_supported_outlined,
              color: Colors.white54, size: 40),
        );
    return path.startsWith('http')
        ? Image.network(path,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => placeholder())
        : Image.asset(path,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => placeholder());
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
}
