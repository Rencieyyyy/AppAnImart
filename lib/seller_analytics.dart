import 'package:flutter/material.dart';
import 'main.dart';
import 'services/marketplace_service.dart';

/// Sales analytics a seller uses to monitor their performance.
///
/// A **Super Premium** exclusive: the popup (and its advanced metrics) is
/// only ever shown to Super Premium sellers, alongside their Priority
/// Listing perk.
/// One month's worth of listing activity for the bar graph.
class MonthlyCount {
  final String label;
  final int count;
  const MonthlyCount(this.label, this.count);
}

class SellerAnalytics {
  final int totalListings;
  final int activeListings;
  final int soldOrHidden;
  final int salesCount;
  final int trustScore;
  final double inventoryValue;
  final double avgPrice;
  final String topCategory;
  final SellerRating rating;

  /// Listings posted per month over the last six months (oldest first).
  final List<MonthlyCount> monthlyListings;

  /// Active listings per category, for the breakdown bars.
  final Map<String, int> categoryCounts;

  const SellerAnalytics({
    required this.totalListings,
    required this.activeListings,
    required this.soldOrHidden,
    required this.salesCount,
    required this.trustScore,
    required this.inventoryValue,
    required this.avgPrice,
    required this.topCategory,
    required this.rating,
    this.monthlyListings = const [],
    this.categoryCounts = const {},
  });

  static const empty = SellerAnalytics(
    totalListings: 0,
    activeListings: 0,
    soldOrHidden: 0,
    salesCount: 0,
    trustScore: 0,
    inventoryValue: 0,
    avgPrice: 0,
    topCategory: '—',
    rating: SellerRating.empty,
  );

  /// Loads analytics for [userId] from the listings + users + reviews tables.
  static Future<SellerAnalytics> load(String userId) async {
    if (userId.isEmpty) return empty;
    int total = 0, active = 0;
    double inventory = 0;
    final categoryCounts = <String, int>{};
    int sales = 0, trust = 0;
    // Last six calendar months (oldest first) for the activity graph.
    final now = DateTime.now();
    final months =
        List.generate(6, (i) => DateTime(now.year, now.month - 5 + i));
    final monthlyBuckets = {for (final m in months) '${m.year}-${m.month}': 0};
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    try {
      final listings = await supabase
          .from('listings')
          .select('price, status, category, created_at')
          .eq('seller_id', userId);
      for (final row in (listings as List)) {
        final r = row as Map<String, dynamic>;
        total++;
        final status = (r['status'] as String?) ?? 'active';
        final price = (r['price'] is num)
            ? (r['price'] as num).toDouble()
            : (double.tryParse('${r['price']}') ?? 0);
        if (status == 'active') {
          active++;
          inventory += price;
          final cat = (r['category'] as String?)?.trim();
          if (cat != null && cat.isNotEmpty) {
            categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
          }
        }
        final created = DateTime.tryParse('${r['created_at'] ?? ''}');
        if (created != null) {
          final key = '${created.year}-${created.month}';
          if (monthlyBuckets.containsKey(key)) {
            monthlyBuckets[key] = monthlyBuckets[key]! + 1;
          }
        }
      }

      final profile = await supabase
          .from('users')
          .select('sales_count, trust_score')
          .eq('id', userId)
          .maybeSingle();
      if (profile != null) {
        sales = (profile['sales_count'] as int?) ?? 0;
        trust = (profile['trust_score'] as int?) ?? 0;
      }
    } catch (e) {
      debugPrint('Failed to load seller analytics: $e');
    }

    final rating = await MarketplaceService.fetchSellerRating(userId);
    if (rating.hasReviews) trust = rating.trustPercent;

    String topCat = '—';
    int best = 0;
    categoryCounts.forEach((cat, n) {
      if (n > best) {
        best = n;
        topCat = cat;
      }
    });

    return SellerAnalytics(
      totalListings: total,
      activeListings: active,
      soldOrHidden: total - active,
      salesCount: sales,
      trustScore: trust,
      inventoryValue: inventory,
      avgPrice: active > 0 ? inventory / active : 0,
      topCategory: topCat,
      rating: rating,
      monthlyListings: [
        for (final m in months)
          MonthlyCount(
              monthNames[m.month - 1], monthlyBuckets['${m.year}-${m.month}']!),
      ],
      categoryCounts: categoryCounts,
    );
  }
}

/// Whether [plan] is the top "Super Premium" tier.
bool isSuperPremiumPlan(String plan) => plan.trim() == 'Super Premium';

/// Loads analytics for the signed-in user and shows the tier-aware dialog.
Future<void> showSellerAnalytics(BuildContext context, String plan) async {
  final user = supabase.auth.currentUser;
  if (user == null) return;
  final data = await SellerAnalytics.load(user.id);
  if (!context.mounted) return;
  showDialog(
    context: context,
    builder: (_) => _SellerAnalyticsDialog(plan: plan, data: data),
  );
}

class _SellerAnalyticsDialog extends StatelessWidget {
  final String plan;
  final SellerAnalytics data;
  const _SellerAnalyticsDialog({required this.plan, required this.data});

  String _peso(double value) {
    if (value >= 1000) {
      final k = value / 1000;
      final text = k == k.roundToDouble() ? k.toInt().toString() : k.toStringAsFixed(1);
      return '₱${text}k';
    }
    return '₱${value == value.roundToDouble() ? value.toInt() : value.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final isSuper = isSuperPremiumPlan(plan);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F8F1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.insights_rounded, color: Color(0xFF1D9E75), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sales Analytics',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                          Text('$plan member overview',
                              style: const TextStyle(fontSize: 12, color: Colors.black45)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.black45, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // ── Core metrics (all premium tiers) ──
                Row(
                  children: [
                    _card('${data.totalListings}', 'Total Listings', Icons.inventory_2_outlined, const Color(0xFF3AA876)),
                    const SizedBox(width: 10),
                    _card('${data.activeListings}', 'Active', Icons.check_circle_outline, const Color(0xFF2196F3)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _card('${data.salesCount}', 'Sales', Icons.shopping_bag_outlined, const Color(0xFFFFB300)),
                    const SizedBox(width: 10),
                    _card('${data.trustScore}%', 'Trust Score', Icons.verified_outlined, const Color(0xFF1D9E75)),
                  ],
                ),
                const SizedBox(height: 18),

                // ── Advanced metrics ──
                const Text('Advanced',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _card(_peso(data.inventoryValue), 'Inventory Value', Icons.account_balance_wallet_outlined, const Color(0xFF3AA876)),
                    const SizedBox(width: 10),
                    _card(_peso(data.avgPrice), 'Avg. Price', Icons.sell_outlined, const Color(0xFF2196F3)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _card(data.topCategory, 'Top Category', Icons.category_outlined, const Color(0xFFFFB300)),
                    const SizedBox(width: 10),
                    _card(
                        data.rating.hasReviews ? '${data.rating.average.toStringAsFixed(1)} (${data.rating.count})' : 'No reviews',
                        'Avg. Rating', Icons.star_outline_rounded, const Color(0xFF1D9E75)),
                  ],
                ),
                const SizedBox(height: 18),

                // ── Sales graphs ──
                const Text('Sales Graphs',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A2E22))),
                const SizedBox(height: 10),
                _MonthlyBarChart(data: data.monthlyListings),
                if (data.categoryCounts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _CategoryBars(data: data.categoryCounts),
                ],

                if (isSuper) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8E5BE8), Color(0xFF6A3FD1)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 22),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Priority Listing Active',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('Your listings appear above Premium sellers',
                                  style: TextStyle(color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(String value, String label, IconData icon, Color c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: c.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withOpacity(0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(height: 8),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

/// Bar graph of listings posted per month over the last six months.
class _MonthlyBarChart extends StatelessWidget {
  final List<MonthlyCount> data;
  const _MonthlyBarChart({required this.data});

  static const double _maxBarHeight = 64;

  @override
  Widget build(BuildContext context) {
    final maxCount =
        data.fold<int>(0, (m, e) => e.count > m ? e.count : m);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF3AA876).withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3AA876).withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart_rounded, color: Color(0xFF3AA876), size: 16),
              SizedBox(width: 6),
              Text('Listings posted',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A2E22))),
              Spacer(),
              Text('Last 6 months',
                  style: TextStyle(fontSize: 10, color: Colors.black45)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < data.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: _bar(data[i], maxCount, isCurrent: i == data.length - 1)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar(MonthlyCount m, int maxCount, {required bool isCurrent}) {
    // Minimum stub height so empty months still show a baseline.
    final h = maxCount == 0
        ? 4.0
        : 4 + _maxBarHeight * (m.count / maxCount);
    final color = isCurrent ? const Color(0xFF3AA876) : const Color(0xFF3AA876).withOpacity(0.35);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${m.count}',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isCurrent ? const Color(0xFF3AA876) : Colors.black45)),
        const SizedBox(height: 4),
        Container(
          height: h,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
        const SizedBox(height: 6),
        Text(m.label, style: const TextStyle(fontSize: 10, color: Colors.black45)),
      ],
    );
  }
}

/// Horizontal breakdown bars of active listings per category.
class _CategoryBars extends StatelessWidget {
  final Map<String, int> data;
  const _CategoryBars({required this.data});

  static const List<Color> _palette = [
    Color(0xFF3AA876),
    Color(0xFF2196F3),
    Color(0xFFFFB300),
    Color(0xFF8E5BE8),
  ];

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(4).toList();
    final total = data.values.fold<int>(0, (s, n) => s + n);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3).withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.donut_small_rounded, color: Color(0xFF2196F3), size: 16),
              SizedBox(width: 6),
              Text('Active listings by category',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A2E22))),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _categoryRow(top[i].key, top[i].value, total, _palette[i % _palette.length]),
          ],
        ],
      ),
    );
  }

  Widget _categoryRow(String label, int count, int total, Color color) {
    final fraction = total == 0 ? 0.0 : count / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1A2E22))),
            ),
            Text('$count · ${(fraction * 100).round()}%',
                style: const TextStyle(fontSize: 10, color: Colors.black45)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 7,
            color: color.withOpacity(0.15),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: Container(color: color),
            ),
          ),
        ),
      ],
    );
  }
}
