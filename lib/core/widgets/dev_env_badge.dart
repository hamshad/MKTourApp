import 'package:flutter/material.dart';
import '../constants.dart';

/// Persistent environment badge — visible on every screen while
/// [AppConstants.isDev] is true so it's always obvious which backend
/// the build talks to. Renders nothing in prod.
class DevEnvBadge extends StatelessWidget {
  final Widget child;

  const DevEnvBadge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!AppConstants.isDev) return child;
    return Stack(
      children: [
        child,
        // Non-interactive pill, top-right below the status bar.
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          right: 12,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade700,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4),
                ],
              ),
              child: const Text(
                'DEV',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
