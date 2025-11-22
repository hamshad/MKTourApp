import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:skyline/core/theme.dart';

enum SnackbarType { success, error, warning, info }

class CustomSnackbar {
  static void show(
    BuildContext context, {
    required String message,
    required SnackbarType type,
    String? title,
    Duration duration = const Duration(seconds: 4),
  }) {
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _TopBannerWidget(
        message: message,
        type: type,
        title: title,
        duration: duration,
        onDismiss: () {
          if (overlayEntry.mounted) {
            overlayEntry.remove();
          }
        },
      ),
    );

    Overlay.of(context).insert(overlayEntry);
  }
}

class _TopBannerWidget extends StatefulWidget {
  final String message;
  final SnackbarType type;
  final String? title;
  final Duration duration;
  final VoidCallback onDismiss;

  const _TopBannerWidget({
    Key? key,
    required this.message,
    required this.type,
    this.title,
    required this.duration,
    required this.onDismiss,
  }) : super(key: key);

  @override
  State<_TopBannerWidget> createState() => _TopBannerWidgetState();
}

class _TopBannerWidgetState extends State<_TopBannerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      reverseDuration: const Duration(milliseconds: 400),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
      reverseCurve: Curves.easeInBack,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // Start animation
    _controller.forward();

    // Auto dismiss
    Future.delayed(widget.duration, () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  void _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  Color _getAccentColor() {
    switch (widget.type) {
      case SnackbarType.success:
        return AppTheme.successColor;
      case SnackbarType.error:
        return AppTheme.errorColor;
      case SnackbarType.warning:
        return AppTheme.warningColor;
      case SnackbarType.info:
        return AppTheme.primaryColor;
    }
  }

  IconData _getIcon() {
    switch (widget.type) {
      case SnackbarType.success:
        return Icons.check_circle_rounded;
      case SnackbarType.error:
        return Icons.error_rounded;
      case SnackbarType.warning:
        return Icons.warning_rounded;
      case SnackbarType.info:
        return Icons.info_rounded;
    }
  }

  String _getDefaultTitle() {
    if (widget.title != null) return widget.title!;
    switch (widget.type) {
      case SnackbarType.success:
        return 'Success';
      case SnackbarType.error:
        return 'Error';
      case SnackbarType.warning:
        return 'Warning';
      case SnackbarType.info:
        return 'Info';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _getAccentColor();

    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _slideAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Dismissible(
                key: UniqueKey(),
                direction: DismissDirection.up,
                onDismissed: (_) => widget.onDismiss(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                        spreadRadius: 0,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.8),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon Bubble
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _getIcon(),
                          color: accentColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      
                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _getDefaultTitle(),
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.message,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: AppTheme.textSecondary,
                                height: 1.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      
                      // Close Button (Optional, but good for UX)
                      GestureDetector(
                        onTap: _dismiss,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4),
                          child: Icon(
                            Icons.close_rounded,
                            color: AppTheme.textSecondary.withValues(alpha: 0.5),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
