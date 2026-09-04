import 'package:flutter/material.dart';
import 'package:ani_mart/product_detail.dart';
import 'cloudinary_function.dart';
import 'friendly_error.dart';
import 'main.dart';
import 'widgets/top_message.dart';

/// Shows every listing published by a single user (seller).
///
/// When the signed-in user is viewing their *own* listings, a gallery-style
/// multi-select mode (long-press to start, tap to toggle) lets them delete or
/// disable/enable several posts at once.
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

  // ── Multi-select state ────────────────────────────────────────────────────
  bool _selectionMode = false;
  // Listing ids (stringified, so int and uuid keys both work) that are picked.
  final Set<String> _selectedIds = {};
  // True while a batch delete / status change is running.
  bool _busy = false;

  /// Only the owner of these listings may manage (select/delete/disable) them.
  bool get _isOwner => supabase.auth.currentUser?.id == widget.userId;

  /// The raw `id` values (int or uuid) of the currently selected rows.
  List<dynamic> get _selectedRawIds => _listings
      .where((r) => _selectedIds.contains('${r['id']}'))
      .map((r) => r['id'])
      .toList();

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
        // Drop any selections that no longer exist after a refresh.
        _selectedIds.removeWhere(
            (id) => !_listings.any((r) => '${r['id']}' == id));
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

  // ── Selection helpers ──────────────────────────────────────────────────────
  void _enterSelection(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
      // Leaving zero selected keeps selection mode on (matches phone galleries),
      // so the user can keep picking; they exit via the close button.
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _listings.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(_listings.map((r) => '${r['id']}'));
      }
    });
  }

  // ── Batch operations ───────────────────────────────────────────────────────
  Future<void> _deleteSelected() async {
    final ids = _selectedRawIds;
    if (ids.isEmpty || _busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete listings',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
        content: Text(
          ids.length == 1
              ? 'Delete this listing? This cannot be undone.'
              : 'Delete ${ids.length} listings? This cannot be undone.',
          style: const TextStyle(color: Color(0xFF6B8578)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6B8578))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53E3E),
              foregroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      for (final id in ids) {
        // Best-effort Cloudinary cleanup first (verifies ownership + reads the
        // image URLs from the row), then remove the row itself.
        await deleteListingImages('$id');
        await supabase.from('listings').delete().eq('id', id);
      }
      if (!mounted) return;
      _exitSelection();
      await _loadListings();
      if (mounted) {
        showTopMessage(context,
            ids.length == 1 ? 'Listing deleted.' : '${ids.length} listings deleted.',
            isError: false, backgroundColor: const Color(0xFF6DBF99));
      }
    } catch (e) {
      debugPrint('Bulk delete failed: $e');
      if (mounted) {
        showTopMessage(
            context,
            friendlyError(e,
                action: 'bulk_delete_listings',
                fallback: 'Could not delete those listings. '
                    'Please try again.'));
      }
      await _loadListings();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sets the status of every selected listing to [newStatus]
  /// ('disabled' hides it from buyers, 'active' makes it public again).
  Future<void> _setStatusSelected(String newStatus) async {
    final ids = _selectedRawIds;
    if (ids.isEmpty || _busy) return;

    setState(() => _busy = true);
    try {
      await supabase
          .from('listings')
          .update({'status': newStatus}).inFilter('id', ids);
      if (!mounted) return;
      _exitSelection();
      await _loadListings();
      if (mounted) {
        showTopMessage(
          context,
          newStatus == 'disabled'
              ? (ids.length == 1
                  ? 'Listing disabled. Buyers can no longer see it.'
                  : '${ids.length} listings disabled.')
              : (ids.length == 1
                  ? 'Listing enabled and visible to buyers.'
                  : '${ids.length} listings enabled.'),
          isError: false,
          backgroundColor: const Color(0xFF6DBF99),
        );
      }
    } catch (e) {
      debugPrint('Bulk status update failed: $e');
      if (mounted) {
        showTopMessage(
            context,
            friendlyError(e,
                action: 'bulk_update_listing_status',
                fallback: 'Could not update those listings. '
                    'Please try again.'));
      }
      await _loadListings();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.userName.trim().isEmpty
        ? 'Listings'
        : "${widget.userName}'s Listings";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(title),
      bottomNavigationBar:
          _selectionMode && _isOwner ? _buildSelectionBar() : null,
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

  PreferredSizeWidget _buildAppBar(String title) {
    if (_selectionMode && _isOwner) {
      final allSelected =
          _listings.isNotEmpty && _selectedIds.length == _listings.length;
      return AppBar(
        backgroundColor: const Color(0xFF3AA876),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : _exitSelection,
        ),
        title: Text('${_selectedIds.length} selected',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _busy ? null : _toggleSelectAll,
            child: Text(allSelected ? 'Clear all' : 'Select all',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      );
    }
    return AppBar(
      backgroundColor: const Color(0xFF6DBF99),
      foregroundColor: Colors.white,
      elevation: 0,
      title: Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      actions: [
        if (_isOwner && _listings.isNotEmpty)
          IconButton(
            tooltip: 'Select listings',
            icon: const Icon(Icons.checklist_rounded),
            onPressed: () => setState(() => _selectionMode = true),
          ),
      ],
    );
  }

  /// Bottom action bar shown in selection mode: Enable, Disable, Delete.
  Widget _buildSelectionBar() {
    final hasSelection = _selectedIds.isNotEmpty;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.black.withOpacity(0.08))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: _busy
            ? const SizedBox(
                height: 56,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Color(0xFF3AA876)),
                  ),
                ),
              )
            : Row(
                children: [
                  _barAction(
                    icon: Icons.visibility_outlined,
                    label: 'Enable',
                    color: const Color(0xFF3AA876),
                    enabled: hasSelection,
                    onTap: () => _setStatusSelected('active'),
                  ),
                  _barAction(
                    icon: Icons.visibility_off_outlined,
                    label: 'Disable',
                    color: const Color(0xFFFF9800),
                    enabled: hasSelection,
                    onTap: () => _setStatusSelected('disabled'),
                  ),
                  _barAction(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    color: const Color(0xFFE53E3E),
                    enabled: hasSelection,
                    onTap: _deleteSelected,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _barAction({
    required IconData icon,
    required String label,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final effective = enabled ? color : Colors.black26;
    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: effective, size: 24),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      color: effective,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listingCard(Map<String, dynamic> row) {
    final id = '${row['id']}';
    final title = (row['title'] as String?) ?? 'Untitled';
    final price = _formatPrice(row['price']);
    final imageUrl = (row['image_url'] as String?)?.trim() ?? '';
    final image = imageUrl.isNotEmpty ? imageUrl : 'images/chicken.png';
    final status = ((row['status'] as String?) ?? 'active');
    final isDisabled = status.toLowerCase() != 'active';
    final selected = _selectedIds.contains(id);

    void openDetail() async {
      final result = await Navigator.push(
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
            createdAt: '${row['created_at'] ?? ''}',
            listingId: id,
            sellerId: '${row['seller_id'] ?? ''}',
            status: status,
          ),
        ),
      );
      // Detail page can delete or toggle status; refresh to reflect changes.
      if (result == 'deleted' || result == 'updated') _loadListings();
    }

    return GestureDetector(
      onTap: () {
        if (_selectionMode && _isOwner) {
          _toggleSelection(id);
        } else {
          openDetail();
        }
      },
      onLongPress: _isOwner
          ? () {
              if (!_selectionMode) {
                _enterSelection(id);
              } else {
                _toggleSelection(id);
              }
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? const Color(0xFF3AA876) : const Color(0xFF6DBF99),
            width: selected ? 2.5 : 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10),
                    ),
                    child: Opacity(
                      opacity: isDisabled ? 0.45 : 1,
                      child: _listingImage(image),
                    ),
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

            // "Disabled" badge so the owner can see hidden posts at a glance.
            if (isDisabled)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Disabled',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold)),
                ),
              ),

            // Selection checkbox overlay (only in selection mode, owner only).
            if (_selectionMode && _isOwner)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF3AA876) : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color:
                            selected ? const Color(0xFF3AA876) : Colors.black38,
                        width: 2),
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
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
