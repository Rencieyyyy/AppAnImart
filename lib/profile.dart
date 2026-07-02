import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dashboard.dart';
import 'buyer.dart';
import 'announcement_page.dart';
import 'login.dart';
import 'main.dart';
import 'product_detail.dart';
import 'user_listings.dart';
import 'seller.dart';
import 'seller_analytics.dart';
import 'widgets/top_message.dart';
import 'cloudinary_function.dart';
import 'support_chat.dart';
import 'services/location_service.dart';
import 'services/marketplace_service.dart';
import 'services/subscription_service.dart';
import 'seller_reviews.dart';
import 'widgets/city_picker.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int _selectedIndex = 3;

  // ── Signed-in user data (loaded from the `users` table) ───────────────────
  bool _loadingProfile = true;
  String _name = '';
  String _email = '';
  String _phone = '';
  String _address = '';
  String _houseNumber = '';
  String _businessName = '';
  // Shop details captured when the user becomes a seller. Shown in the
  // "Details" section once `_isSeller` is true.
  String _shopCategory = '';
  String _shopDescription = '';
  String _paymentNumber = '';
  // App-facing name of the user's active subscription plan (from the
  // `subscriptions` table managed by the admin website). 'Free' by default.
  String _planName = 'Free';
  String _memberSince = '';
  String _avatarUrl = '';
  bool _isSeller = false;
  int _salesCount = 0;
  int _trustScore = 0;
  SellerRating _reviewRating = SellerRating.empty;

  // ── Listings owned by the signed-in user (from the `listings` table) ──────
  List<Map<String, dynamic>> _myListings = [];
  bool _loadingListings = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadMyListings();
    _loadReviewRating();
  }

  /// Loads the rating this user has received as a seller. When they have
  /// reviews, the average drives the displayed Trust Score.
  Future<void> _loadReviewRating() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final rating = await MarketplaceService.fetchSellerRating(user.id);
    if (!mounted) return;
    setState(() {
      _reviewRating = rating;
      if (rating.hasReviews) _trustScore = rating.trustPercent;
    });
  }

  void _openMyReviews() {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SellerReviewsPage(sellerId: user.id, sellerName: _name),
      ),
    ).then((_) => _loadReviewRating());
  }

  Future<void> _loadMyListings() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingListings = false);
      return;
    }
    try {
      final rows = await supabase
          .from('listings')
          .select()
          .eq('seller_id', user.id)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _myListings =
            (rows as List).map((r) => r as Map<String, dynamic>).toList();
        _loadingListings = false;
      });
    } catch (e) {
      debugPrint('Failed to load listings: $e');
      if (mounted) setState(() => _loadingListings = false);
    }
  }

  String _formatPrice(dynamic raw) {
    final value = raw is num ? raw : (num.tryParse('$raw') ?? 0);
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
    return '₱$text';
  }

  void _openAllListings() {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserListingsPage(userId: user.id, userName: _name),
      ),
      // Listings may have been deleted/disabled there, so refresh on return.
      // This keeps the "Seller" indicator in sync — it disappears once the
      // user has no listings left.
    ).then((_) => _loadMyListings());
  }

  String _relativeTime(dynamic isoDate) {
    final dt = DateTime.tryParse('$isoDate');
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 1) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    if (diff.inHours >= 1) return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} min ago';
    return 'Just now';
  }

  Future<void> _loadProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingProfile = false);
      return;
    }
    try {
      final row = await supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;
      final data = row ?? <String, dynamic>{};
      setState(() {
        _email = (data['email'] as String?) ?? user.email ?? '';
        _name = (data['name'] as String?)?.trim().isNotEmpty == true
            ? data['name'] as String
            : (_email.isNotEmpty ? _email.split('@').first : 'AniMart User');
        _phone = (data['phone'] as String?) ?? '';
        _address = (data['address'] as String?) ?? '';
        _houseNumber = (data['house_number'] as String?) ?? '';
        _businessName = (data['business_name'] as String?) ?? '';
        _shopCategory = (data['shop_category'] as String?) ?? '';
        _shopDescription = (data['shop_description'] as String?) ?? '';
        _paymentNumber = (data['payment_number'] as String?) ?? '';
        _avatarUrl = (data['avatar_url'] as String?) ?? '';
        _isSeller = (data['is_seller'] as bool?) ?? false;
        _salesCount = (data['sales_count'] as int?) ?? 0;
        _trustScore = (data['trust_score'] as int?) ?? 0;
        _memberSince = _formatMemberSince(
            (data['member_since'] as String?) ?? user.createdAt);
        _loadingProfile = false;
      });

      // Resolve the active subscription plan (Free / Premium / Super Premium)
      // from the admin-managed `subscriptions` table.
      final planName = await SubscriptionService.activePlanLabel();
      if (mounted) setState(() => _planName = planName);
    } catch (e) {
      debugPrint('Failed to load profile from users table: $e');
      if (!mounted) return;
      // Fall back to the auth user so the screen still renders.
      setState(() {
        _email = user.email ?? '';
        _name = _email.isNotEmpty ? _email.split('@').first : 'AniMart User';
        _memberSince = _formatMemberSince(user.createdAt);
        _loadingProfile = false;
      });
    }
  }

  String _formatMemberSince(String? isoDate) {
    if (isoDate == null) return '';
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return 'Member since ${months[dt.month - 1]} ${dt.year}';
  }

  String get _initial => _name.trim().isNotEmpty ? _name.trim()[0].toUpperCase() : 'U';

  /// Whether the user has published at least one listing — drives the "Seller"
  /// label shown under their name.
  bool get _hasListings => _myListings.isNotEmpty;

  /// Whether the active subscription is a paid tier (Premium / Super Premium).
  /// Only these tiers earn the "Verified Seller" badge.
  bool get _isPremiumTier =>
      _planName == 'Premium' || _planName == 'Super Premium';

  // ── Bottom Nav ────────────────────────────────────────────────────────────
  void _onTabTapped(int index) {
    if (index == _selectedIndex) return;
    switch (index) {
      case 0:
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const DashboardPage()),
          (route) => false,
        );
        break;
      case 1:
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const BuyerPage()),
          (route) => false,
        );
        break;
      case 2:
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AnnouncementPage()),
          (route) => false,
        );
        break;
      case 3:
        break;
    }
  }

  // ── Log Out ───────────────────────────────────────────────────────────────
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Log Out',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2E22)),
        ),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: Color(0xFF6B8578)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B8578))),
          ),
          ElevatedButton(
            onPressed: () {
              final navigator = Navigator.of(context);
              // Close the dialog and leave for the login screen immediately so
              // the user is never stuck if the network sign-out call is slow.
              navigator.pop();
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
              // Clear the Supabase session in the background; ignore network
              // errors since the local session is cleared regardless.
              supabase.auth.signOut().catchError((_) {});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53E3E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  // ── Edit Profile ──────────────────────────────────────────────────────────
  // Opens a full-screen edit page (list-row layout) for the profile fields.
  Future<void> _showEditProfile() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _EditProfilePage(
          initialName: _name,
          initialPhone: _phone,
          initialAddress: _address,
          initialHouse: _houseNumber,
          initialAvatarUrl: _avatarUrl,
          email: _email,
          memberSince: _memberSince,
          isSeller: _isSeller,
          initialBusinessName: _businessName,
          initialShopCategory: _shopCategory,
          initialShopDescription: _shopDescription,
          initialPaymentNumber: _paymentNumber,
          onSave: _saveProfile,
          onAvatarChanged: (url) {
            if (mounted) setState(() => _avatarUrl = url);
          },
        ),
      ),
    );
    if (saved == true && mounted) {
      _showMessage('Profile updated successfully!', const Color(0xFF3AA876));
    }
  }

  /// Persists the edited profile fields to the `users` table.
  /// Returns null on success, or an error message describing why it failed.
  Future<String?> _saveProfile({
    required String name,
    required String phone,
    required String address,
    required String houseNumber,
    required String businessName,
    required String shopCategory,
    required String shopDescription,
    required String paymentNumber,
    PhCity? location,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null || supabase.auth.currentSession == null) {
      return 'You are not signed in. Please log in again.';
    }

    try {
      // Update only the editable columns of the user's existing row, keyed by
      // the auth user id. We deliberately don't touch columns like `plan`
      // (which has a CHECK constraint) so editing the profile can't break them.
      final row = await supabase
          .from('users')
          .update({
            'name': name,
            'phone': phone,
            'address': address,
            'house_number': houseNumber,
            'business_name': businessName,
            'shop_category': shopCategory,
            'shop_description': shopDescription,
            'payment_number': paymentNumber,
            // Coordinates power "Explore near you" distances.
            if (location != null) 'location_name': location.label,
            if (location != null) 'latitude': location.lat,
            if (location != null) 'longitude': location.lng,
          })
          .eq('id', user.id)
          .select()
          .maybeSingle();

      if (row == null) {
        return 'Your account has no profile record yet. Please contact support.';
      }

      // Re-base everything this user has posted onto their new location so
      // their listings show (and are ranked by) where they now live.
      if (location != null) {
        try {
          await supabase
              .from('listings')
              .update({'location': location.label})
              .eq('seller_id', user.id);
        } catch (e) {
          debugPrint('Could not re-base listings location: $e');
        }
      }

      if (mounted) {
        setState(() {
          _name = (row['name'] as String?)?.trim().isNotEmpty == true
              ? row['name'] as String
              : name;
          _phone = (row['phone'] as String?) ?? phone;
          _address = (row['address'] as String?) ?? address;
          _houseNumber = (row['house_number'] as String?) ?? houseNumber;
          _businessName = (row['business_name'] as String?) ?? businessName;
          _shopCategory = (row['shop_category'] as String?) ?? shopCategory;
          _shopDescription = (row['shop_description'] as String?) ?? shopDescription;
          _paymentNumber = (row['payment_number'] as String?) ?? paymentNumber;
        });
      }
      return null;
    } on PostgrestException catch (e) {
      debugPrint('Profile update PostgrestException: ${e.message}');
      return e.message;
    } catch (e) {
      debugPrint('Profile update error: $e');
      return e.toString();
    }
  }

  /// Persists the shop details to the `users` table when a user becomes a
  /// seller. Returns null on success, or an error message describing the
  /// failure. State is updated optimistically by the caller, so on failure we
  /// surface the message but keep the entered values on screen.
  Future<String?> _saveSellerDetails({
    required String businessName,
    required String shopDescription,
    required String shopCategory,
    required String paymentNumber,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null || supabase.auth.currentSession == null) {
      return 'You are not signed in. Please log in again.';
    }
    try {
      final row = await supabase
          .from('users')
          .update({
            'is_seller': true,
            'business_name': businessName,
            'shop_description': shopDescription,
            'shop_category': shopCategory,
            'payment_number': paymentNumber,
          })
          .eq('id', user.id)
          .select()
          .maybeSingle();

      if (row == null) {
        return 'Your account has no profile record yet. Please contact support.';
      }
      return null;
    } on PostgrestException catch (e) {
      debugPrint('Seller details update PostgrestException: ${e.message}');
      return e.message;
    } catch (e) {
      debugPrint('Seller details update error: $e');
      return e.toString();
    }
  }

  Widget _editField(TextEditingController ctrl, String hint, IconData icon,
      {TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1A2E22)),
      cursorColor: const Color(0xFF3AA876),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF6DBF99)),
        filled: true,
        fillColor: const Color(0xFFF4FAF7),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDCEFE6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF6DBF99), width: 1.5),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDCEFE6)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  // ── Send Message ──────────────────────────────────────────────────────────
  void _showSendMessage() {
    final msgCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Send a Message',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Send a message to admin or support.',
                    style: TextStyle(fontSize: 13, color: Colors.black38)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: msgCtrl,
                maxLines: 4,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Type your message here...',
                  hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF4FAF7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (msgCtrl.text.trim().isEmpty) return;
                    Navigator.pop(ctx);
                    _showMessage('Message sent!', const Color(0xFF2196F3));
                  },
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Send Message', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Customer Service ──────────────────────────────────────────────────────
  void _showCustomerService() {
    final bool chatOnline = DateTime.now().hour >= 8 && DateTime.now().hour < 17;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, 24 + MediaQuery.of(ctx).padding.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44, height: 5,
                decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(height: 22),
              Container(
                width: 66, height: 66,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3AA876), Color(0xFF2E8B63)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3AA876).withOpacity(0.32),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.support_agent_rounded,
                    color: Colors.white, size: 34),
              ),
              const SizedBox(height: 14),
              const Text('Customer Service',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A2E22))),
              const SizedBox(height: 6),
              const Text(
                'We\'re here to help! Reach us through any of the\nchannels below.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black45, height: 1.45),
              ),
              const SizedBox(height: 22),
              _serviceRow(
                icon: Icons.phone_rounded,
                title: 'Call Us',
                subtitle: '+63 912 345 6789',
                color: const Color(0xFF3AA876),
                actionLabel: 'Copy',
                onTap: () => _copyContact('Phone number', '+63 912 345 6789'),
              ),
              const SizedBox(height: 12),
              _serviceRow(
                icon: Icons.email_outlined,
                title: 'Email Us',
                subtitle: 'support@animart.ph',
                color: const Color(0xFF2196F3),
                actionLabel: 'Copy',
                onTap: () => _copyContact('Email', 'support@animart.ph'),
              ),
              const SizedBox(height: 12),
              _serviceRow(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Live Chat',
                subtitle: chatOnline
                    ? 'Online now · Typically replies in minutes'
                    : 'Available 8AM – 5PM',
                color: const Color(0xFFFFB300),
                actionLabel: 'Open',
                actionIcon: Icons.arrow_forward_rounded,
                online: chatOnline,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SupportChatPage()),
                  );
                },
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6F5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.schedule_rounded,
                        size: 18, color: Color(0xFF3AA876)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Average response time under 24 hours.',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.black54,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: const Color(0xFFF2F4F3),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Close',
                      style: TextStyle(
                          color: Color(0xFF1A2E22),
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyContact(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    showTopMessage(context, '$label copied to clipboard',
        isError: false, icon: Icons.copy_rounded);
  }

  Widget _serviceRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    required String actionLabel,
    IconData actionIcon = Icons.copy_rounded,
    bool online = false,
  }) {
    return Material(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                  color: Color(0xFF1A2E22))),
                        ),
                        if (online) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                                color: const Color(0xFF3AA876).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                _Dot(),
                                SizedBox(width: 5),
                                Text('Online',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF3AA876))),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12.5, color: Colors.black54)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(actionIcon, size: 14, color: color),
                    const SizedBox(width: 5),
                    Text(actionLabel,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: color)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Rate Us ───────────────────────────────────────────────────────────────
  void _showRateUs() {
    int selectedStars = 0;
    final feedbackCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx2, setLocal) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 20),
                const Text('Rate Our App',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                const SizedBox(height: 6),
                const Text('Your feedback helps us improve!',
                    style: TextStyle(fontSize: 13, color: Colors.black45)),
                const SizedBox(height: 20),
                // Stars
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    return GestureDetector(
                      onTap: () => setLocal(() => selectedStars = i + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          i < selectedStars ? Icons.star_rounded : Icons.star_border_rounded,
                          size: 40,
                          color: const Color(0xFFFFB300),
                        ),
                      ),
                    );
                  }),
                ),
                if (selectedStars > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    ['', 'Poor', 'Fair', 'Good', 'Very Good', 'Excellent!'][selectedStars],
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFFFB300)),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: feedbackCtrl,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Leave a comment (optional)',
                    hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFF4FAF7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selectedStars == 0
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _showMessage(
                                'Thanks for your rating! ⭐', const Color(0xFFFFB300));
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB300),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.black12,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Submit Rating', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Premium Subscription page ─────────────────────────────────────────────

  void _openPlansPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _PremiumSubscriptionPage()),
    );
  }

  // ── View Comments (listing card) ──────────────────────────────────────────
  void _showListingComments() {
    final List<Map<String, String>> comments = [
      {'user': 'Maria Santos', 'text': 'How much per kilo?', 'time': '2 days ago'},
      {'user': 'Pedro Reyes', 'text': 'Still available?', 'time': '1 day ago'},
    ];
    final commentCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setLocal) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Comments (${comments.length})',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close, color: Colors.black45, size: 20),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(height: 18, thickness: 0.5),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: comments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final c = comments[i];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFF6DBF99).withOpacity(0.2),
                          child: Text(c['user']![0],
                              style: const TextStyle(color: Color(0xFF3AA876), fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF4FAF7),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF6DBF99).withOpacity(0.2)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c['user']!,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF1A2E22))),
                                    const SizedBox(height: 2),
                                    Text(c['text']!,
                                        style: const TextStyle(fontSize: 13, color: Color(0xFF3D5247), height: 1.4)),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 4, top: 3),
                                child: Text(c['time']!,
                                    style: const TextStyle(fontSize: 10, color: Colors.black38)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Container(
                padding: EdgeInsets.only(
                    left: 16, right: 16, top: 10,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.black.withOpacity(0.07))),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(0xFF6DBF99),
                      child: Text('J', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4FAF7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF6DBF99).withOpacity(0.3)),
                        ),
                        child: TextField(
                          controller: commentCtrl,
                          style: const TextStyle(fontSize: 13),
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) {
                            if (commentCtrl.text.trim().isEmpty) return;
                            setLocal(() {
                              comments.add({'user': 'John Smith', 'text': commentCtrl.text.trim(), 'time': 'Just now'});
                            });
                            commentCtrl.clear();
                          },
                          decoration: const InputDecoration(
                            hintText: 'Write a comment...',
                            hintStyle: TextStyle(color: Colors.black38, fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        if (commentCtrl.text.trim().isEmpty) return;
                        setLocal(() {
                          comments.add({'user': 'John Smith', 'text': commentCtrl.text.trim(), 'time': 'Just now'});
                        });
                        commentCtrl.clear();
                      },
                      child: Container(
                        width: 38, height: 38,
                        decoration: const BoxDecoration(color: Color(0xFF6DBF99), shape: BoxShape.circle),
                        child: const Icon(Icons.send_rounded, color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Become a Seller ────────────────────────────────────────────────────────
  void _showBecomeSeller() {
    if (_isSeller) {
      _showSellerDashboard();
      return;
    }

    final shopNameCtrl = TextEditingController();
    final shopDescCtrl = TextEditingController();
    final bankCtrl = TextEditingController();
    String? selectedCategory;
    const categories = ['Poultry', 'Livestock', 'Aquatics', 'Mixed / All'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx2, setLocal) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F8F1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.storefront_rounded, color: Color(0xFF3AA876), size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Become a Seller',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                          Text('Start selling your animals & products',
                              style: TextStyle(fontSize: 12, color: Colors.black45)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Benefits banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F8F1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFC2EDD9)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Seller Benefits', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1A2E22))),
                        SizedBox(height: 8),
                        _BenefitRow(icon: Icons.storefront_outlined, text: 'List your animals & products'),
                        SizedBox(height: 4),
                        _BenefitRow(icon: Icons.people_outline, text: 'Reach thousands of buyers'),
                        SizedBox(height: 4),
                        _BenefitRow(icon: Icons.payments_outlined, text: 'Secure & easy payments'),
                        SizedBox(height: 4),
                        _BenefitRow(icon: Icons.analytics_outlined, text: 'Track your sales & listings'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text('Shop Details',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                  const SizedBox(height: 10),

                  _editField(shopNameCtrl, 'Shop / Farm Name', Icons.store_outlined),
                  const SizedBox(height: 10),
                  _editField(shopDescCtrl, 'Shop Description', Icons.description_outlined),
                  const SizedBox(height: 10),

                  // Category picker
                  GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: ctx,
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (_) => Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 40, height: 4,
                                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text('Select Category',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                              const SizedBox(height: 12),
                              ...categories.map((cat) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(cat, style: const TextStyle(fontSize: 14)),
                                    trailing: selectedCategory == cat
                                        ? const Icon(Icons.check_circle_rounded, color: Color(0xFF6DBF99))
                                        : null,
                                    onTap: () {
  setLocal(() => selectedCategory = cat);
  Navigator.pop(context);
},
                                  )),
                            ],
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4FAF7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.category_outlined, size: 18, color: Color(0xFF6DBF99)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selectedCategory ?? 'Select Category',
                              style: TextStyle(
                                fontSize: 14,
                                color: selectedCategory != null ? Colors.black87 : Colors.black38,
                              ),
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black38, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _editField(bankCtrl, 'GCash / Bank Number for Payments', Icons.account_balance_outlined),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (shopNameCtrl.text.trim().isEmpty || selectedCategory == null) {
                          _showMessage(
                              'Please fill in all required fields.', Colors.redAccent);
                          return;
                        }
                        final businessName = shopNameCtrl.text.trim();
                        final shopDescription = shopDescCtrl.text.trim();
                        final shopCategory = selectedCategory ?? '';
                        final paymentNumber = bankCtrl.text.trim();

                        Navigator.pop(ctx);
                        // Optimistically reflect the new seller state, then
                        // persist to the database.
                        setState(() {
                          _isSeller = true;
                          _businessName = businessName;
                          _shopDescription = shopDescription;
                          _shopCategory = shopCategory;
                          _paymentNumber = paymentNumber;
                        });
                        final error = await _saveSellerDetails(
                          businessName: businessName,
                          shopDescription: shopDescription,
                          shopCategory: shopCategory,
                          paymentNumber: paymentNumber,
                        );
                        if (!mounted) return;
                        if (error != null) {
                          _showMessage(
                              'Saved on this device, but syncing failed: $error',
                              Colors.redAccent);
                        } else {
                          _showMessage('🎉 You are now a Seller! Welcome aboard.',
                              const Color(0xFF3AA876));
                        }
                      },
                      icon: const Icon(Icons.storefront_rounded, size: 18),
                      label: const Text('Submit & Become a Seller',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3AA876),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Seller Dashboard (after becoming seller) ───────────────────────────────
  void _showSellerDashboard() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF4FAF7),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('My Seller Dashboard',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close, color: Colors.black45, size: 22),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  children: [
                    // Stats row
                    Row(
                      children: [
                        _dashStat('${_myListings.length}', 'Listings', const Color(0xFF3AA876)),
                        const SizedBox(width: 12),
                        _dashStat('$_salesCount', 'Sales', const Color(0xFF2196F3)),
                        const SizedBox(width: 12),
                        _dashStat('₱0', 'Earnings', const Color(0xFFFFB300)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Quick actions
                    const Text('Quick Actions',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                    const SizedBox(height: 10),
                    _dashAction(Icons.add_circle_outline, 'Add New Listing', 'Post a new animal or product', const Color(0xFF3AA876),
                        onTap: () {
                      Navigator.pop(ctx);
                      _openSeller(initialTab: 1);
                    }),
                    const SizedBox(height: 8),
                    _dashAction(Icons.bar_chart_rounded, 'View Sales', 'Track your orders and earnings', const Color(0xFF2196F3),
                        onTap: () {
                      Navigator.pop(ctx);
                      _openSeller(initialTab: 0);
                    }),
                    const SizedBox(height: 8),
                    _dashAction(Icons.reviews_outlined, 'My Reviews', 'See buyer feedback', const Color(0xFFFFB300),
                        onTap: () {
                      Navigator.pop(ctx);
                      _openMyReviews();
                    }),
                    const SizedBox(height: 8),
                    _dashAction(Icons.settings_outlined, 'Shop Settings', 'Update your shop info', Colors.black38,
                        onTap: () {
                      Navigator.pop(ctx);
                      _showShopSettings();
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the seller listings page on the given tab (0 = My Listings,
  /// 1 = Create Listing) and refreshes this page's listings on return.
  Future<void> _openSeller({int initialTab = 0}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SellerPage(initialTab: initialTab)),
    );
    if (mounted) _loadMyListings();
  }

  /// Shop Settings — edit and persist the seller's shop details.
  void _showShopSettings() {
    final shopNameCtrl = TextEditingController(text: _businessName);
    final shopDescCtrl = TextEditingController(text: _shopDescription);
    final bankCtrl = TextEditingController(text: _paymentNumber);
    String? selectedCategory = _shopCategory.isNotEmpty ? _shopCategory : null;
    const categories = ['Poultry', 'Livestock', 'Aquatics', 'Mixed / All'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx2, setLocal) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F8F1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.settings_outlined, color: Color(0xFF3AA876), size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Shop Settings',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                          Text('Update your shop info',
                              style: TextStyle(fontSize: 12, color: Colors.black45)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _editField(shopNameCtrl, 'Shop / Farm Name', Icons.store_outlined),
                  const SizedBox(height: 10),
                  _editField(shopDescCtrl, 'Shop Description', Icons.description_outlined),
                  const SizedBox(height: 10),

                  // Category picker
                  GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: ctx,
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (_) => Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 40, height: 4,
                                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text('Select Category',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                              const SizedBox(height: 12),
                              ...categories.map((cat) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(cat, style: const TextStyle(fontSize: 14)),
                                    trailing: selectedCategory == cat
                                        ? const Icon(Icons.check_circle_rounded, color: Color(0xFF6DBF99))
                                        : null,
                                    onTap: () {
                                      setLocal(() => selectedCategory = cat);
                                      Navigator.pop(context);
                                    },
                                  )),
                            ],
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4FAF7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.category_outlined, size: 18, color: Color(0xFF6DBF99)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selectedCategory ?? 'Select Category',
                              style: TextStyle(
                                fontSize: 14,
                                color: selectedCategory != null ? Colors.black87 : Colors.black38,
                              ),
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black38, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _editField(bankCtrl, 'GCash / Bank Number for Payments', Icons.account_balance_outlined),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (shopNameCtrl.text.trim().isEmpty || selectedCategory == null) {
                          _showMessage(
                              'Please fill in all required fields.', Colors.redAccent);
                          return;
                        }
                        final businessName = shopNameCtrl.text.trim();
                        final shopDescription = shopDescCtrl.text.trim();
                        final shopCategory = selectedCategory ?? '';
                        final paymentNumber = bankCtrl.text.trim();

                        Navigator.pop(ctx);
                        setState(() {
                          _businessName = businessName;
                          _shopDescription = shopDescription;
                          _shopCategory = shopCategory;
                          _paymentNumber = paymentNumber;
                        });
                        final error = await _saveSellerDetails(
                          businessName: businessName,
                          shopDescription: shopDescription,
                          shopCategory: shopCategory,
                          paymentNumber: paymentNumber,
                        );
                        if (!mounted) return;
                        if (error != null) {
                          _showMessage(
                              'Saved on this device, but syncing failed: $error',
                              Colors.redAccent);
                        } else {
                          _showMessage('Shop details updated.', const Color(0xFF3AA876));
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Save Changes',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3AA876),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashStat(String val, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(val, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.black45)),
          ],
        ),
      ),
    );
  }

  Widget _dashAction(IconData icon, String title, String subtitle, Color color,
      {required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: color)),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.black38)),
                ],
              ),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded, color: Colors.black26, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top message helper ────────────────────────────────────────────────────
  void _showMessage(String msg, Color color) {
    showTopMessage(
      context,
      msg,
      isError: color == Colors.redAccent,
      backgroundColor: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAF7),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 44, bottom: 16, left: 16, right: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF6DBF99),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back arrow + centered title on a single row.
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: () {
                            if (Navigator.canPop(context)) Navigator.pop(context);
                          },
                          child: const Icon(Icons.arrow_back,
                              color: Colors.white, size: 24),
                        ),
                      ),
                      const Text('PROFILE',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                              color: Colors.white, letterSpacing: 1.5)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar with seller badge
                      Stack(
                        children: [
                          Container(
                            width: 70, height: 70,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4A9B73),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.6), width: 2),
                              image: _avatarUrl.isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(_avatarUrl),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _avatarUrl.isNotEmpty
                                ? null
                                : const Icon(Icons.person, color: Colors.white, size: 40),
                          ),
                          if (_hasListings)
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFB300),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                                child: const Text('SELLER',
                                    style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Tapping the name (with its ">" indicator) opens Edit Profile.
                            GestureDetector(
                              onTap: _showEditProfile,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(_loadingProfile ? 'Loading…' : _name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.chevron_right, color: Colors.white, size: 22),
                                ],
                              ),
                            ),
                            if (_isPremiumTier) ...[
                              const SizedBox(height: 5),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  // "Verified Seller" is reserved for paid tiers
                                  // (Premium / Super Premium).
                                  if (_isPremiumTier)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2196F3),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('Verified Seller',
                                          style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Sized to match the avatar's height (70), a touch wider.
                      GestureDetector(
                        onTap: _showSendMessage,
                        child: Container(
                          width: 92,
                          height: 70,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2196F3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.messenger_outline, color: Colors.white, size: 18),
                              SizedBox(height: 4),
                              Text('Send me a\nMessage',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Become a Seller Banner ──────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: _showBecomeSeller,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isSeller
                          ? [const Color(0xFF3AA876), const Color(0xFF6DBF99)]
                          : [const Color(0xFF1A2E22), const Color(0xFF2D5A3D)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _isSeller ? Icons.dashboard_rounded : Icons.storefront_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isSeller ? 'Seller Dashboard' : 'Become a Seller',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _isSeller ? 'Open' : 'Get Started',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Premium Plan Action (relocated just above Account Stats) ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _premiumSubscriptionButton(),
            ),

            const SizedBox(height: 16),

            // ── Account Stats ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF6DBF99).withOpacity(0.2)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Text('Account Stats',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                    ),
                    const Divider(height: 1, thickness: 0.5),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        children: [
                          _statItem(_planName, 'Plan'),
                          Container(width: 1, height: 40, color: const Color(0xFFE0E0E0)),
                          _statItem('$_salesCount', 'Sales', valueColor: const Color(0xFF3AA876)),
                          Container(width: 1, height: 40, color: const Color(0xFFE0E0E0)),
                          _statItem('$_trustScore%', 'Trust Score', valueColor: const Color(0xFF2196F3)),
                        ],
                      ),
                    ),
                    const Divider(height: 1, thickness: 0.5),
                    // ── View Analytics (Premium / Super Premium only) ────
                    if (_isPremiumTier) ...[
                      InkWell(
                        onTap: () => showSellerAnalytics(context, _planName),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              const Icon(Icons.insights_rounded,
                                  color: Color(0xFF1D9E75), size: 20),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text('Sales Analytics',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1A2E22))),
                              ),
                              const Text('View Analytics',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF3AA876),
                                      fontWeight: FontWeight.w600)),
                              const Icon(Icons.chevron_right,
                                  size: 18, color: Color(0xFF3AA876)),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1, thickness: 0.5),
                    ],
                    // ── My Reviews (rating received as a seller) ─────────
                    InkWell(
                      onTap: _openMyReviews,
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            const Icon(Icons.star_rounded,
                                color: Color(0xFFFFB300), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _reviewRating.hasReviews
                                    ? '${_reviewRating.average.toStringAsFixed(1)} · ${_reviewRating.count} review${_reviewRating.count == 1 ? '' : 's'}'
                                    : 'No reviews yet',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A2E22)),
                              ),
                            ),
                            const Text('My Reviews',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF3AA876),
                                    fontWeight: FontWeight.w600)),
                            const Icon(Icons.chevron_right,
                                size: 18, color: Color(0xFF3AA876)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Details (relocated just below Account Stats) ────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF6DBF99).withOpacity(0.2)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Details',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                    const SizedBox(height: 10),
                    _infoRow(Icons.place_outlined,
                        _address.isNotEmpty ? _address : 'Add your address'),
                    const SizedBox(height: 8),
                    _infoRow(Icons.phone_outlined,
                        _phone.isNotEmpty ? _phone : 'Add your phone number'),
                    if (_email.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _infoRow(Icons.email_outlined, _email),
                    ],
                    if (_memberSince.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _infoRow(Icons.calendar_month_outlined, _memberSince),
                    ],
                    // ── Shop details (shown once the user is a seller) ──
                    if (_isSeller) ...[
                      const SizedBox(height: 14),
                      const Divider(height: 1, thickness: 0.5),
                      const SizedBox(height: 14),
                      const Text('Shop',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                      const SizedBox(height: 10),
                      if (_businessName.isNotEmpty) ...[
                        _infoRow(Icons.storefront_outlined, _businessName),
                        const SizedBox(height: 8),
                      ],
                      if (_shopCategory.isNotEmpty) ...[
                        _infoRow(Icons.category_outlined, _shopCategory),
                        const SizedBox(height: 8),
                      ],
                      if (_shopDescription.isNotEmpty) ...[
                        _infoRow(Icons.description_outlined, _shopDescription),
                        const SizedBox(height: 8),
                      ],
                      if (_paymentNumber.isNotEmpty)
                        _infoRow(Icons.account_balance_outlined, _paymentNumber),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── My Listings ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('My Listings (${_myListings.length})',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                      if (_myListings.isNotEmpty)
                        GestureDetector(
                          onTap: _openAllListings,
                          child: const Row(
                            children: [
                              Text('See All',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3AA876))),
                              Icon(Icons.chevron_right, size: 18, color: Color(0xFF3AA876)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_loadingListings)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(color: Color(0xFF6DBF99)),
                      ),
                    )
                  else if (_myListings.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF6DBF99).withOpacity(0.2)),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 40, color: Colors.black26),
                          SizedBox(height: 8),
                          Text('No listings yet.',
                              style: TextStyle(fontSize: 13, color: Colors.black45)),
                        ],
                      ),
                    )
                  else
                    // Show only the latest listing; the rest are on "See All".
                    _listingCard(_myListings.first),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Customer Service & Rate Us ───────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      icon: Icons.support_agent,
                      label: 'Customer Service',
                      iconColor: const Color(0xFF3AA876),
                      onTap: _showCustomerService,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _actionButton(
                      icon: Icons.star_border,
                      label: 'Rate Us',
                      iconColor: const Color(0xFFFFB300),
                      onTap: _showRateUs,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Log Out ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showLogoutDialog,
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Log Out',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53E3E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),

      // ── Bottom Nav ─────────────────────────────────────────────────
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
              icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.shopping_cart_outlined), activeIcon: Icon(Icons.shopping_cart), label: 'Explore'),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications_outlined), activeIcon: Icon(Icons.notifications), label: 'Announcements'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  // ── Helper Widgets ──────────────────────────────────────────────────────
  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF6B8578)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text,
              style: const TextStyle(fontSize: 13, color: Color(0xFF3D5247)),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _statItem(String value, String label, {Color valueColor = const Color(0xFF1A2E22)}) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: valueColor)),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B8578))),
        ],
      ),
    );
  }

  Widget _listingCard(Map<String, dynamic> row) {
    final title = (row['title'] as String?) ?? 'Untitled';
    final price = _formatPrice(row['price']);
    final imageUrl = (row['image_url'] as String?)?.trim() ?? '';
    final status = ((row['status'] as String?) ?? 'active');
    final created = _relativeTime(row['created_at']);

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailPage(
              name: title,
              price: price,
              image: imageUrl.isNotEmpty ? imageUrl : 'images/chicken.png',
              images: (row['image_urls'] as List?)
                      ?.map((e) => '$e')
                      .where((e) => e.trim().isNotEmpty)
                      .toList() ??
                  const [],
              description: (row['description'] as String?) ?? '',
              condition: (row['condition'] as String?) ?? '',
              sellerName: _name,
              location: (row['location'] as String?) ?? '',
              breed: (row['breed'] as String?) ?? '',
              age: (row['age'] as String?) ?? '',
              weight: (row['weight'] as String?) ?? '',
              createdAt: '${row['created_at'] ?? ''}',
              listingId: '${row['id'] ?? ''}',
              sellerId: '${row['seller_id'] ?? ''}',
              status: status,
            ),
          ),
        );
        if (result == 'deleted') _loadMyListings();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF6DBF99).withOpacity(0.2)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: _listingImage(imageUrl),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF5CC898),
                    child: Text(_initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1A2E22))),
                        const SizedBox(height: 2),
                        Text(price,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3AA876))),
                        if (created.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(created, style: const TextStyle(fontSize: 11, color: Colors.black38)),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F8F1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFC2EDD9)),
                    ),
                    child: Text(status[0].toUpperCase() + status.substring(1),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF27803F))),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _showListingComments,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE8F8F1), width: 1)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.mode_comment_outlined, size: 14, color: Color(0xFF3AA876)),
                    SizedBox(width: 6),
                    Text('View Comments',
                        style: TextStyle(fontSize: 12, color: Color(0xFF3AA876), fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Renders a listing image from a network URL or bundled asset.
  Widget _listingImage(String path) {
    Widget placeholder() => Container(
          width: double.infinity, height: 140,
          color: const Color(0xFFE8F8F1),
          child: const Icon(Icons.image_not_supported_outlined, color: Colors.black26, size: 40),
        );
    if (path.isEmpty) return placeholder();
    return path.startsWith('http')
        ? Image.network(path,
            width: double.infinity, height: 140, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder())
        : Image.asset(path,
            width: double.infinity, height: 140, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder());
  }

  // ── Premium Subscription button (navigates to the plans page) ─────────────
  Widget _premiumSubscriptionButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openPlansPage,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE8F8F1), Color(0xFFD3F0E4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF6DBF99).withOpacity(0.45)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1D9E75).withOpacity(0.12),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: const Icon(Icons.workspace_premium,
                    color: Color(0xFF1D9E75), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Premium Subscription',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2E22))),
                    SizedBox(height: 2),
                    Text('Unlock more features — view plans',
                        style: TextStyle(fontSize: 12.5, color: Color(0xFF3D5247))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF1D9E75), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF6DBF99).withOpacity(0.2)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: iconColor)),
          ],
        ),
      ),
    );
  }
}

// ── Benefit Row widget ────────────────────────────────────────────────────────
class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BenefitRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF3AA876)),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF3D5247))),
      ],
    );
  }
}

// ── Premium Subscription page ──────────────────────────────────────────────
/// Full-screen plan-selection page reached from the profile's
/// "Premium Subscription" button. Replaces the old plan popup dialog.
class _PremiumSubscriptionPage extends StatefulWidget {
  const _PremiumSubscriptionPage();

  @override
  State<_PremiumSubscriptionPage> createState() =>
      _PremiumSubscriptionPageState();
}

class _PremiumSubscriptionPageState extends State<_PremiumSubscriptionPage> {
  // Brand palette (matches the rest of the app).
  static const Color _green = Color(0xFF1D9E75);
  static const Color _greenMid = Color(0xFF3AA876);
  static const Color _dark = Color(0xFF1A2E22);
  static const Color _muted = Color(0xFF7C8B83);

  bool _yearly = false;
  String _selectedPlan = 'premium';

  // Id of the plan whose request is currently being submitted, if any.
  String? _submittingId;

  // Shared feature checklist — each plan marks which ones it unlocks.
  static const List<String> _features = [
    'Browse all listings',
    'Post your own listings',
    'Direct buyer messaging',
    'Verified seller badge',
    'Priority customer support',
  ];

  static const List<_PlanData> _plans = [
    _PlanData(
      id: 'free',
      label: 'Free',
      icon: Icons.person_outline,
      monthly: 0,
      unlocked: [true, false, false, false, false],
    ),
    _PlanData(
      id: 'premium',
      label: 'Premium',
      icon: Icons.star_rounded,
      monthly: 699,
      unlocked: [true, true, true, true, false],
      featured: true,
    ),
    _PlanData(
      id: 'superpremium',
      label: 'Super Premium',
      icon: Icons.workspace_premium,
      monthly: 1299,
      unlocked: [true, true, true, true, true],
    ),
  ];

  String _priceLabel(_PlanData plan) {
    if (plan.monthly == 0) return '₱0';
    final value = _yearly ? plan.monthly * 10 : plan.monthly;
    return '₱$value';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAF7),
      body: SafeArea(
        child: Column(
          children: [
            // ── Back button (upper left) ─────────────────────────────
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: _dark),
                  tooltip: 'Back',
                ),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                child: Column(
                  children: [
                    // ── Heading ─────────────────────────────────────
                    const Text(
                      'Simple pricing, no hidden fees',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _dark,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '7-day free trial. No credit card required.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: _muted),
                    ),

                    const SizedBox(height: 20),

                    // ── Billing toggle ──────────────────────────────
                    _billingToggle(),

                    const SizedBox(height: 24),

                    // ── Plan Cards ──────────────────────────────────
                    ..._plans.map(_planCard),

                    const SizedBox(height: 8),
                    const Text(
                      'You can change your plan anytime in settings.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: _muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bill Monthly / Bill Yearly pill toggle ────────────────────────────────
  Widget _billingToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE2EFE9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleChip('Monthly', !_yearly, () => setState(() => _yearly = false)),
          _toggleChip('Yearly', _yearly, () => setState(() => _yearly = true)),
        ],
      ),
    );
  }

  Widget _toggleChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
        decoration: BoxDecoration(
          color: active ? _green : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : _muted,
          ),
        ),
      ),
    );
  }

  // ── One plan card ─────────────────────────────────────────────────────────
  Widget _planCard(_PlanData plan) {
    final featured = plan.featured;
    final selected = _selectedPlan == plan.id;
    final onColor = featured ? Colors.white : _dark;
    final subColor = featured ? Colors.white70 : _muted;

    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = plan.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: featured
              ? const LinearGradient(
                  colors: [_greenMid, _green],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: featured ? null : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected && !featured
                ? _green
                : const Color(0xFFE7F0EB),
            width: selected && !featured ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: featured
                  ? _green.withOpacity(0.30)
                  : Colors.black.withOpacity(0.04),
              blurRadius: featured ? 22 : 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: name + price badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: featured
                        ? Colors.white.withOpacity(0.18)
                        : const Color(0xFFE8F8F1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(plan.icon,
                      color: featured ? Colors.white : _green, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            plan.label,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: onColor,
                            ),
                          ),
                          if (featured) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'POPULAR',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: _green,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _yearly ? 'Per year' : 'Per month',
                        style: TextStyle(fontSize: 12, color: subColor),
                      ),
                    ],
                  ),
                ),
                // Price badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: featured
                        ? Colors.white
                        : const Color(0xFFE8F8F1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _priceLabel(plan),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _green,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),
            Divider(
              height: 1,
              thickness: 1,
              color: featured
                  ? Colors.white.withOpacity(0.20)
                  : const Color(0xFFEEF4F1),
            ),
            const SizedBox(height: 16),

            // Feature checklist
            ...List.generate(_features.length, (i) {
              final on = plan.unlocked[i];
              final iconColor = featured
                  ? (on ? Colors.white : Colors.white38)
                  : (on ? _green : const Color(0xFFC4D3CC));
              final textColor = featured
                  ? (on ? Colors.white : Colors.white54)
                  : (on ? _dark : const Color(0xFFB2C0B9));
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      on ? Icons.check_circle : Icons.cancel,
                      size: 18,
                      color: iconColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _features[i],
                        style: TextStyle(
                          fontSize: 13,
                          color: textColor,
                          decoration:
                              on ? null : TextDecoration.lineThrough,
                          decorationColor: textColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 6),

            // Purchase button
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed:
                    _submittingId != null ? null : () => _choosePlan(plan),
                style: ElevatedButton.styleFrom(
                  backgroundColor: featured ? Colors.white : _green,
                  foregroundColor: featured ? _green : Colors.white,
                  disabledBackgroundColor:
                      (featured ? Colors.white : _green).withOpacity(0.6),
                  disabledForegroundColor: featured ? _green : Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: _submittingId == plan.id
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: featured ? _green : Colors.white,
                        ),
                      )
                    : Text(
                        plan.monthly == 0 ? 'Get Started' : 'Choose Plan',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _choosePlan(_PlanData plan) async {
    setState(() => _selectedPlan = plan.id);
    final appPlan = SubscriptionService.planById(plan.id);

    // Free needs no admin approval.
    if (appPlan.isFree) {
      showTopMessage(context, "You're on the Free plan.", isError: false);
      Navigator.pop(context);
      return;
    }

    setState(() => _submittingId = plan.id);
    final error = await SubscriptionService.requestPlan(appPlan);
    if (!mounted) return;
    setState(() => _submittingId = null);

    if (error == null) {
      showTopMessage(
        context,
        '${appPlan.label} request submitted — pending admin approval.',
        isError: false,
      );
      Navigator.pop(context);
    } else {
      showTopMessage(context, error);
    }
  }
}

// Static description of a subscription plan rendered by [_PremiumSubscriptionPage].
class _PlanData {
  final String id;
  final String label;
  final IconData icon;
  final int monthly;
  final List<bool> unlocked;
  final bool featured;

  const _PlanData({
    required this.id,
    required this.label,
    required this.icon,
    required this.monthly,
    required this.unlocked,
    this.featured = false,
  });
}

/// Full-screen "Edit Profile" page.
///
/// Layout is modeled on a social-app style edit screen: a centered avatar with
/// an "Edit picture or avatar" action on top, followed by label/value rows
/// separated by thin dividers. It edits the same fields as the old popup
/// (name, phone, address, house number) and persists them via [onSave].
class _EditProfilePage extends StatefulWidget {
  final String initialName;
  final String initialPhone;
  final String initialAddress;
  final String initialHouse;
  final String initialAvatarUrl;
  // Details extras (read-only) + shop details (editable, seller-only).
  final String email;
  final String memberSince;
  final bool isSeller;
  final String initialBusinessName;
  final String initialShopCategory;
  final String initialShopDescription;
  final String initialPaymentNumber;
  final Future<String?> Function({
    required String name,
    required String phone,
    required String address,
    required String houseNumber,
    required String businessName,
    required String shopCategory,
    required String shopDescription,
    required String paymentNumber,
    PhCity? location,
  }) onSave;
  final ValueChanged<String> onAvatarChanged;

  const _EditProfilePage({
    required this.initialName,
    required this.initialPhone,
    required this.initialAddress,
    required this.initialHouse,
    required this.initialAvatarUrl,
    required this.email,
    required this.memberSince,
    required this.isSeller,
    required this.initialBusinessName,
    required this.initialShopCategory,
    required this.initialShopDescription,
    required this.initialPaymentNumber,
    required this.onSave,
    required this.onAvatarChanged,
  });

  @override
  State<_EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<_EditProfilePage> {
  static const Color _accent = Color(0xFF3AA876);
  static const Color _dark = Color(0xFF1A2E22);
  static const Color _line = Color(0xFFEAF2EE);

  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _houseCtrl;
  late final TextEditingController _businessCtrl;
  late final TextEditingController _shopDescCtrl;
  late final TextEditingController _paymentCtrl;
  late String _shopCategory;
  late String _avatarUrl;
  // Address is picked from the PH city/municipality gazetteer, not typed.
  late String _address;
  PhCity? _pickedCity;
  bool _isSaving = false;
  bool _uploadingAvatar = false;

  static const List<String> _categories = [
    'Poultry', 'Livestock', 'Aquatics', 'Mixed / All'
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _phoneCtrl = TextEditingController(text: widget.initialPhone);
    _address = widget.initialAddress;
    _houseCtrl = TextEditingController(text: widget.initialHouse);
    _businessCtrl = TextEditingController(text: widget.initialBusinessName);
    _shopDescCtrl = TextEditingController(text: widget.initialShopDescription);
    _paymentCtrl = TextEditingController(text: widget.initialPaymentNumber);
    _shopCategory = widget.initialShopCategory;
    _avatarUrl = widget.initialAvatarUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _houseCtrl.dispose();
    _businessCtrl.dispose();
    _shopDescCtrl.dispose();
    _paymentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final error = await widget.onSave(
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      address: _address.trim(),
      location: _pickedCity,
      houseNumber: _houseCtrl.text.trim(),
      businessName: _businessCtrl.text.trim(),
      shopCategory: _shopCategory,
      shopDescription: _shopDescCtrl.text.trim(),
      paymentNumber: _paymentCtrl.text.trim(),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() => _isSaving = false);
      showTopMessage(context, 'Save failed: $error');
    }
  }

  // Lets the user pick a photo source, then uploads and saves it as the avatar.
  Future<void> _changeAvatar() async {
    if (_uploadingAvatar) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDCEFE6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: _accent),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: _accent),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _uploadAvatar(source);
  }

  /// Opens the crop editor so the user can frame their photo as a square
  /// before upload. Returns null if they cancel.
  Future<CroppedFile?> _cropToSquare(String sourcePath) async {
    return ImageCropper().cropImage(
      sourcePath: sourcePath,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Adjust photo',
          toolbarColor: _accent,
          toolbarWidgetColor: Colors.white,
          backgroundColor: Colors.black,
          activeControlsWidgetColor: _accent,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          cropStyle: CropStyle.circle,
          aspectRatioPresets: const [CropAspectRatioPreset.square],
        ),
        IOSUiSettings(
          title: 'Adjust photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          cropStyle: CropStyle.circle,
          aspectRatioPresets: const [CropAspectRatioPreset.square],
        ),
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
        ),
      ],
    );
  }

  Future<void> _uploadAvatar(ImageSource source) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      showTopMessage(context, 'You are not signed in. Please log in again.');
      return;
    }
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 90,
      );
      if (picked == null) return; // user cancelled
      if (!mounted) return;

      // Let the user crop/adjust to a square before uploading.
      final cropped = await _cropToSquare(picked.path);
      if (cropped == null) return; // user cancelled the crop

      setState(() => _uploadingAvatar = true);
      final bytes = await cropped.readAsBytes();

      // Upload the new profile picture to Cloudinary (folder `user_profile`).
      final url = await uploadToCloudinary(
        bytes,
        '${user.id}.jpg',
        folder: 'user_profile',
      );
      if (url == null) {
        throw Exception('Image upload failed.');
      }

      // Remove the previous picture from Cloudinary so it's truly replaced.
      // Runs while the DB still references the old URL (best-effort).
      await deleteCurrentAvatarImage();

      // Persist the new URL on the user's row.
      await supabase
          .from('users')
          .update({'avatar_url': url}).eq('id', user.id);

      if (!mounted) return;
      setState(() {
        _avatarUrl = url;
        _uploadingAvatar = false;
      });
      widget.onAvatarChanged(url);
      showTopMessage(context, 'Profile picture updated!',
          isError: false, backgroundColor: _accent);
    } catch (e) {
      debugPrint('Avatar upload failed: $e');
      if (!mounted) return;
      setState(() => _uploadingAvatar = false);
      showTopMessage(context, 'Could not update picture: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _dark),
          onPressed: _isSaving ? null : () => Navigator.pop(context),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(color: _dark, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.only(right: 20),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: _accent),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text(
                    'Save',
                    style: TextStyle(color: _accent, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: _line),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 26),
          // ── Avatar + edit action ───────────────────────────────────────
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _uploadingAvatar ? null : _changeAvatar,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A9B73),
                          shape: BoxShape.circle,
                          border: Border.all(color: _line, width: 2),
                          image: _avatarUrl.isNotEmpty
                              ? DecorationImage(
                                  image: NetworkImage(_avatarUrl),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _avatarUrl.isNotEmpty
                            ? null
                            : const Icon(Icons.person, color: Colors.white, size: 48),
                      ),
                      // Loading overlay while uploading.
                      if (_uploadingAvatar)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withOpacity(0.35),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      // Camera badge.
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: _accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                          ),
                          child: const Icon(Icons.photo_camera,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _uploadingAvatar ? null : _changeAvatar,
                  child: const Text(
                    'Edit picture or avatar',
                    style: TextStyle(color: _accent, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _sectionHeader('Details'),
          _row('Name', _nameCtrl, 'Your full name'),
          _row('Phone', _phoneCtrl, 'Your phone number', type: TextInputType.phone),
          _addressRow(),
          if (widget.email.isNotEmpty) _readonlyRow('Email', widget.email),
          if (widget.memberSince.isNotEmpty)
            _readonlyRow('Member', widget.memberSince),
          // ── Shop details (sellers only) ──
          if (widget.isSeller) ...[
            _sectionHeader('Shop'),
            _row('Shop Name', _businessCtrl, 'Shop / Farm name'),
            _categoryRow(),
            _row('Description', _shopDescCtrl, 'What you sell', maxLines: 2),
            _row('Payment', _paymentCtrl, 'GCash / Bank number',
                type: TextInputType.text),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // Section heading row (e.g. "Details", "Shop").
  Widget _sectionHeader(String label) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF7FBF9),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.bold, color: _accent),
      ),
    );
  }

  // A read-only label/value row for fields that can't be edited here.
  Widget _readonlyRow(String label, String value) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 16, color: _dark, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 16, color: Colors.black45)),
          ),
        ],
      ),
    );
  }

  // Tappable address row that opens the searchable PH city/municipality
  // picker instead of a free-text box.
  Widget _addressRow() {
    return InkWell(
      onTap: _pickAddress,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _line)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            const SizedBox(
              width: 104,
              child: Text('Address',
                  style: TextStyle(
                      fontSize: 16, color: _dark, fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: Text(
                _address.isNotEmpty ? _address : 'Select your city/municipality',
                style: TextStyle(
                    fontSize: 16,
                    color: _address.isNotEmpty ? _dark : Colors.black38),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down,
                color: Colors.black38, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAddress() async {
    final city = await showCityPicker(
      context,
      selectedLabel: _address,
      title: 'Your Address',
      subtitle: 'Search and select your city or municipality — your listings '
          'and "near you" distances are based on it.',
    );
    if (city == null || !mounted) return;
    setState(() {
      _pickedCity = city;
      _address = city.label;
    });
  }

  // Tappable category row that opens a picker.
  Widget _categoryRow() {
    return InkWell(
      onTap: _pickCategory,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _line)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            const SizedBox(
              width: 104,
              child: Text('Category',
                  style: TextStyle(
                      fontSize: 16, color: _dark, fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: Text(
                _shopCategory.isNotEmpty ? _shopCategory : 'Select category',
                style: TextStyle(
                    fontSize: 16,
                    color: _shopCategory.isNotEmpty ? _dark : Colors.black38),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.black38, size: 22),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCategory() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFDCEFE6),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            ..._categories.map((c) => ListTile(
                  title: Text(c),
                  trailing: _shopCategory == c
                      ? const Icon(Icons.check_circle_rounded, color: _accent)
                      : null,
                  onTap: () => Navigator.pop(ctx, c),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _shopCategory = picked);
  }

  // A single label/value row: fixed-width label on the left, inline editable
  // text field on the right, with a thin divider beneath.
  Widget _row(String label, TextEditingController ctrl, String hint,
      {TextInputType type = TextInputType.text, int maxLines = 1}) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              width: 104,
              child: Text(
                label,
                style: const TextStyle(fontSize: 16, color: _dark, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              keyboardType: type,
              maxLines: maxLines,
              style: const TextStyle(fontSize: 16, color: _dark),
              cursorColor: _accent,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
                hintText: hint,
                hintStyle: const TextStyle(color: Colors.black38, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small status dot used in the Customer Service sheet.
class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: Color(0xFF3AA876),
        shape: BoxShape.circle,
      ),
    );
  }
}