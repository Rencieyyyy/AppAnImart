import 'package:flutter/material.dart';
import 'package:ani_mart/product_detail.dart';
import 'main.dart';

/// Shows every listing published by a single user (seller).
class UserListingsPage extends StatefulWidget {
  final String userId;
  final String userName;

  const UserListingsPage({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<UserListingsPage> createState() => _UserListingsPageState();
}

class _UserListingsPageState extends State<UserListingsPage> {
  List<Map<String, dynamic>> _listings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  Future<void> _loadListings() async {
    try {
      final rows = await supabase
          .from('listings')
          .select()
          .eq('seller_id', widget.userId)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _listings =
            (rows as List).map((r) => r as Map<String, dynamic>).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('Failed to load user listings: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatPrice(dynamic raw) {
    final value = raw is num ? raw : (num.tryParse('$raw') ?? 0);
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
    return '₱$text';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.userName.trim().isEmpty
        ? 'Listings'
        : "${widget.userName}'s Listings";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF6DBF99),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6DBF99)))
          : _listings.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 64, color: Colors.black26),
                      SizedBox(height: 12),
                      Text('No listings published yet.',
                          style: TextStyle(color: Colors.black45, fontSize: 14)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFF6DBF99),
                  onRefresh: _loadListings,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _listings.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.82,
                    ),
                    itemBuilder: (context, index) =>
                        _listingCard(_listings[index]),
                  ),
                ),
    );
  }

  Widget _listingCard(Map<String, dynamic> row) {
    final title = (row['title'] as String?) ?? 'Untitled';
    final price = _formatPrice(row['price']);
    final imageUrl = (row['image_url'] as String?)?.trim() ?? '';
    final image = imageUrl.isNotEmpty ? imageUrl : 'images/chicken.png';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailPage(
            name: title,
            price: price,
            image: image,
            images: (row['image_urls'] as List?)
                    ?.map((e) => '$e')
                    .where((e) => e.trim().isNotEmpty)
                    .toList() ??
                const [],
            description: (row['description'] as String?) ?? '',
            condition: (row['condition'] as String?) ?? '',
            sellerName: widget.userName,
            location: (row['location'] as String?) ?? '',
            breed: (row['breed'] as String?) ?? '',
            age: (row['age'] as String?) ?? '',
            weight: (row['weight'] as String?) ?? '',
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF6DBF99), width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
                child: _listingImage(image),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(price,
                      style: const TextStyle(
                          color: Color(0xFF6DBF99),
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listingImage(String path) {
    Widget placeholder() => Container(
          color: const Color(0xFFD6F0E4),
          child: const Icon(Icons.image_not_supported_outlined,
              color: Colors.white54, size: 40),
        );
    return path.startsWith('http')
        ? Image.network(path,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder())
        : Image.asset(path,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder());
  }
}
