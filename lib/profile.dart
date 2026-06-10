import 'package:flutter/material.dart';
import 'dashboard.dart';
import 'buyer.dart';
import 'announcement_page.dart';
import 'login.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int _selectedIndex = 3;
  bool _isSeller = false;
  bool _isPremium = true; // Simulated: User has availed a subscription
  int _salesCount = 1;    // Simulated: User has 1 sale (New Farmer)

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
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
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
  void _showEditProfile() {
    final nameCtrl = TextEditingController(text: 'John Smith');
    final phoneCtrl = TextEditingController(text: '+63 991 888 8854');
    final addressCtrl = TextEditingController(text: 'Purok 5, Laoag St., Quezon City');
    final locationCtrl = TextEditingController(text: 'I-Dagupan Lane');

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
                child: Text('Edit Profile',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
              ),
              const SizedBox(height: 20),
              _editField(nameCtrl, 'Full Name', Icons.person_outline),
              const SizedBox(height: 12),
              _editField(phoneCtrl, 'Phone Number', Icons.phone_outlined, type: TextInputType.phone),
              const SizedBox(height: 12),
              _editField(locationCtrl, 'Location / Barangay', Icons.location_on_outlined),
              const SizedBox(height: 12),
              _editField(addressCtrl, 'Full Address', Icons.place_outlined),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      _snackBar('Profile updated successfully!', const Color(0xFF3AA876)),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6DBF99),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editField(TextEditingController ctrl, String hint, IconData icon,
      {TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF6DBF99)),
        filled: true,
        fillColor: const Color(0xFFF4FAF7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      _snackBar('Message sent!', const Color(0xFF2196F3)),
                    );
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              const CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xFFE8F8F1),
                child: Icon(Icons.support_agent, color: Color(0xFF3AA876), size: 30),
              ),
              const SizedBox(height: 12),
              const Text('Customer Service',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
              const SizedBox(height: 6),
              const Text(
                'We\'re here to help! Reach us through any of the channels below.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black45, height: 1.5),
              ),
              const SizedBox(height: 20),
              _serviceRow(Icons.phone_rounded, 'Call Us', '+63 912 345 6789', const Color(0xFF3AA876)),
              const SizedBox(height: 10),
              _serviceRow(Icons.email_outlined, 'Email Us', 'support@animart.ph', const Color(0xFF2196F3)),
              const SizedBox(height: 10),
              _serviceRow(Icons.chat_bubble_outline, 'Live Chat', 'Available 8AM – 5PM', const Color(0xFFFFB300)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: const BorderSide(color: Colors.black12),
                  ),
                  child: const Text('Close', style: TextStyle(color: Colors.black54)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serviceRow(IconData icon, String title, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: color)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black45)),
            ],
          ),
        ],
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              _snackBar('Thanks for your rating! ⭐', const Color(0xFFFFB300)),
                            );
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

  // ── Plan selection dialog ─────────────────────────────────────────────────

  void _showPlanDialog() {
    String selectedPlan = 'free';

    final List<Map<String, String>> plans = [
      {
        'id': 'free',
        'label': 'Free',
        'price': '₱0 / mo',
        'desc': 'Basic browsing, view listings',
      },
      {
        'id': 'premium',
        'label': 'Premium',
        'price': '₱199 / mo',
        'desc': 'Post listings, buyer messaging',
      },
      {
        'id': 'superpremium',
        'label': 'Super Premium',
        'price': '₱499 / mo',
        'desc': 'All features + priority support',
      },
    ];

    showDialog(
      context: context,
      barrierDismissible: false, // must tap X or Continue to dismiss
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialog) {
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
                      final isSelected = selectedPlan == plan['id'];
                      return GestureDetector(
                        onTap: () =>
                            setDialog(() => selectedPlan = plan['id']!),
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
                                plan['id'] == 'free'
                                    ? Icons.person_outline
                                    : plan['id'] == 'premium'
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
                                    Text(
                                      plan['label']!,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      plan['desc']!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                plan['price']!,
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
                        onPressed: () => Navigator.pop(ctx),
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
                          Text('Set up your shop and start selling',
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
                      onPressed: () {
                        if (shopNameCtrl.text.trim().isEmpty || selectedCategory == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            _snackBar('Please fill in all required fields.', Colors.redAccent),
                          );
                          return;
                        }
                        Navigator.pop(ctx);
                        setState(() => _isSeller = true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          _snackBar('🎉 You are now a Seller! Welcome aboard.', const Color(0xFF3AA876)),
                        );
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
                        _dashStat('1', 'Listings', const Color(0xFF3AA876)),
                        const SizedBox(width: 12),
                        _dashStat('1', 'Sales', const Color(0xFF2196F3)),
                        const SizedBox(width: 12),
                        _dashStat('₱0', 'Earnings', const Color(0xFFFFB300)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Quick actions
                    const Text('Quick Actions',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                    const SizedBox(height: 10),
                    _dashAction(Icons.add_circle_outline, 'Add New Listing', 'Post a new animal or product', const Color(0xFF3AA876)),
                    const SizedBox(height: 8),
                    _dashAction(Icons.bar_chart_rounded, 'View Sales', 'Track your orders and earnings', const Color(0xFF2196F3)),
                    const SizedBox(height: 8),
                    _dashAction(Icons.reviews_outlined, 'My Reviews', 'See buyer feedback', const Color(0xFFFFB300)),
                    const SizedBox(height: 8),
                    _dashAction(Icons.settings_outlined, 'Shop Settings', 'Update your shop info', Colors.black38),
                  ],
                ),
              ),
            ],
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

  Widget _dashAction(IconData icon, String title, String subtitle, Color color) {
    return Container(
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
    );
  }

  // ── Snackbar helper ───────────────────────────────────────────────────────
  SnackBar _snackBar(String msg, Color color) => SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      );

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
              padding: const EdgeInsets.only(top: 50, bottom: 20, left: 16, right: 16),
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
                  GestureDetector(
                    onTap: () { if (Navigator.canPop(context)) Navigator.pop(context); },
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text('PROFILE',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                            color: Colors.white, letterSpacing: 1.5)),
                  ),
                  const SizedBox(height: 20),
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
                            ),
                            child: const Icon(Icons.person, color: Colors.white, size: 40),
                          ),
                          if (_isSeller)
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
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('John Smith',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                    if (_isPremium)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 4),
                                        child: Icon(Icons.verified, color: Colors.blue, size: 18),
                                      ),
                                  ],
                                ),
                                if (_isSeller) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _salesCount >= 3 ? const Color(0xFFFFB300) : const Color(0xFF4CAF50),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(_salesCount >= 3 ? 'Trusted Seller' : 'New Farmer',
                                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                                if (_isPremium) ...[
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
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2196F3),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Trust Score: 98%',
                                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            _infoRow(Icons.location_on_outlined, 'I-Dagupan Lane'),
                            const SizedBox(height: 2),
                            _infoRow(Icons.phone_outlined, '+63 991 888 8854'),
                            const SizedBox(height: 2),
                            _infoRow(Icons.place_outlined, 'Purok 5, Laoag St., Quezon City'),
                            const SizedBox(height: 2),
                            _infoRow(Icons.calendar_month_outlined, 'Member since Jan 2024'),
                            if (_isSeller) ...[
                              const SizedBox(height: 2),
                              _infoRow(Icons.workspace_premium_outlined, 'Breeder since 2020'),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          _headerButton(
                            icon: Icons.edit,
                            label: 'Edit Profile',
                            color: const Color(0xFF4CAF50),
                            onTap: _showEditProfile,
                          ),
                          const SizedBox(height: 6),
                          _headerButton(
                            icon: Icons.messenger_outline,
                            label: 'Send me a\nMessage',
                            color: const Color(0xFF2196F3),
                            onTap: _showSendMessage,
                          ),
                        ],
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isSeller ? 'Seller Dashboard' : 'Become a Seller',
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text(
                              _isSeller
                                  ? 'Manage your listings & earnings'
                                  : 'Start selling your animals & products',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _isSeller ? 'Open' : 'Get Started',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
                          _statItem('1', 'Listings'),
                          Container(width: 1, height: 40, color: const Color(0xFFE0E0E0)),
                          _statItem('1', 'Sales', valueColor: const Color(0xFF3AA876)),
                          Container(width: 1, height: 40, color: const Color(0xFFE0E0E0)),
                          _statItem('98%', 'Trust Score', valueColor: const Color(0xFF2196F3)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Premium Plan Action ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _actionButton(
                icon: Icons.workspace_premium,
                label: 'Premium Subscription',
                iconColor: const Color(0xFF1D9E75),
                onTap: _showPlanDialog,
              ),
            ),

            const SizedBox(height: 16),

            // ── My Listing ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('My Listing',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                  const SizedBox(height: 10),
                  _listingCard(),
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
        Icon(icon, size: 11, color: Colors.white70),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _headerButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 13),
            const SizedBox(width: 4),
            Text(label, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String value, String label, {Color valueColor = const Color(0xFF1A2E22)}) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: valueColor)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B8578))),
        ],
      ),
    );
  }

  Widget _listingCard() {
    return GestureDetector(
      onTap: () {},
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
              child: Image.asset(
                'images/turkey.png',
                width: double.infinity, height: 140, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: double.infinity, height: 140,
                  color: const Color(0xFFE8F8F1),
                  child: const Icon(Icons.image_not_supported_outlined, color: Colors.black26, size: 40),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(0xFF5CC898),
                    child: Text('J', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('John Smith',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1A2E22))),
                        SizedBox(height: 2),
                        Text('13 days', style: TextStyle(fontSize: 11, color: Colors.black38)),
                        SizedBox(height: 2),
                        Text('Good morning', style: TextStyle(fontSize: 11, color: Color(0xFF6B8578))),
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
                    child: const Text('Active',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF27803F))),
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