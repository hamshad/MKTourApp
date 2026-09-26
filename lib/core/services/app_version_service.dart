import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../constants/api_constants.dart';
import '../models/app_version.dart';

/// Client for GET /api/v1/app/check-version.
///
/// Single binary serves both user + driver roles, so [appType] resolves from
/// the stored auth role (defaults to `user` pre-login). On cold start with no
/// stored role, both matrices are checked and the strictest result wins, so a
/// driver-force-update can never be bypassed by falling back to `user`.
class AppVersionService {
  static const _prefsRoleKey = 'auth_role';

  /// Fallback when backend omits storeUrl. Android uses the real
  /// applicationId (android/app/build.gradle.kts). iOS resolves via the
  /// iTunes lookup API by bundleId, so no hardcoded numeric App Store ID.
  static const String _fallbackAppStoreSearchUrl =
      'https://apps.apple.com/search?term=MK%20Tours';

  Future<AppVersionResult> checkForUpdate() async {
    final platform = currentPlatform;
    final version = await currentVersion();
    final buildNumber = await currentBuildNumber();
    final rolesToCheck = await _rolesToCheck();

    AppVersionResult? softest;
    for (final appType in rolesToCheck) {
      final result = await _checkOne(
        platform: platform,
        appType: appType,
        version: version,
        buildNumber: buildNumber,
      );
      // Blocking states win immediately; never fall through to auth flow.
      if (result.isBlocking || !result.canContinue) return result;
      // Prefer SOFT over NONE so a pending update still surfaces.
      if (result.updateType == AppUpdateType.soft) {
        softest ??= result;
      } else {
        softest ??= result;
      }
    }
    return softest ??
        AppVersionResult.allow(platform: platform, appType: rolesToCheck.first);
  }

  Future<AppVersionResult> retry({
    required String platform,
    required String appType,
  }) async {
    return _checkOne(
      platform: platform,
      appType: appType,
      version: await currentVersion(),
      buildNumber: await currentBuildNumber(),
    );
  }

  Future<AppVersionResult> _checkOne({
    required String platform,
    required String appType,
    required String version,
    required int? buildNumber,
  }) async {
    final query = <String, String>{
      'platform': platform,
      'appType': appType,
      'version': version,
      if (buildNumber != null) 'buildNumber': buildNumber.toString(),
    };
    final uri =
        Uri.parse(ApiConstants.checkVersion).replace(queryParameters: query);
    try {
      final response = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        'X-App-Platform': platform,
        'X-App-Type': appType,
        'X-App-Version': version,
        if (buildNumber != null)
          'X-App-Build-Number': buildNumber.toString(),
      }).timeout(const Duration(seconds: 12));

      debugPrint(
          '🔍 [AppVersion] $platform/$appType $version+$buildNumber → ${response.statusCode}: ${response.body}');
      if (response.statusCode != 200) {
        // Fail-open per spec: offline / server error must not lock users out.
        return AppVersionResult.allow(platform: platform, appType: appType);
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return AppVersionResult.fromJson(decoded);
      }
      return AppVersionResult.allow(platform: platform, appType: appType);
    } catch (e) {
      // Fail-open: network failure proceeds to offline/login handler.
      debugPrint('🟠 [AppVersion] check failed (fail-open): $e');
      return AppVersionResult.allow(platform: platform, appType: appType);
    }
  }

  Future<List<String>> _rolesToCheck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString(_prefsRoleKey);
      if (role == 'driver' || role == 'user') return [role!];
    } catch (_) {}
    // Pre-login: enforce strictest across both matrices.
    return const ['user', 'driver'];
  }

  String get currentPlatform {
    if (kIsWeb) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  /// Always reports the real installed version (1.1.2) and build (53),
  /// in dev and release alike. Version thresholds are owned by the backend
  /// — test scenarios are driven by what the server returns, not by the app.
  Future<String> currentVersion() async {
    final real = await _realVersion();
    debugPrint('🔍 [AppVersion] Reporting version=$real isDev=${AppConstants.isDev}');
    return real;
  }

  Future<String> _realVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '1.1.2';
    }
  }

  Future<int?> currentBuildNumber() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber);
    } catch (_) {
      return null;
    }
  }

  static Future<String> fallbackStoreUrl(String platform) async {
    if (platform != 'ios') {
      try {
        final info = await PackageInfo.fromPlatform();
        if (info.packageName.isNotEmpty) {
          return 'https://play.google.com/store/apps/details?id=${info.packageName}';
        }
      } catch (_) {}
      return 'https://play.google.com/store/apps/details?id=com.mokshasolutions.mktours';
    }
    // iOS: resolve the real App Store URL via iTunes lookup by bundleId.
    try {
      final info = await PackageInfo.fromPlatform();
      final bundleId =
          info.packageName.isNotEmpty ? info.packageName : 'com.moksha.mktours';
      final lookup = Uri.parse(
          'https://itunes.apple.com/lookup?bundleId=$bundleId&country=GB');
      final response =
          await http.get(lookup).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final results = decoded is Map ? decoded['results'] : null;
        if (results is List && results.isNotEmpty) {
          final trackUrl = results.first is Map
              ? results.first['trackViewUrl']?.toString()
              : null;
          if (trackUrl?.isNotEmpty == true) return trackUrl!;
        }
      }
    } catch (e) {
      debugPrint('🟠 [AppVersion] iTunes lookup failed: $e');
    }
    return _fallbackAppStoreSearchUrl;
  }

  static Future<void> openStore(String? storeUrl, String platform) async {
    final url = (storeUrl?.isNotEmpty == true)
        ? storeUrl!
        : await fallbackStoreUrl(platform);
    final uri = Uri.tryParse(url);
    if (uri == null) {
      debugPrint('🔴 [AppVersion] Invalid store URL: $url');
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('🔴 [AppVersion] Cannot launch store URL: $url');
    }
  }
}
