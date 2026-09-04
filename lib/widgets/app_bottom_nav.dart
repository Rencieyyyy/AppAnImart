import 'package:flutter/material.dart';

import 'notification_dot.dart';

/// The app's four main tabs. Home / Explore / Announcements / Profile each
/// live on their own page, and every one of them renders THIS widget, so the
/// bar is pixel-identical everywhere.
///
/// Together with [instantRoute] (which swaps tabs with no transition), that
/// makes the bar look like a fixed piece of chrome instead of something that
/// slides in with each page.
class AppBottomNav extends StatelessWidget {
  static const Color brand = Color(0xFF6DBF99);

  /// Which tab is highlighted: 0 Home, 1 Explore, 2 Announcements, 3 Profile.
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Red dot on the bell while unseen announcements exist.
  final bool hasUnseenAnnouncements;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.hasUnseenAnnouncements = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        backgroundColor: Colors.white,
        selectedItemColor: brand,
        unselectedItemColor: Colors.black45,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart_outlined),
            activeIcon: Icon(Icons.shopping_cart),
            label: 'Explore',
          ),
          BottomNavigationBarItem(
            icon: NotificationDot(
              show: hasUnseenAnnouncements,
              child: const Icon(Icons.notifications_outlined),
            ),
            activeIcon: NotificationDot(
              show: hasUnseenAnnouncements,
              child: const Icon(Icons.notifications),
            ),
            label: 'Announcements',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// A route that swaps pages with NO animation.
///
/// The four tabs are separate pages, so the default `MaterialPageRoute` slid
/// the whole screen — bottom bar included — in from the right on every tap,
/// which read as the nav bar "popping" each time. With a zero-length
/// transition and an identical [AppBottomNav] on the incoming page, the bar
/// stays put and only the content above it changes.
Route<T> instantRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
  );
}
