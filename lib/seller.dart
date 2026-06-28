import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ani_mart/product_detail.dart';
import 'cloudinary_function.dart';
import 'current_user.dart';
import 'main.dart';
import 'widgets/top_message.dart';

/// A photo chosen by the user, kept as in-memory bytes so it works on every
/// platform including Flutter Web (where `dart:io` File is unavailable).
class _PickedImage {
  final Uint8List bytes;
  final String name;
  const _PickedImage(this.bytes, this.name);
}

class SellerPage extends StatefulWidget {
  const SellerPage({super.key});

  @override
  State<SellerPage> createState() => _SellerPageState();
}

class _SellerPageState extends State<SellerPage> {
  int _selectedTab = 0;

  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _descController  = TextEditingController();
  final _breedController = TextEditingController();
  final _ageController   = TextEditingController();
  final _weightController = TextEditingController();
  String? _selectedCategory;
  String? _selectedCondition;
  String _weightUnit = 'kg'; // 'kg' or 'lbs'

  final List<_PickedImage> _pickedImages = [];
  final ImagePicker _imagePicker = ImagePicker();
  bool _uploading = false;

  // Signed-in user's name + avatar (loaded from the `users` table).
  String _userName = '';
  String _avatarUrl = '';

  final List<String> _categories  = ['Poultry', 'Small Livestock', 'Large Livestock', 'Aquatics'];
  final List<String> _conditions  = ['Good', 'Excellent', 'Fair'];

  // Listings owned by the signed-in user, loaded from the `listings` table.
  final List<Map<String, dynamic>> _myListings = [];
  bool _loadingListings = true;

  static const String _location = 'Tanauan, Batangas Philippines -4232';

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _loadMyListings();
  }

  Future<void> _loadUserName() async {
    final name = await fetchCurrentUserName();
    if (mounted) setState(() => _userName = name);

    // Also load the avatar so the header shows the user's real photo.
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final row = await supabase
          .from('users')
          .select('avatar_url')
          .eq('id', userId)
          .maybeSingle();
      final url = (row?['avatar_url'] as String?)?.trim() ?? '';
      if (mounted && url.isNotEmpty) setState(() => _avatarUrl = url);
    } catch (_) {
      // Ignore — fall back to the default person icon.
    }
  }

  /// Loads the signed-in user's listings from Supabase, newest first.
  Future<void> _loadMyListings() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _loadingListings = false);
      return;
    }
    try {
      final rows = await supabase
          .from('listings')
          .select()
          .eq('seller_id', userId)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _myListings
          ..clear()
          ..addAll((rows as List).map((r) {
            final row = r as Map<String, dynamic>;
            final img = (row['image_url'] as String?)?.trim() ?? '';
            final imgs = (row['image_urls'] as List?)
                    ?.map((e) => '$e')
                    .where((e) => e.trim().isNotEmpty)
                    .toList() ??
                <String>[];
            return <String, dynamic>{
              'id': row['id'],
              'name': (row['title'] as String?) ?? 'Untitled',
              'price': _formatPrice(row['price']),
              'image': img.isNotEmpty ? img : 'images/chicken.png',
              'isAsset': img.isEmpty,
              'images': imgs,
              'description': (row['description'] as String?) ?? '',
              'condition': (row['condition'] as String?) ?? '',
              'location': (row['location'] as String?) ?? '',
              'breed': (row['breed'] as String?) ?? '',
              'age': (row['age'] as String?) ?? '',
              'weight': (row['weight'] as String?) ?? '',
              'createdAt': '${row['created_at'] ?? ''}',
              'sellerId': '${row['seller_id'] ?? ''}',
              'status': (row['status'] as String?) ?? 'active',
            };
          }));
        _loadingListings = false;
      });
    } catch (e) {
      debugPrint('Failed to load listings: $e');
      if (mounted) setState(() => _loadingListings = false);
    }
  }

  /// Formats a numeric price as e.g. "₱350" (no trailing ".0").
  String _formatPrice(dynamic raw) {
    final value = raw is num ? raw : (num.tryParse('$raw') ?? 0);
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
    return '₱$text';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descController.dispose();
    _breedController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  void _showPhotoSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add Photo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6F0E4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.camera_alt_outlined, color: Color(0xFF6DBF99)),
                  ),
                  title: const Text('Take a Photo', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Use your camera'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);   // ✅ fixed import resolves this
                  },
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6F0E4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.photo_library_outlined, color: Color(0xFF6DBF99)),
                  ),
                  title: const Text('Choose from Files', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Pick from your gallery or files'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);  // ✅ fixed
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _imagePicker.pickImage(  // ✅ XFile resolved
        source: source,
        imageQuality: 85,
        maxWidth: 1080,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _pickedImages.add(_PickedImage(bytes, picked.name));
        });
      }
    } catch (e) {
      if (mounted) {
        showTopMessage(context, 'Could not pick image: $e');
      }
    }
  }

  Future<void> _publishListing() async {
    if (_uploading) return;
    final title = _titleController.text.trim();
    final price = _priceController.text.trim();
    final description = _descController.text.trim();
    final breed = _breedController.text.trim();
    final age = _ageController.text.trim();
    final weightValue = _weightController.text.trim();
    final weight = weightValue.isEmpty ? '' : '$weightValue $_weightUnit';

    if (_pickedImages.isEmpty) {
      showTopMessage(context, 'Please add at least one photo.');
      return;
    }
    if (title.isEmpty ||
        price.isEmpty ||
        _selectedCategory == null ||
        _selectedCondition == null ||
        breed.isEmpty ||
        age.isEmpty ||
        weight.isEmpty ||
        description.isEmpty) {
      showTopMessage(context, 'Please fill in all fields.');
      return;
    }
    final priceValue = num.tryParse(price);
    if (priceValue == null) {
      showTopMessage(context, 'Please enter a valid price.');
      return;
    }
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      showTopMessage(context, 'You are not signed in. Please log in again.');
      return;
    }

    final images = List<_PickedImage>.from(_pickedImages);
    setState(() => _uploading = true);

    try {
      final imageUrls = <String>[];
      for (final image in images) {
        // Host each image on Cloudinary, then record it in test_img.
        final url = await uploadToCloudinary(image.bytes, image.name);
        if (url == null) {
          throw Exception('Cloudinary upload returned no URL.');
        }
        imageUrls.add(url);
        await supabase.from('test_img').insert({
          'file': image.name,
          'cloud_url': url,
          'user_id': userId,
        });
      }

      // Persist the listing itself.
      await supabase.from('listings').insert({
        'title': title,
        'price': priceValue,
        'category': _selectedCategory,
        'condition': _selectedCondition,
        'description': description,
        'breed': breed,
        'age': age,
        'weight': weight,
        'location': _location,
        'status': 'active',
        'seller_id': userId,
        'image_url': imageUrls.isNotEmpty ? imageUrls.first : null,
        'image_urls': imageUrls,
      });

      // Refresh My Listings from the database so it reflects what's stored.
      await _loadMyListings();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      showTopMessage(context, 'Could not publish listing: $e');
      return;
    }

    if (!mounted) return;
    setState(() {
      _titleController.clear();
      _priceController.clear();
      _descController.clear();
      _breedController.clear();
      _ageController.clear();
      _weightController.clear();
      _weightUnit = 'kg';
      _selectedCategory  = null;
      _selectedCondition = null;
      _pickedImages.clear();
      _uploading = false;
      _selectedTab = 0;
    });

    showTopMessage(
      context,
      'Listing published successfully!',
      isError: false,
      backgroundColor: const Color(0xFF6DBF99),
    );
  }

  /// Asks the user to confirm before permanently deleting a listing.
  Future<void> _confirmDeleteListing(int index) async {
    final title = (_myListings[index]['name'] as String?) ?? 'this listing';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Listing',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Permanently delete "$title"? This action cannot be undone.',
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteListing(index);
  }

  /// Deletes a listing both locally and in Supabase.
  Future<void> _deleteListing(int index) async {
    final id = _myListings[index]['id'];
    setState(() => _myListings.removeAt(index));
    if (id == null) return;
    try {
      // Best-effort Cloudinary cleanup first — the function verifies ownership
      // and reads the image URLs from the row, so it must run before delete.
      await deleteListingImages('$id');
      await supabase.from('listings').delete().eq('id', id);
    } catch (e) {
      if (mounted) showTopMessage(context, 'Could not delete listing: $e');
      await _loadMyListings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 50, bottom: 16, left: 16, right: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF6DBF99),
              borderRadius: BorderRadius.only(
                bottomLeft:  Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white, size: 26),
                    ),
                    GestureDetector(
                      onTap: (_selectedTab == 1 && !_uploading) ? _publishListing : null,
                      child: Text(
                        _uploading ? 'Publishing…' : 'Publish',
                        style: TextStyle(
                          color: (_selectedTab == 1 && !_uploading) ? Colors.white : Colors.white54,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        shape: BoxShape.circle,
                        image: _avatarUrl.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(_avatarUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _avatarUrl.isNotEmpty
                          ? null
                          : const Icon(Icons.person,
                              color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_userName.isEmpty ? 'AniMart User' : _userName,
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const Text('Listing on Marketplace',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _buildTabButton('My Listings', 0),
                    const SizedBox(width: 10),
                    _buildTabButton('Create Listing', 1),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _selectedTab == 0 ? _buildMyListings() : _buildCreateListing(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white24,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF6DBF99) : Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildMyListings() {
    if (_loadingListings) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6DBF99)),
      );
    }

    if (_myListings.isEmpty) {
      return RefreshIndicator(
        color: const Color(0xFF6DBF99),
        onRefresh: _loadMyListings,
        child: ListView(
          children: const [
            SizedBox(height: 160),
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.black26),
            SizedBox(height: 12),
            Text(
              'No listings yet.\nTap "Create Listing" to add one.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black45, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Listings (${_myListings.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _myListings.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (context, index) {
              final item    = _myListings[index];
              final isAsset = item['isAsset'] as bool;

              return GestureDetector(
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProductDetailPage(
                        name:  item['name'] as String,
                        price: item['price'] as String,
                        image: item['image'] as String,
                        images: (item['images'] as List?)?.cast<String>() ?? const [],
                        description: item['description'] as String? ?? '',
                        condition: item['condition'] as String? ?? '',
                        sellerName: _userName,
                        location: item['location'] as String? ?? '',
                        breed: item['breed'] as String? ?? '',
                        age: item['age'] as String? ?? '',
                        weight: item['weight'] as String? ?? '',
                        createdAt: item['createdAt'] as String? ?? '',
                        listingId: '${item['id'] ?? ''}',
                        sellerId: item['sellerId'] as String? ?? '',
                        status: item['status'] as String? ?? 'active',
                      ),
                    ),
                  );
                  if (result == 'deleted') _loadMyListings();
                },
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
                            topLeft:  Radius.circular(10),
                            topRight: Radius.circular(10),
                          ),
                          child: isAsset
                              ? Image.asset(
                                  item['image']!,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _imagePlaceholder(),
                                )
                              : Image.network(
                                  item['image']!,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _imagePlaceholder(),
                                ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['name']!,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(item['price']!,
                                  style: const TextStyle(
                                    color: Color(0xFF6DBF99),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _confirmDeleteListing(index),
                                  child: const Icon(Icons.delete_outline, size: 16, color: Colors.black38),
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
        ],
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: const Color(0xFFD6F0E4),
      child: const Icon(Icons.image_not_supported_outlined, color: Colors.white54, size: 40),
    );
  }

  Widget _buildCreateListing() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_pickedImages.isEmpty)
            GestureDetector(
              onTap: _showPhotoSourceSheet,
              child: Column(
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2A3A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.image_outlined, color: Colors.white, size: 34),
                  ),
                  const SizedBox(height: 8),
                  const Text('Add Photos',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pickedImages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _pickedImages.length) {
                        return GestureDetector(
                          onTap: _showPhotoSourceSheet,
                          child: Container(
                            width: 90,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFF6DBF99), width: 1.5),
                              borderRadius: BorderRadius.circular(10),
                              color: const Color(0xFFD6F0E4),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined,
                                    color: Color(0xFF6DBF99), size: 28),
                                SizedBox(height: 4),
                                Text('Add more',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF6DBF99))),
                              ],
                            ),
                          ),
                        );
                      }
                      return Stack(
                        children: [
                          Container(
                            width: 90,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF6DBF99), width: 1.5),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: Image.memory(
                                _pickedImages[index].bytes,
                                fit: BoxFit.cover,
                                width: 90,
                                height: 100,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 2, right: 10,
                            child: GestureDetector(
                              onTap: () => setState(() => _pickedImages.removeAt(index)),
                              child: Container(
                                width: 20, height: 20,
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 13),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Text('${_pickedImages.length} photo(s) selected',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),

          const SizedBox(height: 24),
          _buildInputField(controller: _titleController, hint: 'Title'),
          const SizedBox(height: 12),
          _buildInputField(
            controller: _priceController,
            hint: 'Price',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            prefixText: '₱ ',
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
          ),
          const SizedBox(height: 12),
          _buildDropdown(
            hint: 'Category',
            value: _selectedCategory,
            items: _categories,
            onChanged: (val) => setState(() => _selectedCategory = val),
          ),
          const SizedBox(height: 12),
          _buildDropdown(
            hint: 'Condition',
            value: _selectedCondition,
            items: _conditions,
            onChanged: (val) => setState(() => _selectedCondition = val),
          ),
          const SizedBox(height: 12),
          _buildInputField(controller: _breedController, hint: 'Breed'),
          const SizedBox(height: 12),
          _buildInputField(controller: _ageController, hint: 'Age (e.g. 3 months)'),
          const SizedBox(height: 12),
          _buildInputField(
            controller: _weightController,
            hint: 'Weight (e.g. 1.5)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            suffix: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _weightUnit,
                isDense: true,
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black38, size: 18),
                style: const TextStyle(color: Colors.black87, fontSize: 14),
                items: const [
                  DropdownMenuItem(value: 'kg', child: Text('kg')),
                  DropdownMenuItem(value: 'lbs', child: Text('lbs')),
                ],
                onChanged: (val) => setState(() => _weightUnit = val ?? 'kg'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _descController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Description',
                hintStyle: TextStyle(color: Colors.black38, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(14),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Location',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6DBF99)),
                ),
                GestureDetector(
                  onTap: () {},
                  child: const Text('Edit',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6DBF99)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Tanauan, Batangas Philippines -4232',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _uploading ? null : _publishListing,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6DBF99),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: _uploading
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white,
                      ),
                    )
                  : const Text('Publish Listing',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    String? prefixText,
    Widget? suffix,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          hintText: hint,
          prefixText: prefixText,
          suffix: suffix,
          hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          hint: Text(hint, style: const TextStyle(color: Colors.black38, fontSize: 14)),
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black38),
          items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}