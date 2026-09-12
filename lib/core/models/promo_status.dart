/// Typed model for `GET /api/v1/users/promo-status` data envelope.
///
/// Covers the 4-state backend contract: none | eligible | pending | claimed.
/// Backend treats `isPending` users as ineligible for second-ride discounts
/// automatically, so this model carries no client-side blocking logic — it
/// only parses and exposes the flags for UI (plan 09-02 consumes it).
library;

/// The four promo states returned by the backend.
enum PromoState {
  none,
  eligible,
  pending,
  claimed;

  /// Parses a raw status string; unknown/null values default to [none].
  static PromoState fromString(String? value) {
    switch (value) {
      case 'eligible':
        return PromoState.eligible;
      case 'pending':
        return PromoState.pending;
      case 'claimed':
        return PromoState.claimed;
      case 'none':
      default:
        return PromoState.none;
    }
  }
}

/// Parsed promo-status payload (the `data` map of the API envelope).
class PromoStatus {
  /// Rides completed towards the free-ride promo.
  final int completedRides;

  /// Typed promo state.
  final PromoState state;

  /// Raw `promoStatus` string from the backend (for debug/logging).
  final String rawStatus;

  /// Rides remaining until the user becomes eligible.
  final int ridesUntilEligible;

  /// True when the user can claim a free ride now.
  final bool isEligible;

  /// True when the free ride is locked to an already-booked ride.
  final bool isPending;

  /// True when the free ride was already claimed.
  final bool isClaimed;

  /// Human-readable status copy from the backend.
  final String message;

  const PromoStatus({
    this.completedRides = 0,
    this.state = PromoState.none,
    this.rawStatus = 'none',
    this.ridesUntilEligible = 0,
    this.isEligible = false,
    this.isPending = false,
    this.isClaimed = false,
    this.message = '',
  });

  /// Parses the `data` map of the promo-status envelope.
  ///
  /// Never throws on malformed input: missing keys fall back to the `none`
  /// state with zeroed counters and empty message.
  factory PromoStatus.fromMap(Map<String, dynamic> data) {
    final raw = data['promoStatus']?.toString() ?? 'none';
    return PromoStatus(
      completedRides: (data['completedRides'] as num?)?.toInt() ?? 0,
      state: PromoState.fromString(raw),
      rawStatus: raw,
      ridesUntilEligible:
          (data['ridesUntilEligible'] as num?)?.toInt() ?? 0,
      isEligible: data['isEligible'] == true,
      isPending: data['isPending'] == true,
      isClaimed: data['isClaimed'] == true,
      message: data['message']?.toString() ?? '',
    );
  }

  /// True when state is [PromoState.none].
  bool get isNone => state == PromoState.none;

  /// True when state is [PromoState.eligible].
  bool get isEligibleState => state == PromoState.eligible;

  /// True when state is [PromoState.pending].
  bool get isPendingState => state == PromoState.pending;

  /// True when state is [PromoState.claimed].
  bool get isClaimedState => state == PromoState.claimed;

  @override
  String toString() {
    return 'PromoStatus(state: ${state.name}, completedRides: $completedRides, '
        'ridesUntilEligible: $ridesUntilEligible, isEligible: $isEligible, '
        'isPending: $isPending, isClaimed: $isClaimed, message: $message)';
  }
}
