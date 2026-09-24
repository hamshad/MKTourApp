import 'package:flutter/material.dart';

import '../../../core/models/app_version.dart';
import '../../../core/services/app_version_service.dart';
import '../../../core/theme.dart';

/// Non-dismissible full-screen block for FORCE updates.
/// Back button disabled via PopScope; no close icon.
class ForceUpdateScreen extends StatelessWidget {
  final AppVersionResult result;
  final VoidCallback? onResumeRecheck;

  const ForceUpdateScreen({
    super.key,
    required this.result,
    this.onResumeRecheck,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.system_update_rounded,
                  size: 88,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(height: 24),
                Text(
                  result.title?.isNotEmpty == true
                      ? result.title!
                      : 'Update Required',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  result.message?.isNotEmpty == true
                      ? result.message!
                      : 'This version is outdated. Please update to continue.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (result.latestVersion != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Latest version: ${result.latestVersion}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => AppVersionService.openStore(
                    result.storeUrl,
                    result.platform,
                  ),
                  child: const Text('Update Application'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Maintenance screen with Retry → re-calls check-version.
class MaintenanceScreen extends StatelessWidget {
  final AppVersionResult result;
  final VoidCallback onRetry;
  final bool isRetrying;

  const MaintenanceScreen({
    super.key,
    required this.result,
    required this.onRetry,
    this.isRetrying = false,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.construction_rounded,
                  size: 88,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(height: 24),
                Text(
                  result.title?.isNotEmpty == true
                      ? result.title!
                      : 'Under Maintenance',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  result.message?.isNotEmpty == true
                      ? result.message!
                      : 'MK Tours is currently undergoing scheduled maintenance. Please check back shortly.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: isRetrying ? null : onRetry,
                  child: isRetrying
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Flexible SOFT update dialog: Update → store, Later → dismiss + continue.
Future<void> showSoftUpdateDialog(
  BuildContext context,
  AppVersionResult result,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      title:
          Text(result.title?.isNotEmpty == true ? result.title! : 'New Update Available'),
      content: Text(
        result.message?.isNotEmpty == true
            ? result.message!
            : 'A new version is available with performance improvements and new features.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Later'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            AppVersionService.openStore(result.storeUrl, result.platform);
          },
          child: const Text('Update'),
        ),
      ],
    ),
  );
}
