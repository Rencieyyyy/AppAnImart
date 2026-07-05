import 'package:flutter/material.dart';

/// Overlays a small red "new" dot on the top-right corner of [child] when
/// [show] is true (used on the bottom-nav announcements bell and the Seller
/// Dashboard's Offers action).
class NotificationDot extends StatelessWidget {
  final Widget child;
  final bool show;

  const NotificationDot({super.key, required this.child, required this.show});

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -2,
          right: -2,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: const Color(0xFFE53E3E),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
