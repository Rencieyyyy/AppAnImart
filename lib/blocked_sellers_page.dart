import 'package:flutter/material.dart';

import 'services/marketplace_service.dart';
import 'widgets/top_message.dart';

/// "Blocked Sellers" screen (opened from the profile page). Lists every user
/// the signed-in user has blocked, with an Unblock action per row. Unblocking
/// makes that seller's listings visible in the feeds again.
class BlockedSellersPage extends StatefulWidget {
  const BlockedSellersPage({super.key});

  @override
  State<BlockedSellersPage> createState() => _BlockedSellersPageState();
}

class _BlockedSellersPageState extends State<BlockedSellersPage> {
  bool _loading = true;
  List<BlockedUser> _blocked = const [];

  /// Ids with an unblock request in flight, so their button shows a spinner.
  final Set<String> _unblocking = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await MarketplaceService.fetchBlockedUsers();
    if (!mounted) return;
    setState(() {
      _blocked = users;
      _loading = false;
    });
  }

  Future<void> _unblock(BlockedUser user) async {
    if (_unblocking.contains(user.id)) return;
    setState(() => _unblocking.add(user.id));
    final stillBlocked = await MarketplaceService.toggleBlock(
      user.id,
      currentlyBlocked: true,
    );
    if (!mounted) return;
    setState(() {
      _unblocking.remove(user.id);
      if (!stillBlocked) {
        _blocked = _blocked.where((b) => b.id != user.id).toList();
      }
    });
    showTopMessage(
      context,
      stillBlocked
          ? 'Could not unblock ${user.name}. Please try again.'
          : '${user.name} unblocked. Their listings are visible again.',
      isError: stillBlocked,
      backgroundColor: stillBlocked ? null : const Color(0xFF6DBF99),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Blocked Sellers',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6DBF99)))
          : _blocked.isEmpty
              ? RefreshIndicator(
                  color: const Color(0xFF6DBF99),
                  onRefresh: _load,
                  child: ListView(
                    children: const [
                      SizedBox(height: 140),
                      Icon(Icons.block_outlined,
                          size: 60, color: Colors.black26),
                      SizedBox(height: 14),
                      Text(
                        'You haven\'t blocked anyone.\nSellers you block from their listing\npage will show up here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black45, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFF6DBF99),
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _blocked.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _buildBlockedRow(_blocked[index]),
                  ),
                ),
    );
  }

  Widget _buildBlockedRow(BlockedUser user) {
    final busy = _unblocking.contains(user.id);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEDED)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
                color: Color(0xFFD6F0E4), shape: BoxShape.circle),
            clipBehavior: Clip.antiAlias,
            child: user.avatarUrl.isNotEmpty
                ? Image.network(user.avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, e, s) => const Icon(Icons.person,
                        color: Color(0xFF6DBF99), size: 22))
                : const Icon(Icons.person, color: Color(0xFF6DBF99), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
                const Text('Listings hidden from your feed',
                    style: TextStyle(fontSize: 12, color: Colors.black45)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: busy ? null : () => _unblock(user),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF6DBF99)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF6DBF99)),
                    )
                  : const Text('Unblock',
                      style: TextStyle(
                          color: Color(0xFF1D9E75),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
