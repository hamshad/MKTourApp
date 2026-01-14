/// Enum representing the different statuses a ride can have.
///
/// Status flow:
/// - [requested] - Initial state when rider requests a ride
/// - [accepted] - Driver has accepted the ride request
/// - [arrived] - Driver has arrived at pickup location
/// - [inProgress] - Ride is in progress (started after OTP verification)
/// - [completed] - Ride completed normally
/// - [earlyCompleted] - Ride ended early by driver with recalculated fare
/// - [cancelled] - Ride was cancelled
/// - [expired] - Ride request expired (no driver accepted)
enum RideStatus {
  requested,
  accepted,
  arrived,
  inProgress,
  completed,
  earlyCompleted,
  cancelled,
  expired;

  /// Convert enum to API-compatible string (snake_case)
  String toJson() {
    switch (this) {
      case RideStatus.requested:
        return 'requested';
      case RideStatus.accepted:
        return 'accepted';
      case RideStatus.arrived:
        return 'arrived';
      case RideStatus.inProgress:
        return 'in_progress';
      case RideStatus.completed:
        return 'completed';
      case RideStatus.earlyCompleted:
        return 'early_completed';
      case RideStatus.cancelled:
        return 'cancelled';
      case RideStatus.expired:
        return 'expired';
    }
  }

  /// Parse status from API response string
  static RideStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'requested':
      case 'pending': // Legacy support
        return RideStatus.requested;
      case 'accepted':
      case 'driver_assigned':
        return RideStatus.accepted;
      case 'arrived':
      case 'driver_arrived':
        return RideStatus.arrived;
      case 'in_progress':
      case 'started': // Legacy support
        return RideStatus.inProgress;
      case 'completed':
        return RideStatus.completed;
      case 'early_completed':
        return RideStatus.earlyCompleted;
      case 'cancelled':
        return RideStatus.cancelled;
      case 'expired':
        return RideStatus.expired;
      default:
        return RideStatus.requested;
    }
  }

  /// Get display name for UI
  String get displayName {
    switch (this) {
      case RideStatus.requested:
        return 'Requested';
      case RideStatus.accepted:
        return 'Driver Assigned';
      case RideStatus.arrived:
        return 'Driver Arrived';
      case RideStatus.inProgress:
        return 'In Progress';
      case RideStatus.completed:
        return 'Completed';
      case RideStatus.earlyCompleted:
        return 'Ended Early';
      case RideStatus.cancelled:
        return 'Cancelled';
      case RideStatus.expired:
        return 'Expired';
    }
  }

  /// Check if ride is active (not final state)
  bool get isActive {
    return this == RideStatus.requested ||
        this == RideStatus.accepted ||
        this == RideStatus.arrived ||
        this == RideStatus.inProgress;
  }

  /// Check if ride is in a final state
  bool get isFinal {
    return this == RideStatus.completed ||
        this == RideStatus.earlyCompleted ||
        this == RideStatus.cancelled ||
        this == RideStatus.expired;
  }
}
