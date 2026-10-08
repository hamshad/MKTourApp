import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ShareUtils {
  static const String androidAppLink = 'https://play.google.com/store/apps/details?id=com.mokshasolutions.mktours';
  static const String iosAppLink = 'https://apps.apple.com/us/app/mk-tours/id6757809090';

  static Future<void> shareApp({
    String? customMessage,
    String? subject,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final appName = packageInfo.appName;

    final message = customMessage ??
        'Check out $appName - the best way to book rides! '
            'Download now: Android: $androidAppLink | iOS: $iosAppLink';

    await _share(message, subject: subject ?? 'Share $appName');
  }

  static Future<void> shareAppWithReferral({
    String? referralCode,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final appName = packageInfo.appName;

    String message = 'Check out $appName - the best way to book rides! '
        'Download now: Android: $androidAppLink | iOS: $iosAppLink';

    if (referralCode != null && referralCode.isNotEmpty) {
      message += '\n\nUse my referral code: $referralCode';
    }

    await _share(message, subject: 'Share $appName');
  }

  static Future<void> _share(String text, {String? subject}) async {
    await Share.share(
      text,
      subject: subject,
      sharePositionOrigin: _defaultShareOrigin(),
    );
  }

  /// Provides a valid share origin rect for iOS share sheet popover.
  /// Uses a small rect at bottom-center of screen as safe default for iOS popover anchoring.
  static Rect _defaultShareOrigin() {
    // iPhone standard screen width ~375, height ~667 (logical points)
    // Use a small 1x1 rect at bottom-center to anchor the popover
    return const Rect.fromLTWH(187, 666, 1, 1);
  }
}