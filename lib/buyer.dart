import 'package:flutter/material.dart';
import 'package:ani_mart/product_detail.dart';
import 'dashboard.dart';
import 'announcement_page.dart';
import 'profile.dart';

// ─── Data model ──────────────────────────────────────────────────────────────

class _Listing {
  final String name;
  final String price;
  final double priceValue;
  final String image;
  final String category;
  final String location;
  final double distanceKm;

  const _Listing({
    required this.name,
    required this.price,
    required this.priceValue,
    required this.image,
    required this.category,
    required this.location,
    required this.distanceKm,
  });
}

const List<_Listing> _allListings = [
  // Poultry
  _Listing(name: 'Chicken',   price: '₱350',   priceValue: 350,   image: 'images/chicken.png',   category: 'Poultry',         location: 'Tanauan',   distanceKm: 20),
  _Listing(name: 'White Hen', price: '₱400',   priceValue: 400,   image: 'images/whitehen.png',  category: 'Poultry',         location: 'Sto. Tomas', distanceKm: 35),
  _Listing(name: 'Duck',      price: '₱300',   priceValue: 300,   image: 'images/duck.png',      category: 'Poultry',         location: 'Lipa City', distanceKm: 12),
  _Listing(name: 'Turkey',    price: '₱1,200', priceValue: 1200,  image: 'images/turkey.png',    category: 'Poultry',         location: 'Batangas',  distanceKm: 50),
  _Listing(name: 'Quail',     price: '₱80',    priceValue: 80,    image: 'images/quail.png',     category: 'Poultry',         location: 'Rosario',   distanceKm: 8),
  // Small Livestock
  _Listing(name: 'Goat',      price: '₱5,000', priceValue: 5000,  image: 'images/goat.png',      category: 'Small Livestock', location: 'Lemery',    distanceKm: 18),
  _Listing(name: 'Sheep',     price: '₱4,500', priceValue: 4500,  image: 'images/sheep.png',     category: 'Small Livestock', location: 'Ibaan',     distanceKm: 22),
  _Listing(name: 'Rabbit',    price: '₱250',   priceValue: 250,   image: 'images/rabbit.png',    category: 'Small Livestock', location: 'Bauan',     distanceKm: 14),
  _Listing(name: 'Pig',       price: '₱8,000', priceValue: 8000,  image: 'images/pig.png',       category: 'Small Livestock', location: 'San Jose',  distanceKm: 30),
  // Large Livestock
  _Listing(name: 'Cow',       price: '₱25,000',priceValue: 25000, image: 'images/cow.png',       category: 'Large Livestock', location: 'Malvar',    distanceKm: 40),
  _Listing(name: 'Horse',     price: '₱45,000',priceValue: 45000, image: 'images/horse.png',     category: 'Large Livestock', location: 'Padre G.',  distanceKm: 55),
  _Listing(name: 'Carabao',   price: '₱30,000',priceValue: 30000, image: 'images/carabao.png',   category: 'Large Livestock', location: 'Cuenca',    distanceKm: 28),
  // Aquatics
  _Listing(name: 'Tilapia',   price: '₱120',   priceValue: 120,   image: 'images/tilapia.png',   category: 'Aquatics',        location: 'Calaca',    distanceKm: 45),
  _Listing(name: 'Bangus',    price: '₱180',   priceValue: 180,   image: 'images/bangus.png',    category: 'Aquatics',        location: 'Nasugbu',   distanceKm: 60),
  _Listing(name: 'Shrimp',    price: '₱350',   priceValue: 350,   image: 'images/shrimp.png',    category: 'Aquatics',        location: 'Calatagan', distanceKm: 70),
];

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
  final Set<String> _favourites = {};

  // ── Derived list ───────────────────────────────────────────────────────────

  List<_Listing> get _filtered {
    List<_Listing> list = _allListings;

    if (_selectedCategory != 'All') {
      list = list.where((l) => l.category == _selectedCategory).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((l) =>
              l.name.toLowerCase().contains(q) ||
              l.category.toLowerCase().contains(q) ||
              l.location.toLowerCase().contains(q))
          .toList();
    }

    switch (_sortBy) {
      case 'Price ↑':
        list = [...list]..sort((a, b) => a.priceValue.compareTo(b.priceValue));
        break;
      case 'Price ↓':
        list = [...list]..sort((a, b) => b.priceValue.compareTo(a.priceValue));
        break;
      case 'Nearest':
        list = [...list]..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
        break;
      default:
        break;
    }

    return list;
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
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _sortBy = tempSort);
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
      }),
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

  // ── Favourites dialog ──────────────────────────────────────────────────────

  void _showFavourites() {
    showDialog(
      context: context,
      builder: (ctx) {
        final favs =
            _allListings.where((l) => _favourites.contains(l.name)).toList();
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.favorite, color: Color(0xFF6DBF99)),
              SizedBox(width: 8),
              Text('My Favourites',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: favs.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No favourites yet.\nTap ♡ on any listing to save it here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, height: 1.5),
                  ),
                )
              : SizedBox(
                  width: double.maxFinite,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: favs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final item = favs[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(item.image,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                  width: 44,
                                  height: 44,
                                  color: const Color(0xFFD6F0E4),
                                  child: const Icon(Icons.pets,
                                      color: Colors.white54))),
                        ),
                        title: Text(item.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 14)),
                        subtitle: Text('${item.price} · ${item.location}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black45)),
                        trailing: GestureDetector(
                          onTap: () {
                            setState(() => _favourites.remove(item.name));
                            Navigator.pop(ctx);
                            _showFavourites();
                          },
                          child: const Icon(Icons.favorite,
                              color: Color(0xFF6DBF99), size: 20),
                        ),
                      );
                    },
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close',
                  style: TextStyle(color: Color(0xFF6DBF99))),
            ),
          ],
        );
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final bool hasActiveFilters =
        _selectedCategory != 'All' || _sortBy != 'Default' || _searchQuery.isNotEmpty;

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
                        active: _sortBy != 'Default',
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
                      const Row(
                        children: [
                          Icon(Icons.location_on,
                              color: Color(0xFF6DBF99), size: 16),
                          SizedBox(width: 4),
                          Text('Tanauan, 20 KM',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                    ],
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
                          if (_searchQuery.isNotEmpty)
                            _filterChip('"$_searchQuery"',
                                () => setState(() => _searchQuery = '')),
                        ],
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Grid or empty state
                  items.isEmpty
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
                                      : 'No listings in this category',
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
                            final isFav = _favourites.contains(item.name);
                            return GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProductDetailPage(
                                    name: item.name,
                                    price: item.price,
                                    image: item.image,
                                  ),
                                ),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: const Color(0xFF6DBF99),
                                      width: 1.5),
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
                                          ClipRRect(
                                            borderRadius:
                                                const BorderRadius.only(
                                              topLeft: Radius.circular(10),
                                              topRight: Radius.circular(10),
                                            ),
                                            child: Image.asset(
                                              item.image,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                color:
                                                    const Color(0xFFD6F0E4),
                                                child: const Icon(
                                                    Icons
                                                        .image_not_supported_outlined,
                                                    color: Colors.white54,
                                                    size: 40),
                                              ),
                                            ),
                                          ),
                                          // ★ Per-card fav toggle
                                          Positioned(
                                            top: 6,
                                            right: 6,
                                            child: GestureDetector(
                                              onTap: () => setState(() {
                                                isFav
                                                    ? _favourites
                                                        .remove(item.name)
                                                    : _favourites.add(item.name);
                                              }),
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
                                              Text(
                                                '${item.location} · ${item.distanceKm.toInt()} km',
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.black38),
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