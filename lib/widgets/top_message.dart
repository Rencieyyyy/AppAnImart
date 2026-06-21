import 'package:flutter/material.dart';

/// Shows a popup message box that slides in from the top of the screen.
///
/// This replaces [SnackBar] across the app with a consistent top-anchored
/// popup. By default it is styled as an error (red); pass [isError] = false
/// for a success message, or provide a custom [backgroundColor] / [icon].
void showTopMessage(
  BuildContext context,
  String message, {
  bool isError = true,
  Color? backgroundColor,
  IconData? icon,
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Overlay.of(context, rootOverlay: true);

  final bg = backgroundColor ??
      (isError ? const Color(0xFFE53935) : const Color(0xFF3AA876));
  final iconData =
      icon ?? (isError ? Icons.error_outline : Icons.check_circle_outline);

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _TopMessage(
      message: message,
      backgroundColor: bg,
      icon: iconData,
      duration: duration,
      onDismissed: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _TopMessage extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final IconData icon;
  final Duration duration;
  final VoidCallback onDismissed;

  const _TopMessage({
    required this.message,
    required this.backgroundColor,
    required this.icon,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_TopMessage> createState() => _TopMessageState();
}

class _TopMessageState extends State<_TopMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _offset = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    await _controller.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPadding + 12,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _offset,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: _dismiss,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(widget.icon, color: Colors.white, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.close, color: Colors.white70, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
