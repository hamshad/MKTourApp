import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../constants/api_constants.dart';
import '../models/coupon.dart';

/// Coupon validation + wallet API (coupons spec P1/P3).
///
/// Static methods, `ApiConfig.getAuthHeaders()` auth, raw `package:http`
/// (PaymentService style). Money values pass through untouched.
class CouponService {
  CouponService._();

  /// POST /coupons/validate (spec P1) — live booking preview.
  ///
  /// 200 → [CouponValidation] (may have `isValid: false`).
  /// 400 → throws [CouponException] carrying the server `message`
  /// verbatim (invalid code, min fare, expired, vehicle ineligible —
  /// backend decides, client only displays).
  static Future<CouponValidation> validateCoupon({
    required String code,
    required double fare,
    required String vehicleCategorySlug,
    bool isScheduled = false,
    bool isAirportTransfer = false,
  }) async {
    final headers = await ApiConfig.getAuthHeaders();
    final body = {
      'code': code,
      'fare': fare,
      'vehicleCategorySlug': vehicleCategorySlug,
      'isScheduled': isScheduled,
      'isAirportTransfer': isAirportTransfer,
    };

    debugPrint('🎫 CouponService.validateCoupon: $body');
    final response = await http.post(
      Uri.parse(ApiConstants.validateCoupon),
      headers: headers,
      body: jsonEncode(body),
    );
    debugPrint(
      '🎫 CouponService: ${response.statusCode} ${response.body}',
    );

    final decoded = _safeDecode(response.body);
    final message = decoded['message']?.toString();

    if (response.statusCode == 200) {
      final data = decoded['data'];
      if (data is Map) {
        return CouponValidation.fromJson(Map<String, dynamic>.from(data));
      }
      return CouponValidation.parse(data);
    }

    throw CouponException(
      message ?? 'Invalid or unauthorized coupon code',
      statusCode: response.statusCode,
    );
  }

  /// GET /coupons/wallet?status=&page=&limit= (spec P3).
  static Future<CouponWallet> fetchWallet({
    String status = 'active',
    int page = 1,
    int limit = 20,
  }) async {
    final headers = await ApiConfig.getAuthHeaders();
    final url = ApiConstants.couponWallet(
      status: status,
      page: page,
      limit: limit,
    );

    debugPrint('🎫 CouponService.fetchWallet: $url');
    final response = await http.get(Uri.parse(url), headers: headers);
    debugPrint(
      '🎫 CouponService wallet: ${response.statusCode} ${response.body}',
    );

    final decoded = _safeDecode(response.body);
    if (response.statusCode == 200) {
      return CouponWallet.parse(decoded['data'] ?? decoded);
    }
    throw CouponException(
      decoded['message']?.toString() ?? 'Failed to load coupons',
      statusCode: response.statusCode,
    );
  }

  static Map<String, dynamic> _safeDecode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }
}

/// Server-rejected coupon/wallet call. [message] is the backend copy,
/// shown to the user as-is.
class CouponException implements Exception {
  final String message;
  final int statusCode;

  const CouponException(this.message, {this.statusCode = 0});

  @override
  String toString() => message;
}