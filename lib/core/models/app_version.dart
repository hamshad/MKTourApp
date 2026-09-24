/// App version control models — mirrors GET /api/v1/app/check-version.
enum AppUpdateType { none, soft, force, maintenance }

AppUpdateType appUpdateTypeFromString(String? raw) {
  switch (raw?.toUpperCase()) {
    case 'SOFT':
      return AppUpdateType.soft;
    case 'FORCE':
      return AppUpdateType.force;
    case 'MAINTENANCE':
      return AppUpdateType.maintenance;
    case 'NONE':
    default:
      return AppUpdateType.none;
  }
}

class AppVersionResult {
  final String platform;
  final String appType;
  final AppUpdateType updateType;
  final bool canContinue;
  final String? title;
  final String? message;
  final String? storeUrl;
  final String? currentAppVersion;
  final String? minVersion;
  final String? latestVersion;

  const AppVersionResult({
    required this.platform,
    required this.appType,
    required this.updateType,
    required this.canContinue,
    this.title,
    this.message,
    this.storeUrl,
    this.currentAppVersion,
    this.minVersion,
    this.latestVersion,
  });

  bool get isBlocking =>
      updateType == AppUpdateType.force ||
      updateType == AppUpdateType.maintenance;

  factory AppVersionResult.allow({
    required String platform,
    required String appType,
  }) {
    return AppVersionResult(
      platform: platform,
      appType: appType,
      updateType: AppUpdateType.none,
      canContinue: true,
    );
  }

  factory AppVersionResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final Map<String, dynamic> d =
        data is Map<String, dynamic> ? data : Map<String, dynamic>.from(json);
    return AppVersionResult(
      platform: d['platform']?.toString() ?? '',
      appType: d['appType']?.toString() ?? '',
      updateType: appUpdateTypeFromString(d['updateType']?.toString()),
      canContinue: d['canContinue'] == true,
      title: d['title']?.toString(),
      message: d['message']?.toString(),
      storeUrl: d['storeUrl']?.toString(),
      currentAppVersion: d['currentAppVersion']?.toString(),
      minVersion: d['minVersion']?.toString(),
      latestVersion: d['latestVersion']?.toString(),
    );
  }
}
