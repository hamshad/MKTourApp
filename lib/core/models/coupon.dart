/// Coupon models (coupons spec P1, P3).
///
/// Tolerant, never throws (FareSummary style): missing keys default,
/// junk input yields empty objects, every value passes coercion helpers.
/// Money values are VERBATIM backend passthroughs — the UI never
/// computes discounts client-side.

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// Response of POST /coupons/validate (spec P1).
class CouponValidation {
  final bool isValid;
  final String? couponId;
  final String? campaignId;
  final String code;
  final String discountType; // 'percentage' | 'fixed'
  final double discountValue;
  final double computedDiscount;
  final double originalFare;
  final double finalFare;

  const CouponValidation({
    this.isValid = false,
    this.couponId,
    this.campaignId,
    this.code = '',
    this.discountType = 'percentage',
    this.discountValue = 0.0,
    this.computedDiscount = 0.0,
    this.originalFare = 0.0,
    this.finalFare = 0.0,
  });

  factory CouponValidation.fromJson(Map<String, dynamic> json) {
    return CouponValidation(
      isValid: json['isValid'] == true,
      couponId: json['couponId']?.toString(),
      campaignId: json['campaignId']?.toString(),
      code: json['code']?.toString() ?? '',
      discountType: json['discountType']?.toString() ?? 'percentage',
      discountValue: _asDouble(json['discountValue']),
      computedDiscount: _asDouble(json['computedDiscount']),
      originalFare: _asDouble(json['originalFare']),
      finalFare: _asDouble(json['finalFare']),
    );
  }

  factory CouponValidation.parse(dynamic raw) {
    if (raw is Map<String, dynamic>) return CouponValidation.fromJson(raw);
    if (raw is Map) {
      return CouponValidation.fromJson(Map<String, dynamic>.from(raw));
    }
    return const CouponValidation();
  }

  Map<String, dynamic> toJson() => {
        'isValid': isValid,
        'couponId': couponId,
        'campaignId': campaignId,
        'code': code,
        'discountType': discountType,
        'discountValue': discountValue,
        'computedDiscount': computedDiscount,
        'originalFare': originalFare,
        'finalFare': finalFare,
      };
}

/// Campaign fields nested inside a wallet coupon (spec P3).
class CouponCampaign {
  final String name;
  final String description;
  final String discountType;
  final double discountValue;
  final double maxDiscountAmount;
  final double minFare;
  final List<String> applicableVehicles;
  final List<String> applicableRideTypes;
  final DateTime? validUntil;

  const CouponCampaign({
    this.name = '',
    this.description = '',
    this.discountType = 'percentage',
    this.discountValue = 0.0,
    this.maxDiscountAmount = 0.0,
    this.minFare = 0.0,
    this.applicableVehicles = const [],
    this.applicableRideTypes = const [],
    this.validUntil,
  });

  factory CouponCampaign.fromJson(Map<String, dynamic> json) {
    return CouponCampaign(
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      discountType: json['discountType']?.toString() ?? 'percentage',
      discountValue: _asDouble(json['discountValue']),
      maxDiscountAmount: _asDouble(json['maxDiscountAmount']),
      minFare: _asDouble(json['minFare']),
      applicableVehicles: _asStringList(json['applicableVehicles']),
      applicableRideTypes: _asStringList(json['applicableRideTypes']),
      validUntil: _asDateTime(json['validUntil']),
    );
  }

  factory CouponCampaign.parse(dynamic raw) {
    if (raw is Map<String, dynamic>) return CouponCampaign.fromJson(raw);
    if (raw is Map) return CouponCampaign.fromJson(Map<String, dynamic>.from(raw));
    return const CouponCampaign();
  }
}

List<String> _asStringList(dynamic v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  return const [];
}

DateTime? _asDateTime(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v);
}

/// Human label for a discount value: `15%` or `£5.00`.
String couponDiscountLabel(String discountType, double value) {
  if (discountType == 'fixed') return '£${value.toStringAsFixed(2)}';
  return '${value.toStringAsFixed(0)}%';
}

/// One coupon in the user's wallet (spec P3).
class CouponWalletItem {
  final String id;
  final String code;
  final String status; // 'active' | 'used' | 'expired'
  final int maxUses;
  final int usedCount;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final CouponCampaign campaign;

  const CouponWalletItem({
    this.id = '',
    this.code = '',
    this.status = 'active',
    this.maxUses = 0,
    this.usedCount = 0,
    this.expiresAt,
    this.createdAt,
    this.campaign = const CouponCampaign(),
  });

  factory CouponWalletItem.fromJson(Map<String, dynamic> json) {
    return CouponWalletItem(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      maxUses: _asInt(json['maxUses']),
      usedCount: _asInt(json['usedCount']),
      expiresAt: _asDateTime(json['expiresAt']),
      createdAt: _asDateTime(json['createdAt']),
      campaign: CouponCampaign.parse(json['campaign']),
    );
  }

  factory CouponWalletItem.parse(dynamic raw) {
    if (raw is Map<String, dynamic>) return CouponWalletItem.fromJson(raw);
    if (raw is Map) {
      return CouponWalletItem.fromJson(Map<String, dynamic>.from(raw));
    }
    return const CouponWalletItem();
  }

  bool get isFullyUsed => maxUses > 0 && usedCount >= maxUses;
}

/// Pagination block on the wallet response.
class CouponPagination {
  final int total;
  final int page;
  final int limit;
  final int pages;

  const CouponPagination({
    this.total = 0,
    this.page = 1,
    this.limit = 20,
    this.pages = 0,
  });

  factory CouponPagination.fromJson(Map<String, dynamic> json) {
    return CouponPagination(
      total: _asInt(json['total']),
      page: _asInt(json['page']) == 0 ? 1 : _asInt(json['page']),
      limit: _asInt(json['limit']) == 0 ? 20 : _asInt(json['limit']),
      pages: _asInt(json['pages']),
    );
  }

  bool get hasNextPage => page < pages;
}

/// Full GET /coupons/wallet response `data` (spec P3).
class CouponWallet {
  final List<CouponWalletItem> coupons;
  final CouponPagination pagination;

  const CouponWallet({
    this.coupons = const [],
    this.pagination = const CouponPagination(),
  });

  factory CouponWallet.fromJson(Map<String, dynamic> json) {
    final rawCoupons = json['coupons'];
    return CouponWallet(
      coupons: rawCoupons is List
          ? rawCoupons.map((e) => CouponWalletItem.parse(e)).toList()
          : const [],
      pagination: json['pagination'] is Map
          ? CouponPagination.fromJson(
              Map<String, dynamic>.from(json['pagination'] as Map),
            )
          : const CouponPagination(),
    );
  }

  factory CouponWallet.parse(dynamic raw) {
    if (raw is Map<String, dynamic>) return CouponWallet.fromJson(raw);
    if (raw is Map) return CouponWallet.fromJson(Map<String, dynamic>.from(raw));
    return const CouponWallet();
  }
}