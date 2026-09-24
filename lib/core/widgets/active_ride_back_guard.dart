import 'package:flutter/material.dart';

/// Prevents an active ride screen from exposing booking routes underneath it.
///
/// A live or restored ride owns its Navigator stack until it reaches a
/// terminal state. Blocking the pop keeps riders on tracking instead of
/// returning to a stale select-ride/search route.
class ActiveRideBackGuard extends StatelessWidget {
  final Widget child;
  final bool enabled;
  final String message;

  const ActiveRideBackGuard({
    super.key,
    required this.child,
    this.enabled = true,
    this.message = 'Your ride is still active. Stay here to track your driver.',
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
      },
      child: child,
    );
  }
}
