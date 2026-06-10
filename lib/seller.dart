import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ani_mart/product_detail.dart';

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
  String? _selectedCategory;
  String? _selectedCondition;

  final List<File> _pickedImages = [];
  final ImagePicker _imagePicker = ImagePicker();

  final List<String> _categories  = ['Poultry', 'Small Livestock', 'Large Livestock', 'Aquatics'];
  final List<String> _conditions  = ['Good', 'Excellent', 'Fair'];

  final List<Map<String, dynamic>> _myListings = [
    {'name': 'Chicken',   'price': '₱350',   'image': 'images/chicken.png',  'isAsset': true},
    {'name': 'White Hen', 'price': '₱400',   'image': 'images/whitehen.png', 'isAsset': true},
    {'name': 'Duck',      'price': '₱300',   'image': 'images/duck.png',     'isAsset': true},
    {'name': 'Turkey',    'price': '₱1,200', 'image': 'images/turkey.png',   'isAsset': true},
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descController.dispose();
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
        setState(() {
          _pickedImages.add(File(picked.path));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick image: $e')),
        );
      }
    }
  }

  void _publishListing() {
    final title = _titleController.text.trim();
    final price = _priceController.text.trim();
    if (title.isEmpty || price.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in Title and Price.')),
      );
      return;
    }

    final hasPickedImage = _pickedImages.isNotEmpty;

    setState(() {
      _myListings.insert(0, {
        'name':    title,
        'price':   '₱$price',
        'image':   hasPickedImage ? _pickedImages.first.path : 'images/chicken.png',
        'isAsset': !hasPickedImage,
      });
      _titleController.clear();
      _priceController.clear();
      _descController.clear();
      _selectedCategory  = null;
      _selectedCondition = null;
      _pickedImages.clear();
      _selectedTab = 0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Listing published successfully!'),
        backgroundColor: Color(0xFF6DBF99),
      ),
    );
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
                      onTap: _selectedTab == 1 ? _publishListing : null,
                      child: Text(
                        'Publish',
                        style: TextStyle(
                          color: _selectedTab == 1 ? Colors.white : Colors.white54,
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
                      decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                      child: const Icon(Icons.person, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Rencee Formanes',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        Text('Listing on Marketplace',
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
    if (_myListings.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProductDetailPage(
                        name:  item['name']!,
                        price: item['price']!,
                        image: item['image']!,
                      ),
                    ),
                  );
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
                              : Image.file(
                                  File(item['image']!),
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
                                  onTap: () => setState(() => _myListings.removeAt(index)),
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
                              child: Image.file(
                                _pickedImages[index],
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
            keyboardType: TextInputType.number,
            prefixText: '₱ ',
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
              onPressed: _publishListing,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6DBF99),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('Publish Listing',
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
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          prefixText: prefixText,
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