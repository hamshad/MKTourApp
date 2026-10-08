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
        '🚗 *MK Tours — Your ride, your way.*\n\n'
        'Need to get somewhere? Just choose your *pickup point and destination*, book your ride, and let MK Tours take care of the rest. 📍\n\n'
        '✨ Easy ride booking\n'
        '📍 Choose your pickup & destination\n'
        '🚘 Get a ride when you need it\n'
        '💳 Simple & convenient payments\n'
        '🛡️ Ride with trusted drivers\n\n'
        '📲 *Download MK Tours and book your next ride:*\n\n'
        '🤖 *Android*\n'
        '$androidAppLink\n\n'
        '🍎 *iPhone*\n'
        '$iosAppLink\n\n'
        '*Wherever you\'re going, just book a ride with MK Tours.* 🚘';

    await _share(message, subject: subject ?? 'Share MK Tours');
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