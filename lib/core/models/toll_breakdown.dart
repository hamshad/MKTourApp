/// Toll breakdown value object (toll_price_implementation.md §1, §3.2, §4).
///
/// Never-throw tolerant parser shared by rider (02), driver (03), and
/// earnings (04) plans. Backend totals are authoritative: `total` is a
/// verbatim passthrough of `totalFare`/`totalCharged`/take-home keys and is
/// NEVER computed client-side (research Pitfall 1 — no double-counting).
/// Follows the `OutstandingBalance` tolerant style: absent keys → 0.0/false/
/// null defaults, string numbers coerced, malformed values never throw.
class TollInfo {
  /// Toll amount in GBP. 0.0 when absent or unparseable.
  final double tollFee;

  /// Toll road name (e.g. "M6 Toll Highway"), null when absent.
  final String? tollName;

  /// True when the payload explicitly flags a toll or tollFee > 0.
  final bool hasToll;

  /// Backend-authoritative total (totalFare/totalCharged/take-home),
  /// verbatim passthrough. Null when absent — never computed.
  final double? total;

  const TollInfo({
    this.tollFee = 0.0,
    this.tollName,
    this.hasToll = false,
    this.total,
  });

  /// No-toll equivalent — every later plan gates badges/rows on this.
  static TollInfo get none => const TollInfo();

  /// Coerce a payload value to double. num → toDouble, string → parse,
  /// anything else → 0.0. Never throws.
  static double _coerce(dynamic v) =>
      v is num ? v.toDouble() : num.tryParse('$v')?.toDouble() ?? 0.0;

  /// Coerce to double preserving absence: null stays null, unparseable
  /// non-null → null. Never throws.
  static double? _coerceOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return num.tryParse('$v')?.toDouble();
  }

  /// Truthy flag: bool true, non-zero num, or string 'true'/'1'.
  /// Never throws.
  static bool _flag(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().toLowerCase();
    return s == 'true' || s == '1';
  }

  /// Parse a fare-breakdown / fareDetails / earnings map (§1.2
  /// `fareBreakdown`, §3.2 `fareDetails`, §2.1 `earnings`). Never throws.
  ///
  /// Alias chain — tollFee: `tollFee ?? tollReimbursement ?? tollReimbursed
  /// ?? toll_fee`; name: `tollName ?? toll_name`; total: `totalFare ??
  /// totalCharged ?? totalDriverTakeHome ?? totalEstimatedTakeHome`
  /// (null when absent). hasToll: explicit flag OR `isTollIncurred` OR
  /// tollFee > 0.
  factory TollInfo.fromBreakdown(Map? data) {
    if (data == null) return TollInfo.none;
    final tollFee = _coerce(
      data['tollFee'] ??
          data['tollReimbursement'] ??
          data['tollReimbursed'] ??
          data['toll_fee'],
    );
    final tollName = data['tollName'] ?? data['toll_name'];
    return TollInfo(
      tollFee: tollFee,
      tollName: tollName?.toString(),
      hasToll: _flag(data['hasToll']) ||
          _flag(data['isTollIncurred']) ||
          tollFee > 0,
      total: _coerceOrNull(
        data['totalFare'] ??
            data['totalCharged'] ??
            data['totalDriverTakeHome'] ??
            data['totalEstimatedTakeHome'],
      ),
    );
  }

  /// Parse the fare-estimate TOP-LEVEL map (§1.1): `hasToll` flag plus
  /// nested `tollDetails {name, amount}`. Never throws.
  factory TollInfo.fromEstimate(Map? data) {
    if (data == null) return TollInfo.none;
    final rawDetails = data['tollDetails'];
    final details = rawDetails is Map ? rawDetails : const <dynamic, dynamic>{};
    final tollFee = _coerce(
      details['amount'] ?? data['tollFee'] ?? data['toll_fee'],
    );
    final tollName = details['name'] ?? data['tollName'] ?? data['toll_name'];
    return TollInfo(
      tollFee: tollFee,
      tollName: tollName?.toString(),
      hasToll: _flag(data['hasToll']) || tollFee > 0,
      total: _coerceOrNull(data['totalFare'] ?? data['total_with_toll']),
    );
  }

  /// Parse a per-category fare-estimate entry (§1.1 `categories[]`):
  /// `tollFee ?? toll_fee`, `totalFare ?? total_with_toll`. Never throws.
  factory TollInfo.fromCategory(Map? cat) {
    if (cat == null) return TollInfo.none;
    final tollFee = _coerce(cat['tollFee'] ?? cat['toll_fee']);
    final tollName = cat['tollName'] ?? cat['toll_name'];
    return TollInfo(
      tollFee: tollFee,
      tollName: tollName?.toString(),
      hasToll: _flag(cat['hasToll']) || tollFee > 0,
      total: _coerceOrNull(cat['totalFare'] ?? cat['total_with_toll']),
    );
  }
}
