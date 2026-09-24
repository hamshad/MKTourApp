import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth_provider.dart';

import 'package:latlong2/latlong.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import '../../core/api_service.dart';
import '../../core/theme.dart';
import '../../core/widgets/platform_map.dart';
import '../../core/widgets/route_map_helpers.dart';
import 'driver_request_panel.dart';
import 'driver_navigation_panel.dart';
import 'widgets/b2b_offer_card.dart';
import '../../core/widgets/connection_banner.dart';
import '../../core/widgets/custom_snackbar.dart';
import '../../core/models/error_display_helper.dart';
import '../../core/models/vehicle.dart';
import '../../core/services/socket_service.dart';
import '../../core/services/ride_event_dedupe.dart';
import '../../core/services/ride_session.dart';
import '../../core/services/location_service.dart';
import '../../core/services/navigation_service.dart';
import '../../core/services/active_ride_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/audio_service.dart';
import '../../core/services/fcm_service.dart';
import '../../core/services/payment_service.dart';
import '../../core/models/queued_ride.dart';
import 'driver_scheduled_rides_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen>
    with WidgetsBindingObserver {
  // Status: offline, online, request, pickup, arrived, in_progress, complete
  String _status = 'offline';
  final PanelController _panelController = PanelController();

  // Location
  final LocationService _locationService = LocationService();
  LatLng _currentLocation = const LatLng(51.5085, -0.1260); // London fallback
  bool _isMapLoading = false; // Start false to show map immediately
  double _currentBearing = 0.0;
  StreamSubscription<Position>? _positionStreamSubscription;

  String? _currentRideId;
  Map<String, dynamic>? _rideData;

  // Pending-request queue: concurrent ride:newRequest payloads stack here
  // while a card is open. _rideData/_currentRideId mirror
  // queue[_requestIndex] so accept/decline and downstream execution keep
  // working unchanged. (Panel UI wiring lands in 10-02.)
  final List<Map<String, dynamic>> _requestQueue = [];
  int _requestIndex = 0;
  static const int _maxQueuedRequests = 5;

  // Back-to-back dispatch (driver-multirequest.md §5.1, 20-02):
  // `_b2bOffer` is a pending B2B offer received mid-trip; `_queuedTrip` is
  // the accepted queued trip (status accepted, isQueued true) docked while
  // Trip A (`_currentRideId`/`_rideData`) stays authoritative for the map
  // and every action button. Both are memory-only: cold start never
  // restores them (server promotion is authoritative; stale queued state
  // must never strand the UI).
  Map<String, dynamic>? _b2bOffer;
  Map<String, dynamic>? _queuedTrip;
  bool _b2bAccepting = false;
  String? _b2bOfferError;
  void Function(dynamic)? _nextTripListener;
  // Deferred promotion: Trip A was cash, so the queued promotion fires
  // after cash confirmation instead of at completion (20-02).
  bool _queuedPromotionPending = false;

  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  final SocketService _socketService = SocketService();
  final NavigationService _navigationService = NavigationService();

  // Navigation State
  NavigationState? _navigationState;
  List<MapPolyline> _navigationPolylines = [];

  // Data State
  List<dynamic> _recentRides = [];
  Map<String, dynamic> _todayStats = {
    'trips': '0',
    'hours': '0.0',
    'earnings': '0.0',
  };
  bool _isHistoryLoading = false;

  // Connection status subscription for reconnection handling
  StreamSubscription<bool>? _connectionSubscription;

  // Last emitted location timestamp to throttle updates
  DateTime? _lastEmitTime;
  static const int _minEmitIntervalMs = 3000; // Minimum 3 seconds between emits

  // Last position update timestamp (drives emit throttling bookkeeping)
  DateTime? _lastPositionUpdateTime;
  // Silent telemetry: consecutive location failures (debugPrint only, no UI).
  int _consecutiveLocationFailures = 0;

  // Track if socket listeners are set up to re-register after reconnection
  bool _socketListenersSetup = false;

  // Debounce for driver:goOnline re-emits: reconnect + resume + tap paths
  // can fire within milliseconds of each other; the server treats repeats
  // as redundant status broadcasts. Coalescing in SocketEventQueue bounds
  // the offline case — this bounds the connected case.
  DateTime? _lastDriverOnlineEmitAt;
  static const Duration _driverOnlineDebounce = Duration(seconds: 10);

  // Store driverId to use in dispose without accessing context
  String? _driverId;

  // FCM notification subscriptions
  StreamSubscription<FcmNotificationData>? _fcmSubscription;
  StreamSubscription<FcmNotificationData>? _fcmForegroundSubscription;

  // Scheduled pool state
  List<dynamic> _scheduledPool = [];
  bool _isPoolLoading = false;
  String? _acceptError;

  // Proximity guidance: set on 400 distance errors (pickup or stop), cleared
  // on success. Drives the persistent banner — never a dismiss-only toast.
  int? _proximityDistance;
  int? _proximityRequired;
  String _proximityTarget = 'pickup';

  // Free-wait policy from arrive/stop-arrive success (backend authoritative,
  // WaitFeePolicy fallback). Shown as a chip once arrived/at-stop.
  int? _freeWaitMinutes;
  double? _freeWaitRate;

  // Stage 2 excess-cash collect modal (STAGE2-04/05/06). Flag guards
  // duplicate opens + cancelled auto-close; dialog context pops the modal
  // from socket callbacks without touching the outer BuildContext.
  bool _excessCashDialogOpen = false;
  BuildContext? _excessCashDialogContext;

  // Phase 14 CONFIRM-04: per-ride toast-once guard for the confirmed
  // close-out. The modal may already be
  // closed (local confirm tap, co-fired succeeded) while the confirmed
  // toast must still fire exactly once — so the guard is keyed by event
  // rideId, NOT by _excessCashDialogOpen. Reset when a new excess request
  // arrives for the same ride so a fresh round-trip can toast again.
  final Set<String> _excessCashConfirmedToastRideIds = {};

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 [DriverHomeScreen] initState() initiated');
    WidgetsBinding.instance.addObserver(this);
    
    // Concurrent initialization
    _initDriver().then((_) => debugPrint('🚀 [DriverHomeScreen] _initDriver() finished'));
    _initLocation().then((_) => debugPrint('🚀 [DriverHomeScreen] _initLocation() finished'));
    _setupConnectionListener();
    _setupFcmListener();
    debugPrint('🚀 [DriverHomeScreen] initState() finished (futures pending)');
  }

  /// Listen for FCM notifications directly in the home screen
  ///
  /// No RideEventDedupe re-check here: FcmService already applied the shared
  /// FCM/socket guard (sound + tray banner exactly once), and re-checking the
  /// same key would always lose — the service consumed it synchronously before
  /// emitting to this stream, which made the whole FCM path dead (sound with
  /// no card whenever the socket event was missed). Single-card safety comes
  /// from the per-ride queue dedupe inside [_handleNewRideRequest]. `quiet`
  /// avoids a second ring — FCM already played the sound on this path.
  void _setupFcmListener() {
    // Handle notification tap (user taps tray → app opens)
    _fcmSubscription = FcmService.instance.onNotificationTap.listen((data) {
      if (data.type == NotificationType.rideRequest) {
        debugPrint('🔔 [DriverHomeScreen] Received rideRequest via FCM tap');
        if (mounted) {
          _handleNewRideRequest(data.rawData, quiet: true);
        }
      } else if (data.type == NotificationType.excessCashRequested) {
        // Tapped the excess-cash banner (e.g. app was backgrounded) — raise
        // the Collect-Cash modal. No dedupe re-check: the tap path never
        // consumes the shared key, and the dialog-open flag guards doubles.
        debugPrint('💰 [DriverHomeScreen] Excess cash via FCM tap');
        if (mounted) {
          _handleExcessCashRequest(data.rawData, checkDedupe: false);
        }
      } else if (data.type == NotificationType.queuedRideCancelled) {
        // B2B: rider cancelled the queued trip while the app was away —
        // clear the pill, Trip A untouched (20-02).
        debugPrint('🔄 [DriverHomeScreen][B2B] Queued ride cancelled via FCM tap');
        if (mounted && _queuedTrip != null) {
          setState(() => _queuedTrip = null);
          CustomSnackbar.show(
            context,
            message: 'Your queued ride was cancelled by the passenger.',
            type: SnackbarType.info,
          );
        }
      } else if (data.type == NotificationType.excessCashCancelled) {
        if (mounted) _closeExcessCashDialogIfOpen();
      } else if (data.rideId != null && data.rideId!.isNotEmpty) {
        // Ride-lifecycle push tap (socket dead while backgrounded/terminated):
        // authoritative resync + room rejoin, never navigation. Reuses the
        // existing FcmService tap stream — no new push SDK.
        switch (data.type) {
          case NotificationType.rideCancelled:
          case NotificationType.rideCancelledByUser:
          case NotificationType.paymentSelected:
          case NotificationType.rideReminder:
          case NotificationType.scheduledRideCancelledByUser:
            resyncActiveRide(
              api: _apiService,
              socket: _socketService,
              rideId: data.rideId,
            );
            break;
          default:
            break;
        }
      }
    });

    // Handle foreground FCM (app already open) — scheduled rides arrive here
    // without a socket event, so we must auto-process the push notification
    _fcmForegroundSubscription =
        FcmService.instance.onForegroundNotification.listen((data) {
      if (data.type == NotificationType.rideRequest) {
        debugPrint('🔔 [DriverHomeScreen] Received rideRequest via FCM foreground');
        if (mounted) {
          _handleNewRideRequest(data.rawData, quiet: true);
        }
      } else if (data.type == NotificationType.excessCashRequested) {
        // FCM backup for the socket `payment:excessCashRequested` event —
        // raises the same modal so it appears with notifications off too.
        // No dedupe re-check here: FcmService already consumed the shared
        // canonical key before emitting; re-checking would always lose and
        // make this path dead. Sound already played by the service.
        debugPrint('💰 [DriverHomeScreen] Excess cash via FCM foreground');
        if (mounted) {
          _handleExcessCashRequest(data.rawData, checkDedupe: false);
        }
      } else if (data.type == NotificationType.queuedRideCancelled) {
        // B2B foreground: queued trip cancelled — clear pill only (20-02).
        debugPrint('🔄 [DriverHomeScreen][B2B] Queued ride cancelled via FCM');
        if (mounted && _queuedTrip != null) {
          setState(() => _queuedTrip = null);
          CustomSnackbar.show(
            context,
            message: 'Your queued ride was cancelled by the passenger.',
            type: SnackbarType.info,
          );
        }
      } else if (data.type == NotificationType.excessCashCancelled) {
        if (mounted) _closeExcessCashDialogIfOpen();
      }
    });
  }

  /// Shared Stage 2 excess-cash entry point for socket + FCM transports.
  /// Deliberately NOT gated on `_currentRideId`: online-pay rides reset the
  /// driver to idle (`_currentRideId = null`) on completion, and the rider
  /// selects the cash excess method afterwards — requiring a match drops
  /// every real event. The confirm call uses the event's own rideId.
  /// Exactly-once across transports via the shared canonical dedupe key
  /// plus the dialog-open flag; exactly-one-sound via `ring` (FCM path
  /// already rang in the service, so only the socket path rings here).
  void _handleExcessCashRequest(Map<String, dynamic> raw, {required bool checkDedupe, bool ring = false}) {
    if (!mounted) return;
    final map = Map<String, dynamic>.from(raw);
    if (checkDedupe &&
        !RideEventDedupe.shouldHandleEvent(
          source: 'socket',
          type: 'payment_excess_cash_requested',
          data: map,
        )) {
      return;
    }
    final rideId = _socketRideId(map);
    final rawAmount = map['excessAmount'] ?? map['amount'];
    final amount = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse(rawAmount?.toString() ?? '');
    if (rideId == null || amount == null) return;
    // New round-trip for this ride: allow the confirmed toast to fire again.
    _excessCashConfirmedToastRideIds.remove(rideId);
    if (ring) AudioService.instance.playNotification();
    _showExcessCashDialog(rideId, amount);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Save driverId early to use in dispose
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    _driverId = user?['_id'] ?? user?['id'] ?? user?['userId'];
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [DriverHomeScreen] App resumed, syncing state...');

      // Resume is silent: no GPS warnings. Just refresh the position clock
      // so tracking continues without surfacing any message on unlock.
      _lastPositionUpdateTime ??= DateTime.now();

      // 1. Force check socket connection
      if (!_socketService.isConnected) {
        debugPrint(
          '🔌 [DriverHomeScreen] Socket disconnected, reconnecting...',
        );
        _socketService.initSocket(forceReconnect: true);
      }

      // 2. Re-emit online status if driver is not offline
      if (_status != 'offline') {
        _emitDriverOnline();
      }

      // 3. Resume location updates if driver is online
      if (_status == 'online' && _positionStreamSubscription == null) {
        _startLocationUpdates();
      } else if (_status == 'online' ||
          _status == 'pickup' ||
          _status == 'arrived' ||
          _status == 'driver_arrived' ||
          _status == 'at_stop' ||
          _status == 'in_progress') {
        // Stream object still exists but the OS suspended delivery while
        // asleep — kick a one-shot fix so _lastPositionUpdateTime refreshes
        // quickly instead of waiting for the next stream/timer tick.
        _refreshPositionAfterResume();
      }

      // Authoritative re-sync when a snapshot rideId exists (RideSession:
      // fetch + merge + room rejoin, no navigation). Missed socket events
      // during the background gap reconcile from server state.
      _resyncOnResume();
    } else if (state == AppLifecycleState.paused) {
      debugPrint('🔴 [DriverHomeScreen] App paused');
      // Optional: You could pause location updates here to save battery
      // But for a ride app, you probably want to keep them running
    }
  }

  /// Foreground-resume re-sync (no navigation). Refreshes the on-screen
  /// execution state only when the resynced ride is the one on screen, so
  /// stop-arrive/resume buttons reflect the reconciled position.
  Future<void> _resyncOnResume() async {
    final snapshotId = await ActiveRideStorage.getRideId();
    if (snapshotId == null || snapshotId.isEmpty || !mounted) return;
    final ride = await resyncActiveRide(
      api: _apiService,
      socket: _socketService,
    );
    if (ride == null || !mounted) return;
    if (_currentRideId == null || _currentRideId != snapshotId) return;
    final status = (ride['status'] ?? '').toString().toLowerCase();
    final merged = await _withTripBlobParity(Map<String, dynamic>.from(ride));
    setState(() {
      _rideData = merged;
      _status = _uiStatusForServerStatus(status);
    });
  }

  /// Listen for socket reconnection and re-emit driver online status
  void _setupConnectionListener() {
    _connectionSubscription = _socketService.connectionStatus.listen((
      isConnected,
    ) {
      if (isConnected) {
        debugPrint(
          '🔄 [DriverHomeScreen] Socket reconnected, re-setting up listeners',
        );
        // Re-setup socket listeners after reconnection
        _setupSocketListeners();

        if (_status != 'offline') {
          debugPrint('🔄 [DriverHomeScreen] Re-emitting driver status');
          _emitDriverOnline();
        }

        // Auto-sync ride status if we had a disconnection gap and have an active ride
        final gap = _socketService.disconnectionGap;
        if (gap != null && gap.inSeconds > 3 && _currentRideId != null) {
          debugPrint(
            '🔄 [DriverHomeScreen] Disconnection gap: ${gap.inSeconds}s — auto-syncing ride status',
          );
          _syncRideStatus();
        }
      }
    });
  }

  /// Sync ride status with backend after reconnection gap
  Future<void> _syncRideStatus() async {
    if (_currentRideId == null) {
      debugPrint('[DriverRestore] sync skipped (no currentRideId)');
      return;
    }

    try {
      debugPrint(
        '🔄 [DriverHomeScreen] Syncing ride status for ride: $_currentRideId',
      );
      final response = await _apiService.getRideDetails(_currentRideId!);

      if (response['success'] == true && response['data'] != null) {
        final rideData = response['data'];
        final ride = rideData['ride'] ?? rideData;
        final status = ride['status']?.toString() ?? '';

        debugPrint(
          '🔄 [DriverHomeScreen] Synced ride status: $status, current UI state: $_status',
        );

        if (!mounted) return;

        // Check for terminal states — ride may have ended while disconnected
        if (status == 'cancelled' ||
            status == 'cancelled_by_user' ||
            status == 'cancelled_by_driver' ||
            status == 'expired') {
          setState(() {
            _status = 'online';
            _currentRideId = null;
            _rideData = null;
          });
          _clearActiveRideStorage();
          _promoteParkedRequests();
          debugPrint(
            '⚠️ [DriverHomeScreen] Ride ended while disconnected ($status), returning to online',
          );
        } else if (status == 'completed') {
          setState(() {
            _status = 'online';
            _currentRideId = null;
            _rideData = null;
          });
          _clearActiveRideStorage();
          _promoteParkedRequests();
          debugPrint(
            '✅ [DriverHomeScreen] Ride completed while disconnected, returning to online',
          );
        }
        // For active states (accepted, in_progress, etc.), the UI should already
        // reflect the correct state. Just update ride data to sync any changes.
        else if (ride != null) {
          // Stuck-shape repair: online WITH a ride id means the cold-start
          // profile adopt mapped an unknown shape (bare id / unmapped
          // status) — the server status is authoritative, adopt it so the
          // driver lands on the execution screen instead of a dead home.
          // An optimistic restore also always yields to the server on first
          // contact. Never touches settled execution states (a fresh local
          // transition always beats a racing sync) or queue browsing
          // (status == request).
          final stuckOnHome = _status == 'online' && _currentRideId != null;
          final wasOptimistic = _rideData?['optimistic'] == true;
          final repaired = (stuckOnHome || wasOptimistic)
              ? _uiStatusForServerStatus(status.toLowerCase())
              : _status;
          debugPrint(
            '[DriverRestore] sync ok server=$status stuckOnHome=$stuckOnHome wasOptimistic=$wasOptimistic repaired=$repaired',
          );
          setState(() {
            _rideData = ride is Map<String, dynamic> ? ride : null;
            _status = repaired;
          });
        }
      } else {
        debugPrint(
          '[DriverRestore] sync !success success=${response['success']} hasData=${response['data'] != null} rideId=$_currentRideId statusUnchanged=$_status',
        );
      }
    } catch (e) {
      debugPrint('⚠️ [DriverHomeScreen] Error syncing ride status: $e');
      debugPrint('[DriverRestore] sync fetch FAILED e=$e rideId=$_currentRideId statusUnchanged=$_status');
    }
  }

  Future<void> _initLocation() async {
    debugPrint('📍 [DriverHomeScreen] _initLocation() starting...');
    _fetchRideHistory(); // Background process

    // 1. Try to get last known location immediately for instant map update
    try {
      final lastKnown = await _locationService.getLastKnownLocation();
      if (lastKnown != null && mounted) {
        debugPrint("📍 [DriverHomeScreen] Instant last-known location: ${lastKnown.latitude}, ${lastKnown.longitude}");
        setState(() {
          _currentLocation = LatLng(lastKnown.latitude, lastKnown.longitude);
        });
      }
    } catch (e) {
      debugPrint('📍 [DriverHomeScreen] Error fetching last known location: $e');
    }

    // 2. Continue with getting fresh current location in background
    debugPrint("📍 [DriverHomeScreen] Requesting fresh location fix...");
    try {
      final position = await _locationService.getCurrentLocation();
      
      if (position != null && mounted) {
        debugPrint("📍 [DriverHomeScreen] Fresh location received: ${position.latitude}, ${position.longitude}");
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
        
        // Start updates if already online or needed
        if (_status == 'online') {
          _emitLocationUpdate(position.latitude, position.longitude);
        }
      } else {
        debugPrint('📍 [DriverHomeScreen] Fresh location was null or widget not mounted');
      }
    } catch (e) {
      debugPrint('📍 [DriverHomeScreen] Exception while getting fresh location: $e');
    }
    debugPrint('📍 [DriverHomeScreen] _initLocation() finished');
  }

  Future<void> _initDriver() async {
    debugPrint('🚖 [DriverHomeScreen] _initDriver() starting...');
    await _ensureUserLoaded();
    debugPrint('🚖 [DriverHomeScreen] User ensure loaded check complete');
    
    if (mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.user;
      
      if (user != null) {
        debugPrint('🚖 [DriverHomeScreen] Driver profile found: ${user['name']}');
        // DEBUG-RESTORE (keep): cold-start snapshot probe BEFORE the profile
        // adopt below can overwrite it. Paste these lines on a kill-restore miss.
        final snapId = await ActiveRideStorage.getRideId();
        final snapRole = await ActiveRideStorage.getRole();
        final snapStatus = await ActiveRideStorage.getStatus();
        final snapStale = await ActiveRideStorage.isStale();
        final snapBlob = await ActiveRideStorage.getTripState();
        debugPrint(
          '[DriverRestore] snapshot id=$snapId role=$snapRole status=$snapStatus stale=$snapStale stops=${(snapBlob['stops'] as List).length} stopIndex=${snapBlob['currentStopIndex']}',
        );
        // Sync online status from database
        final bool isOnline = user['isOnline'] == true || user['status'] == 'online';

        // Check for active ride in user object
        final currentRide = user['currentRide'];
        debugPrint(
          '[DriverRestore] profile currentRide type=${currentRide.runtimeType} status=${currentRide is Map ? (currentRide as Map)['status'] : currentRide}',
        );
        
        setState(() {
          if (currentRide != null) {
            // Restore active ride state
            _rideData = currentRide is Map ? Map<String, dynamic>.from(currentRide as Map) : null;
            _currentRideId = _rideData?['_id']?.toString() ?? currentRide.toString();
            
            final rideStatus = _rideData?['status']?.toString().toLowerCase();
            debugPrint('🚖 [DriverHomeScreen] Active ride detected: $_currentRideId with status: $rideStatus');
            
            if (rideStatus == 'accepted') {
              _status = 'pickup';
            } else if (rideStatus == 'arrived' ||
                rideStatus == 'driver_arrived') {
              _status = 'arrived';
            } else if (rideStatus == 'in_progress') {
              _status = 'in_progress';
            } else if (rideStatus == 'at_stop') {
              _status = 'at_stop';
            } else {
              _status = 'online';
            }
          } else if (isOnline) {
            _status = 'online';
            debugPrint('🟢 [DriverHomeScreen] Driver is online in profile');
          } else {
            debugPrint('⚪ [DriverHomeScreen] Driver is offline in profile');
          }
        });

        // Trigger sync if we found an active ride
        if (_currentRideId != null) {
          debugPrint('🚖 [DriverHomeScreen] Syncing active ride data from backend...');
          debugPrint(
            '[DriverRestore] branch=profile-adopt id=$_currentRideId status=$_status (storage restore will be SKIPPED)',
          );
          // Snapshot never lags the profile: a kill before the next
          // transition still restores from storage.
          _persistActiveRide();
          _syncRideStatus();
          _fetchNavigationRoute();
        } else {
          debugPrint(
            '[DriverRestore] branch=storage (no profile currentRide — storage restore will run)',
          );
        }
      } else {
        debugPrint('⚠️ [DriverHomeScreen] User is still null after _ensureUserLoaded()');
      }
      
      debugPrint('🚖 [DriverHomeScreen] Initializing Socket and listeners...');
      await _initSocketAndListeners();

      // If online, fetch scheduled pool
      if (_status == 'online') {
        _fetchScheduledPool();
      }

      // Restore an active ride from local storage (accept -> kill app -> reopen).
      await _restoreActiveRideFromStorage();

      // H1 FIX: If an active ride was restored (e.g. a prebook ride that started
      // while the app was backgrounded/terminated), the normal 'online' entry
      // point never ran, so location streaming was never started. Without it the
      // driver map stays static and the passenger never receives
      // driver:locationUpdate (passenger appears "stuck on one screen").
      if (_currentRideId != null &&
          (_status == 'pickup' ||
              _status == 'arrived' ||
              _status == 'driver_arrived' ||
              _status == 'at_stop' ||
              _status == 'in_progress')) {
        debugPrint(
          '📍 [DriverHomeScreen] Restored active ride — starting location updates',
        );
        _startLocationUpdates();
      }
    }
    debugPrint('🚖 [DriverHomeScreen] _initDriver() finished');
  }

  Future<void> _ensureUserLoaded() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user == null) {
      debugPrint('⚠️ [DriverHomeScreen] User is null, fetching profile...');
      await authProvider.fetchDriverProfile();
    }
  }

  Future<void> _initSocketAndListeners() async {
    await _socketService.initSocket();
    if (mounted) {
      _setupSocketListeners();
      _setupNavigationListener();
      // If already online, emit goOnline
      if (_status == 'online') {
        _emitDriverOnline();
        _startLocationUpdates();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Clean up socket listeners
    _socketService.off('ride:newRequest');
    _socketService.off('ride:reminder');
    _socketService.off('ride:longRunning');
    _socketService.off('ride:expired');
    _socketService.off('ride:cancelled');
    _socketService.off('ride:cancelledByUser');
    _socketService.off('ride:unavailable');
    _socketService.off('driver:status');
    _socketService.off('driver:locationUpdated');
    _socketService.off('payment:succeeded');
    _socketService.off('payment:authorized');
    _socketService.off('payment:captured');
    _socketService.off('payment:failed');
    _socketService.off('payment:cancelled');
    _socketService.off('ride:paymentSelected'); // Listener for payment choice
    _socketService.offExcessCashRequested();
    _socketService.offExcessCashCancelled();
    _socketService.offExcessCashConfirmed();
    _socketService.offNextTripActivated();

    // Stop and clean up notification playback if still playing
    AudioService.instance.stop();

    // Clean up streams
    _positionStreamSubscription?.cancel();
    _connectionSubscription?.cancel();
    _fcmSubscription?.cancel();
    _fcmForegroundSubscription?.cancel();

    // Clean up services
    _navigationService.dispose();
    _locationService.dispose();

    // Emit driver offline when disposing (if was online)
    if (_status != 'offline' && _driverId != null) {
      _socketService.emitDriverOffline(_driverId!);
    }

    debugPrint('🔴 [DriverHomeScreen] Disposed');
    super.dispose();
  }

  void _emitDriverOnline({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        _lastDriverOnlineEmitAt != null &&
        now.difference(_lastDriverOnlineEmitAt!) < _driverOnlineDebounce) {
      debugPrint(
        '⏭️ [DriverHomeScreen] Skipping duplicate driver:goOnline (debounced)',
      );
      return;
    }
    _lastDriverOnlineEmitAt = now;
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    debugPrint(
      '🔍 [DriverHomeScreen] User Object: $user',
    ); // Debug print to inspect user structure

    if (user != null) {
      // Try to find ID in common fields
      final driverId = user['_id'] ?? user['id'] ?? user['userId'];

      if (driverId != null) {
        debugPrint(
          '📤 [DriverHomeScreen] Emitting driver:goOnline for $driverId',
        );
        _socketService.emitDriverOnline(driverId);
      } else {
        debugPrint(
          '⚠️ [DriverHomeScreen] Cannot emit driver:goOnline: Driver ID not found in user object',
        );
      }
    } else {
      debugPrint(
        '⚠️ [DriverHomeScreen] Cannot emit driver:goOnline: User object is null',
      );
    }
  }

  void _onLocationStreamError(dynamic error) {
    _consecutiveLocationFailures++;
    debugPrint('⚠️ [DriverHomeScreen] Location stream error '
        '(consecutive failures: $_consecutiveLocationFailures): $error');
    // Silent: tracking resumes on the next fix. No UI.
  }

  /// Silent guard: best-effort freshest fix for completion. Never blocks,
  /// never prompts for permission, never shows UI — always falls back to
  /// _currentLocation on any failure.
  Future<LatLng> _bestEffortCompletionLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _currentLocation;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        return _currentLocation;
      }
      final fresh = await Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      final stamp = fresh?.timestamp;
      if (fresh != null && stamp != null) {
        final lastUpdate = _lastPositionUpdateTime;
        if (lastUpdate == null || stamp.isAfter(lastUpdate)) {
          debugPrint('📍 [DriverHomeScreen] Completion uses fresher '
              'last-known fix (${DateTime.now().difference(stamp).inSeconds}s old)');
          return LatLng(fresh.latitude, fresh.longitude);
        }
      }
    } catch (e) {
      debugPrint(
          '⚠️ [DriverHomeScreen] Completion location guard fallback: $e');
    }
    return _currentLocation;
  }

  /// One-shot position refresh after app resume. Updates the position clock
  /// on success; silently ignores transient failures.
  void _refreshPositionAfterResume() async {
    try {
      final position = await _locationService.getCurrentLocation();
      if (position != null && mounted) {
        _handlePositionUpdate(position);
      } else {
        _consecutiveLocationFailures++;
        debugPrint('⚠️ [DriverHomeScreen] Resume position refresh no fix '
            '(consecutive failures: $_consecutiveLocationFailures)');
      }
    } catch (e) {
      _consecutiveLocationFailures++;
      debugPrint('⚠️ [DriverHomeScreen] Resume position refresh failed '
          '(consecutive failures: $_consecutiveLocationFailures): $e');
    }
  }

  void _startLocationUpdates() async {
    _positionStreamSubscription?.cancel();

    // Get initial location
    final position = await _locationService.getCurrentLocation();
    if (position != null && mounted) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
      _emitLocationUpdate(position.latitude, position.longitude);
    } else {
      // No fix yet — stay silent, tracking resumes on the next fix.
      _consecutiveLocationFailures++;
      debugPrint(
        '⚠️ [DriverHomeScreen] Initial location fix unavailable — continuing silently '
        '(consecutive failures: $_consecutiveLocationFailures)',
      );
    }

    // Use ride tracking stream for active rides (more frequent updates)
    // or periodic stream for online status
    final bool isActiveRide = _status == 'in_progress' ||
        _status == 'pickup' ||
        _status == 'arrived' ||
        _status == 'driver_arrived' ||
        _status == 'at_stop';

    if (isActiveRide) {
      // Use high-frequency tracking for active rides (every 3 seconds, 5m distance filter)
      _positionStreamSubscription = _locationService
          .getRideTrackingStream(intervalSeconds: 3)
          .listen(_handlePositionUpdate, onError: _onLocationStreamError);

      debugPrint(
        '📍 [DriverHomeScreen] Started ride tracking stream (3s interval)',
      );
    } else {
      // Use periodic updates when just online (every 4 seconds)
      _positionStreamSubscription = _locationService
          .getPeriodicPositionStream(intervalSeconds: 4)
          .listen(_handlePositionUpdate, onError: _onLocationStreamError);

      debugPrint(
        '📍 [DriverHomeScreen] Started periodic location stream (4s interval)',
      );
    }
  }

  /// Handle incoming position updates
  void _handlePositionUpdate(Position position) {
    if (!mounted) return;

    _consecutiveLocationFailures = 0;

    // Calculate bearing if we have a previous location
    if (_currentLocation.latitude != 0 && _currentLocation.longitude != 0) {
      final bearing = Geolocator.bearingBetween(
        _currentLocation.latitude,
        _currentLocation.longitude,
        position.latitude,
        position.longitude,
      );
      // Only update bearing if moving significant distance or speed > 0
      if (position.speed > 0.5) {
        // moving at least 0.5 m/s
        _currentBearing = bearing;
      }
    }

    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
    });

    _lastPositionUpdateTime = DateTime.now();

    // Throttle location emissions to prevent overwhelming the server
    final now = DateTime.now();
    final shouldEmit =
        _lastEmitTime == null ||
        now.difference(_lastEmitTime!).inMilliseconds >= _minEmitIntervalMs;

    if (shouldEmit &&
        (_status == 'online' ||
            _status == 'in_progress' ||
            _status == 'pickup' ||
            _status == 'arrived')) {
      _emitLocationUpdate(position.latitude, position.longitude);
      _lastEmitTime = now;

      // Update navigation route in real-time
      if (_status == 'pickup' ||
          _status == 'in_progress' ||
          _status == 'arrived') {
        _updateNavigationRoute();
      }
    }
  }

  /// Setup navigation listener for route updates
  void _setupNavigationListener() {
    _navigationService.routeUpdates.listen((state) {
      if (!mounted) return;

      final bool isNavigationMode = _status == 'pickup' ||
          _status == 'arrived' ||
          _status == 'driver_arrived' ||
          _status == 'at_stop' ||
          _status == 'in_progress';

      // If the ride has ended (or driver is not navigating), ignore late route updates
      // and ensure the map is cleared.
      if (!isNavigationMode) {
        if (_navigationState != null || _navigationPolylines.isNotEmpty) {
          setState(() {
            _clearNavigationUi();
          });
        }
        return;
      }

      setState(() {
        _navigationState = state;
        _updateNavigationPolylines();
      });
    });
  }

  void _clearNavigationUi() {
    _navigationService.clearRoute();
    _navigationState = null;
    _navigationPolylines = [];
  }

  /// Persist the current active ride so it can be restored after an app restart.
  ///
  /// Also persists the trip blob from [_rideData] (stops, stop index, wait
  /// totals, fare, payment) so a kill mid-trip restores position + wait
  /// timer even when the server payload omits them. Single choke point —
  /// every transition (accept/arrive/start/stop-arrive/resume/cash) flows
  /// through here.
  Future<void> _persistActiveRide() async {
    if (_currentRideId == null) return;
    await ActiveRideStorage.save(
      rideId: _currentRideId!,
      role: 'driver',
      status: _status,
    );
    final ride = _rideData;
    if (ride == null) return;
    final stops = ride['stops'];
    int? stopIndex;
    final rawIndex = ride['currentStopIndex'];
    if (rawIndex is num) {
      stopIndex = rawIndex.toInt();
    } else if (rawIndex is String) {
      stopIndex = int.tryParse(rawIndex);
    }
    int? waitMinutes;
    final rawWaitMins = ride['totalWaitMinutes'];
    if (rawWaitMins is num) {
      waitMinutes = rawWaitMins.toInt();
    } else if (rawWaitMins is String) {
      waitMinutes = int.tryParse(rawWaitMins);
    }
    double? waitFee;
    final rawWaitFee = ride['totalWaitFee'];
    if (rawWaitFee is num) {
      waitFee = rawWaitFee.toDouble();
    } else if (rawWaitFee is String) {
      waitFee = double.tryParse(rawWaitFee);
    }
    double? fare;
    for (final key in ['actualFare', 'adjustedFare']) {
      final raw = ride[key];
      if (raw is num) {
        fare = raw.toDouble();
        break;
      } else if (raw is String) {
        final parsed = double.tryParse(raw);
        if (parsed != null) {
          fare = parsed;
          break;
        }
      }
    }
    await ActiveRideStorage.saveTripState(
      stops: stops is List && stops.isNotEmpty
          ? List<dynamic>.from(stops)
          : null,
      totalWaitMinutes: waitMinutes,
      totalWaitFee: waitFee,
      actualFare: fare,
      paymentMethod: ride['paymentMethod']?.toString(),
      paymentStatus: ride['paymentStatus']?.toString(),
      currentStopIndex: stopIndex,
    );
  }

  Future<void> _clearActiveRideStorage() async {
    await ActiveRideStorage.clear();
  }

  /// Restore an active ride from local storage (covers the case where the backend
  /// profile didn't carry currentRide, e.g. accept -> kill app -> reopen).
  ///
  /// Delegates to the global [RideSession] entry (authoritative server
  /// reconcile + room rejoin); only the UI mapping below is screen-local.
  /// The persisted trip blob is overlaid for keys the server payload lacks
  /// so stop-arrive/resume buttons reflect the pre-kill position.
  Future<void> _restoreActiveRideFromStorage() async {
    if (_currentRideId != null) {
      debugPrint(
        '[DriverRestore] storage restore SKIPPED (profile adopt holds id=$_currentRideId status=$_status)',
      );
      return; // already restored from profile
    }
    final role = await ActiveRideStorage.getRole();
    if (role != 'driver') {
      debugPrint('[DriverRestore] storage restore SKIPPED (role=$role)');
      return;
    }

    final outcome = await restoreActiveRide(
      api: _apiService,
      socket: _socketService,
    );
    if (outcome is RideNone) {
      debugPrint(
        '[DriverRestore] storage outcome=RideNone (fetch failed, snapshot kept) → trying optimistic',
      );
      // Authoritative fetch failed (offline / token race / cold TLS) but
      // the live snapshot was kept — restore optimistically from snapshot
      // + blob instead of stranding a mid-trip driver on home. Never fires
      // when the server said final (that returns Cleared, not RideNone).
      await _restoreOptimisticFromSnapshot();
      return;
    }
    if (outcome is Cleared) {
      debugPrint('[DriverRestore] storage outcome=Cleared reason=${outcome.reason}');
      return;
    }
    if (outcome is! Restored) return;
    final ride = outcome.ride;
    final status = (ride['status'] ?? '').toString().toLowerCase();
    debugPrint(
      '[DriverRestore] storage outcome=Restored serverStatus=$status route=${outcome.route}',
    );

    final storedId = await ActiveRideStorage.getRideId();
    final id =
        storedId ??
        ride['_id']?.toString() ??
        ride['id']?.toString() ??
        ride['rideId']?.toString();
    if (id == null || id.isEmpty) return;

    if (!mounted) return;
    final merged = await _withTripBlobParity(Map<String, dynamic>.from(ride));
    setState(() {
      _currentRideId = id;
      _rideData = merged;
      _status = _uiStatusForServerStatus(status);
    });
    _fetchNavigationRoute();
  }

  /// Optimistic cold-start restore when the authoritative fetch failed but
  /// a live snapshot survived (offline / token race / cold TLS on reopen).
  /// Rebuilds the execution screen from snapshot + trip blob, then
  /// reconciles in the background via [_syncRideStatus] — server values win
  /// as soon as the network answers. Only fires for pre-completion
  /// execution states; anything else (online, cash-confirm, unknown) stays
  /// home, matching prior behavior.
  Future<void> _restoreOptimisticFromSnapshot() async {
    if (_currentRideId != null || !mounted) return;
    final storedId = await ActiveRideStorage.getRideId();
    final snapStatus = await ActiveRideStorage.getStatus();
    if (storedId == null || storedId.isEmpty || snapStatus == null) {
      debugPrint(
        '[DriverRestore] optimistic SKIPPED (id=$storedId status=$snapStatus)',
      );
      return;
    }
    final canonical = snapshotStatusForDriver(snapStatus);
    const liveExecution = {
      'accepted',
      'driver_arrived',
      'arrived',
      'in_progress',
      'at_stop',
    };
    if (!liveExecution.contains(canonical)) {
      debugPrint(
        '[DriverRestore] optimistic SKIPPED (snapshot status=$snapStatus canonical=$canonical not live-execution)',
      );
      return;
    }
    final blob = await ActiveRideStorage.getTripState();
    final ride = syntheticRideFromSnapshot(
      rideId: storedId,
      snapshotStatus: snapStatus,
      blob: blob,
    );
    if (ride == null || !mounted) return;
    debugPrint(
      '⚡ [DriverHomeScreen] Optimistic restore $storedId → $canonical (fetch failed, reconciling in background)',
    );
    setState(() {
      _currentRideId = storedId;
      _rideData = ride;
      _status = _uiStatusForServerStatus(canonical);
    });
    _fetchNavigationRoute();
    // Background reconcile: replaces the optimistic ride with server truth
    // (and repairs _status if the server disagrees) when reachable.
    _syncRideStatus();
  }

  /// Map a backend ride status onto this screen's execution states.
  String _uiStatusForServerStatus(String status) {
    switch (status) {
      case 'accepted':
        return 'pickup';
      case 'arrived':
      case 'driver_arrived':
        return 'arrived';
      case 'in_progress':
        return 'in_progress';
      case 'at_stop':
        return 'at_stop';
      default:
        return 'pickup';
    }
  }

  /// Overlay the persisted trip blob onto [ride] for keys the server payload
  /// lacks, so stop-arrive/resume buttons reflect the pre-kill position.
  /// Server values always win when present.
  Future<Map<String, dynamic>> _withTripBlobParity(
    Map<String, dynamic> ride,
  ) async {
    final blob = await ActiveRideStorage.getTripState();
    final merged = Map<String, dynamic>.from(ride);
    final storedStops = blob['stops'];
    final rideStops = merged['stops'];
    if ((rideStops is! List || rideStops.isEmpty) &&
        storedStops is List &&
        storedStops.isNotEmpty) {
      merged['stops'] = storedStops;
    }
    if (merged['currentStopIndex'] == null) {
      merged['currentStopIndex'] = blob['currentStopIndex'];
    }
    if (merged['totalWaitMinutes'] == null) {
      merged['totalWaitMinutes'] = blob['totalWaitMinutes'];
    }
    if (merged['totalWaitFee'] == null) {
      merged['totalWaitFee'] = blob['totalWaitFee'];
    }
    if (merged['actualFare'] == null &&
        (blob['actualFare'] as num? ?? 0) != 0) {
      merged['actualFare'] = blob['actualFare'];
    }
    if (merged['paymentMethod'] == null && blob['paymentMethod'] != null) {
      merged['paymentMethod'] = blob['paymentMethod'];
    }
    if (merged['paymentStatus'] == null && blob['paymentStatus'] != null) {
      merged['paymentStatus'] = blob['paymentStatus'];
    }
    return merged;
  }

  /// Fetch navigation route based on current status
  Future<void> _fetchNavigationRoute() async {
    if (_rideData == null) return;

    LatLng destination;

    if (_status == 'pickup' || _status == 'arrived') {
      // Navigate to pickup
      final coords = _rideData!['pickupLocation']?['coordinates'] ?? [0.0, 0.0];
      destination = LatLng(coords[1], coords[0]);
    } else if (_status == 'in_progress' || _status == 'at_stop') {
      // Navigate to dropoff
      final coords =
          _rideData!['dropoffLocation']?['coordinates'] ?? [0.0, 0.0];
      destination = LatLng(coords[1], coords[0]);
    } else {
      return;
    }

    await _navigationService.fetchRoute(
      originLat: _currentLocation.latitude,
      originLng: _currentLocation.longitude,
      destLat: destination.latitude,
      destLng: destination.longitude,
      // Trip leg traces through stops; pickup leg has no waypoints.
      stops: (_status == 'in_progress' || _status == 'at_stop')
          ? parseRideStops(_rideData?['stops'])
          : null,
    );
  }

  /// Update navigation route in real-time
  Future<void> _updateNavigationRoute() async {
    if (_rideData == null) return;

    LatLng destination;

    if (_status == 'pickup' || _status == 'arrived') {
      final coords = _rideData!['pickupLocation']?['coordinates'] ?? [0.0, 0.0];
      destination = LatLng(coords[1], coords[0]);
    } else if (_status == 'in_progress' || _status == 'at_stop') {
      final coords =
          _rideData!['dropoffLocation']?['coordinates'] ?? [0.0, 0.0];
      destination = LatLng(coords[1], coords[0]);
    } else {
      return;
    }

    await _navigationService.updateRoute(
      currentLat: _currentLocation.latitude,
      currentLng: _currentLocation.longitude,
      destLat: destination.latitude,
      destLng: destination.longitude,
      stops: (_status == 'in_progress' || _status == 'at_stop')
          ? parseRideStops(_rideData?['stops'])
          : null,
    );
  }

  /// Update polylines with navigation route (cased, Uber-style)
  void _updateNavigationPolylines() {
    if (_navigationState != null && _navigationState!.polyline.isNotEmpty) {
      _navigationPolylines = RouteMapHelpers.routePolylines(
        _navigationState!.polyline,
        color: AppTheme.primaryColor,
      );
    } else {
      _navigationPolylines = [];
    }
  }

  /// Open external navigation to the current target, chaining remaining
  /// stops as Google Maps waypoints during the trip (Uber-style).
  Future<void> _openExternalNavigation() async {
    double? lat;
    double? lng;
    if (_proximityTarget.startsWith('stop') && _rideData != null) {
      final stops = parseRideStops(_rideData!['stops']);
      final idx = _rideData!['currentStopIndex'] is int
          ? _rideData!['currentStopIndex'] as int
          : 0;
      final current = idx >= 0 && idx < stops.length ? stops[idx] : null;
      if (current?.coordinates != null) {
        lng = current!.coordinates![0];
        lat = current.coordinates![1];
      }
    } else {
      final coords = _rideData?['pickupLocation']?['coordinates'];
      if (coords is List && coords.length >= 2) {
        lng = (coords[0] as num).toDouble();
        lat = (coords[1] as num).toDouble();
      }
    }
    if (lat == null || lng == null) return;
    // During the trip, append remaining stops + final dropoff as waypoints
    // so Google Maps routes through every stop.
    String waypointsParam = '';
    if ((_status == 'in_progress' || _status == 'at_stop') &&
        _rideData != null) {
      final stops = parseRideStops(_rideData!['stops']);
      final remaining = <String>[];
      for (final s in stops) {
        final c = s.coordinates;
        if (c == null || c.length < 2) continue;
        if (s.isCompleted) continue;
        remaining.add('${c[1]},${c[0]}');
      }
      final dCoords = _rideData!['dropoffLocation']?['coordinates'];
      if (dCoords is List && dCoords.length >= 2) {
        remaining.add(
          '${(dCoords[1] as num).toDouble()},${(dCoords[0] as num).toDouble()}',
        );
      }
      if (remaining.isNotEmpty) {
        waypointsParam =
            '&waypoints=${Uri.encodeComponent(remaining.join('|'))}';
      }
    }
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng$waypointsParam',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Persistent proximity banner — stays until arrival succeeds.
  /// Never a dismiss-only toast: always offers Retry + Open navigation.
  Widget _buildProximityBanner() {
    final distance = _proximityDistance ?? 0;
    final required = _proximityRequired ?? 100;
    final target = _proximityTarget.startsWith('stop')
        ? _proximityTarget
        : 'pickup point';
    // Proximity banner sits at the top (no GPS banner exists anymore).
    const topOffset = 0.0;
    return Positioned(
      top: topOffset,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.orange[800],
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.nearby_error,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "You're ${distance}m away — within ${required}m to confirm",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  'Drive closer to the $target, then retry arrival.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _handleRideAction,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _openExternalNavigation,
                      icon: const Icon(Icons.navigation, size: 16),
                      label: const Text('Open navigation'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.orange[800],
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Free-wait chip label after arrival. Null unless the backend actually
  /// sent a per-ride policy — never show invented defaults.
  String? get _freeWaitLabel {
    if (_status != 'arrived' &&
        _status != 'driver_arrived' &&
        _status != 'at_stop') {
      return null;
    }
    final mins = _freeWaitMinutes;
    final rate = _freeWaitRate;
    if (mins == null || rate == null) return null;
    return '$mins min free · £${rate.toStringAsFixed(2)}/min after';
  }

  /// Harvest per-ride wait policy from a backend payload (arrive /
  /// stop-arrive / ride snapshots carry `freeMinutes` + `perMinuteRate`).
  /// Missing keys stay null so no wait UI is shown — no silent defaults.
  void _harvestWaitPolicy(Map<String, dynamic> data) {
    final fm = data['freeMinutes'];
    _freeWaitMinutes = fm is num
        ? fm.toInt()
        : int.tryParse(fm?.toString() ?? '');
    final rate = data['perMinuteRate'];
    _freeWaitRate = rate is num
        ? rate.toDouble()
        : double.tryParse(rate?.toString() ?? '');
  }

  void _emitLocationUpdate(double lat, double lng) {    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user != null) {
      final driverId = user['_id'] ?? user['id'] ?? user['userId'];

      if (driverId != null) {
        // Use the enhanced socket service method
        _socketService.emitDriverLocationUpdate(
          driverId: driverId,
          latitude: lat,
          longitude: lng,
        );
      }
    }
  }

  void _setupSocketListeners() {
    debugPrint('👂 [DriverHomeScreen] Setting up socket listeners...');

    // Clean up existing listeners before re-registering to prevent duplicates
    if (_socketListenersSetup) {
      debugPrint(
        '🧹 [DriverHomeScreen] Cleaning up old socket listeners before re-setup...',
      );
      _socketService.off('ride:newRequest');
      _socketService.off('ride:reminder');
      _socketService.off('ride:longRunning');
      _socketService.off('ride:expired');
      _socketService.off('ride:cancelled');
      _socketService.off('ride:cancelledByUser');
      _socketService.off('ride:unavailable');
      _socketService.off('driver:status');
      _socketService.off('driver:locationUpdated');
      _socketService.off('payment:succeeded');
      _socketService.off('payment:authorized');
      _socketService.off('payment:captured');
      _socketService.off('payment:failed');
      _socketService.off('payment:cancelled');
      _socketService.off('ride:paymentSelected');
      _socketService.offExcessCashRequested();
      _socketService.offExcessCashCancelled();
      _socketService.offExcessCashConfirmed();
    }

    _socketListenersSetup = true;

    // Listen for driver status confirmation
    _socketService.on('driver:status', (data) {
      debugPrint('📩 [DriverHomeScreen] Driver status: $data');
      if (mounted && data['status'] == 'online') {
        // Successfully went online
      }
    });

    // Listen for payment selected by user
    _socketService.on('ride:paymentSelected', (data) {
      debugPrint('💳 [DriverHomeScreen] User selected payment: $data');
      if (mounted && _currentRideId == (data['bookingId'] ?? data['rideId'])) {
        setState(() {
          // Update local ride data with selected method
          if (_rideData != null) {
            _rideData!['paymentMethod'] = data['paymentMethod'];
          }
        });
        CustomSnackbar.show(
          context,
          message: 'User is paying...',
          type: SnackbarType.info,
        );
      }
    });

    // Listen for payment success to finalize ride completion
    _socketService.on('payment:succeeded', (data) {
      debugPrint('💳 [DriverHomeScreen] Payment succeeded: $data');
      if (!mounted) return;

      final rideId =
          data['bookingId']?.toString() ?? data['rideId']?.toString();
      if (rideId == _currentRideId) {
        // Settled elsewhere (e.g. rider paid online): drop an open
        // cash modal silently, then run the existing reset below.
        _closeExcessCashDialogIfOpen();
        CustomSnackbar.show(
          context,
          message: 'Payment completed! Ride finalized.',
          type: SnackbarType.success,
        );

        // Reset to online and refetch ride history
        setState(() {
          _status = 'online';
          _currentRideId = null;
          _rideData = null;
          _clearNavigationUi();
          _clearActiveRideStorage();
        });
        _promoteParkedRequests();
        _fetchRideHistory();
      }
      // Stop notification playback if payment succeeded
      AudioService.instance.stop();
    });

    _socketService.on('payment:authorized', (data) {
      debugPrint('💳 [DriverHomeScreen] Payment authorized: $data');
      if (!mounted) return;

      final rideId =
          data['bookingId']?.toString() ?? data['rideId']?.toString();
      if (rideId == _currentRideId) {
        CustomSnackbar.show(
          context,
          message: 'Payment authorized by rider.',
          type: SnackbarType.info,
        );
      }
    });

    _socketService.on('payment:captured', (data) {
      debugPrint('💳 [DriverHomeScreen] Payment captured: $data');
      if (!mounted) return;

      final rideId =
          data['bookingId']?.toString() ?? data['rideId']?.toString();
      if (rideId == _currentRideId) {
        CustomSnackbar.show(
          context,
          message: 'Payment captured successfully.',
          type: SnackbarType.success,
        );
      }
    });

    _socketService.on('payment:failed', (data) {
      debugPrint('💳 [DriverHomeScreen] Payment failed: $data');
      if (!mounted) return;

      final rideId =
          data['bookingId']?.toString() ?? data['rideId']?.toString();
      if (rideId == _currentRideId) {
        CustomSnackbar.show(
          context,
          message: data['message']?.toString() ?? 'Rider payment failed.',
          type: SnackbarType.error,
        );
      }
    });

    _socketService.on('payment:cancelled', (data) {
      debugPrint('💳 [DriverHomeScreen] Payment cancelled: $data');
      if (!mounted) return;

      final rideId =
          data['bookingId']?.toString() ?? data['rideId']?.toString();
      if (rideId == _currentRideId) {
        CustomSnackbar.show(
          context,
          message: data['message']?.toString() ?? 'Rider cancelled payment.',
          type: SnackbarType.warning,
        );
      }
    });

    // Stage 2 excess-cash request: rider chose cash for the excess balance.
    // Raises the Collect-Cash modal once per event (dedupe-guarded). Not
    // gated on _currentRideId — see _handleExcessCashRequest.
    _socketService.onExcessCashRequested((data) {
      debugPrint('💰 [DriverHomeScreen] Excess cash requested: $data');
      if (!mounted) return;
      final map = data is Map<String, dynamic>
          ? data
          : data is Map
              ? Map<String, dynamic>.from(data as Map)
              : <String, dynamic>{};
      // Socket path rings: the FCM service only rings when IT wins the race.
      _handleExcessCashRequest(map, checkDedupe: true, ring: true);
    });

    // Stage 2 excess-cash cancelled: rider switched back to online while
    // in the car. Silently close an open cash modal — no toast, no error.
    _socketService.onExcessCashCancelled((data) {
      debugPrint('💰 [DriverHomeScreen] Excess cash cancelled: $data');
      if (!mounted) return;
      final map = data is Map<String, dynamic>
          ? data
          : data is Map
              ? Map<String, dynamic>.from(data as Map)
              : <String, dynamic>{};
      if (!RideEventDedupe.shouldHandleEvent(
        source: 'socket',
        type: 'payment_excess_cash_cancelled',
        data: map,
      )) {
        return;
      }
      final rideId = _socketRideId(map);
      if (rideId != null &&
          _currentRideId != null &&
          rideId != _currentRideId) {
        return;
      }
      _closeExcessCashDialogIfOpen();
    });

    // Phase 14 CONFIRM-03/04: driver confirmed cash receipt — close the
    // Collect-Cash modal (if open) then toast exactly once. No
    // _currentRideId gate: the event rideId is authoritative (no-modal
    // fix) — ignore only when both ids are non-null and differ, mirroring
    // the cancelled handler above. No AudioService ring (request already
    // rang); payment:succeeded flow untouched.
    _socketService.onExcessCashConfirmed((data) {
      debugPrint('💰 [DriverHomeScreen] Excess cash confirmed: $data');
      if (!mounted) return;
      final map = data is Map<String, dynamic>
          ? data
          : data is Map
              ? Map<String, dynamic>.from(data as Map)
              : <String, dynamic>{};
      if (!RideEventDedupe.shouldHandleEvent(
        source: 'socket',
        type: 'payment_excess_cash_confirmed',
        data: map,
      )) {
        return;
      }
      final rideId = _socketRideId(map);
      if (rideId != null &&
          _currentRideId != null &&
          rideId != _currentRideId) {
        return;
      }
      _closeExcessCashDialogIfOpen();
      // Toast-once guard keyed by rideId (not modal-open): the modal may
      // already be closed by a co-fired payment:succeeded, yet the toast
      // must still fire exactly once.
      final toastKey = rideId ?? '__unknown__';
      if (_excessCashConfirmedToastRideIds.contains(toastKey)) return;
      _excessCashConfirmedToastRideIds.add(toastKey);
      CustomSnackbar.show(
        context,
        message: 'Cash excess payment confirmed!',
        type: SnackbarType.success,
      );
    });

    // Listen for location update confirmation
    _socketService.on('driver:locationUpdated', (data) {
      // Location update confirmed by server
    });

    _socketService.on('ride:newRequest', (data) {
      debugPrint('🔔 [DriverHomeScreen] New Ride Request Received: $data');
      if (mounted) {
        // FCM delivers the same request — shared guard keeps one dialog.
        if (!RideEventDedupe.shouldHandleEvent(
          source: 'socket',
          type: 'ride_request',
          data: data,
        )) {
          return;
        }
        debugPrint('🔔 [DriverHomeScreen] Triggering _handleNewRideRequest');
        _handleNewRideRequest(data);
      } else {
        debugPrint(
          '🔔 [DriverHomeScreen] Received request but widget not mounted',
        );
      }
    });

    _socketService.on('ride:scheduledCancelledByUser', (data) {
      debugPrint('❌ [DriverHomeScreen] Scheduled Ride Cancelled By User: $data');
      if (mounted) {
        final rideId = data['rideId']?.toString();
        if (_currentRideId == rideId) {
          setState(() {
            _status = 'online';
            _currentRideId = null;
            _rideData = null;
            // Scheduled trip cancelled — B2B state dies with it.
            _b2bOffer = null;
            _b2bOfferError = null;
            _queuedTrip = null;
            _queuedPromotionPending = false;
          });
          _promoteParkedRequests();
        }
        CustomSnackbar.show(
          context,
          message: data['message'] ?? 'A scheduled ride was cancelled by user',
          type: SnackbarType.info,
        );
      }
    });

    _socketService.on('ride:reminder', (data) {
      debugPrint('⏰ [DriverHomeScreen] Ride Reminder: $data');
      if (mounted) {
        // Prebook reminders ring — first transport (socket or FCM) wins via
        // the shared canonical key, so no double ringtone.
        final reminderType =
            data is Map ? data['reminderType']?.toString().toLowerCase() : null;
        final key = (reminderType?.contains('final') ?? false)
            ? 'reminder_final'
            : 'reminder_first';
        if (RideEventDedupe.shouldHandle(
          source: 'socket',
          type: key,
          rideId: data is Map
              ? (data['rideId'] ?? data['_id'])?.toString()
              : null,
        )) {
          AudioService.instance.playNotification();
        }
        CustomSnackbar.show(
          context,
          message: data['message'] ?? 'Reminder: You have an upcoming ride!',
          type: SnackbarType.warning,
        );
      }
    });

    _socketService.on('ride:longRunning', (data) {
      debugPrint('⏳ [DriverHomeScreen] Ride Long Running: $data');
      if (mounted) {
        CustomSnackbar.show(
          context,
          message: 'Ride is taking longer than expected...',
          type: SnackbarType.warning,
        );
      }
    });

    _socketService.on('ride:cancelled', (data) {
      debugPrint('❌ [DriverHomeScreen] Ride Cancelled: $data');
      if (mounted) {
        final cancelledId = _socketRideId(data);
        // B2B: queued trip cancelled by the rider — clear the pill only,
        // Trip A keeps running (20-02).
        if (cancelledId != null &&
            _queuedTrip != null &&
            _canonicalRideId(_queuedTrip!) == cancelledId) {
          setState(() => _queuedTrip = null);
          debugPrint(
            '🔄 [DriverHomeScreen][B2B] Queued trip $cancelledId cancelled by rider (socket)',
          );
          CustomSnackbar.show(
            context,
            message: 'Your queued ride was cancelled by the passenger.',
            type: SnackbarType.info,
          );
          return;
        }
        // B2B: pending offer evaporated — clear the card, Trip A untouched.
        if (cancelledId != null &&
            _b2bOffer != null &&
            _canonicalRideId(_b2bOffer!) == cancelledId) {
          setState(() {
            _b2bOffer = null;
            _b2bOfferError = null;
          });
          debugPrint(
            '🔄 [DriverHomeScreen][B2B] Pending offer $cancelledId evaporated (socket)',
          );
          AudioService.instance.stop();
          CustomSnackbar.show(
            context,
            message: 'The back-to-back offer is no longer available.',
            type: SnackbarType.info,
          );
          return;
        }
        // Stacked request cancelled — evict just that card.
        if (_status == 'request') {
          final rideId = _socketRideId(data);
          if (rideId != null) {
            _removeQueuedRequest(
              rideId,
              goneMessage: 'A ride request was cancelled.',
            );
            return;
          }
        }
        final reason = data['reason'] ?? 'User cancelled the ride';
        setState(() {
          _status = 'online';
          _currentRideId = null;
          _rideData = null;
          // Active trip externally cancelled — B2B state dies with it.
          _b2bOffer = null;
          _b2bOfferError = null;
          _queuedTrip = null;
          _queuedPromotionPending = false;
          _clearNavigationUi();
          _clearActiveRideStorage();
        });
        _promoteParkedRequests();

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Ride Cancelled'),
            content: Text('The ride was cancelled.\nReason: $reason'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });

    // User cancelled the ride (before start)
    _socketService.on('ride:cancelledByUser', (data) {
      debugPrint('❌ [DriverHomeScreen] Ride Cancelled By User: $data');
      if (mounted) {
        // Stacked request cancelled — evict just that card.
        if (_status == 'request') {
          final rideId = _socketRideId(data);
          if (rideId != null) {
            final feeRaw = data is Map ? data['cancellationFee'] : null;
            final fee = feeRaw is num
                ? feeRaw.toDouble()
                : double.tryParse(feeRaw?.toString() ?? '') ?? 0.0;
            final message = fee > 0
                ? 'User cancelled the ride.\nYou received £${fee.toStringAsFixed(2)} compensation.'
                : 'User cancelled the ride.';
            _removeQueuedRequest(rideId, goneMessage: message);
            return;
          }
        }
        AudioService.instance.stop();
        final cancellationFee = data['cancellationFee'] ?? 0.0;
        setState(() {
          _status = 'online';
          _currentRideId = null;
          _rideData = null;
          // Active trip externally cancelled — B2B state dies with it.
          _b2bOffer = null;
          _b2bOfferError = null;
          _queuedTrip = null;
          _queuedPromotionPending = false;
          _clearNavigationUi();
          _clearActiveRideStorage();
        });
        _promoteParkedRequests();

        final message = cancellationFee > 0
            ? 'User cancelled the ride.\nYou received £${cancellationFee.toStringAsFixed(2)} compensation.'
            : 'User cancelled the ride.';

        CustomSnackbar.show(context, message: message, type: SnackbarType.info);
      }
    });

    _socketService.on('ride:expired', (data) {
      debugPrint('⏰ [DriverHomeScreen] Ride Expired: $data');
      if (mounted) {
        // B2B offer expired — clear the card, Trip A untouched.
        final expiredId = _socketRideId(data);
        if (expiredId != null &&
            _b2bOffer != null &&
            _canonicalRideId(_b2bOffer!) == expiredId) {
          setState(() {
            _b2bOffer = null;
            _b2bOfferError = null;
          });
          AudioService.instance.stop();
          return;
        }
        // Stacked request expired — evict just that card.
        if (_status == 'request') {
          final rideId = _socketRideId(data);
          if (rideId != null) {
            _removeQueuedRequest(
              rideId,
              goneMessage: 'Ride request expired.',
            );
            return;
          }
        }
        AudioService.instance.stop();
        setState(() {
          _status = 'online';
          _currentRideId = null;
          _rideData = null;
          // Active trip expired — B2B state dies with it.
          _b2bOffer = null;
          _b2bOfferError = null;
          _queuedTrip = null;
          _queuedPromotionPending = false;
          _clearNavigationUi();
          _clearActiveRideStorage();
        });
        _promoteParkedRequests();
        CustomSnackbar.show(
          context,
          message: 'Ride request expired.',
          type: SnackbarType.info,
        );
      }
    });

    // Another driver took the ride — evict just that card. Toast only when
    // something was actually removed; audio stops only if the queue drained.
    // B2B offers share the eviction: a taken offer clears the card silently.
    _socketService.on('ride:unavailable', (data) {
      debugPrint('🚫 [DriverHomeScreen] Ride Unavailable: $data');
      if (!mounted) return;
      final unavailableId = _socketRideId(data);
      if (unavailableId != null &&
          _b2bOffer != null &&
          _canonicalRideId(_b2bOffer!) == unavailableId) {
        setState(() {
          _b2bOffer = null;
          _b2bOfferError = null;
        });
        AudioService.instance.stop();
        return;
      }
      if (_status == 'request') {
        final rideId = _socketRideId(data);
        if (rideId != null) {
          _removeQueuedRequest(
            rideId,
            goneMessage: 'This ride was taken by another driver',
          );
        }
      }
    });

    // Back-to-back promotion trigger (§3.1): Trip A completed and Trip B
    // becomes active. First trigger wins — the completeRide response path
    // and this event race; the guard inside _promoteQueuedTrip no-ops the
    // second. Scoped listener, off in dispose.
    _nextTripListener = (data) {
      debugPrint('🔄 [DriverHomeScreen][B2B] Next trip activated: $data');
      if (!mounted) return;
      final map = data is Map<String, dynamic>
          ? data
          : data is Map
              ? Map<String, dynamic>.from(data)
              : <String, dynamic>{};
      // Validate through the 20-01 parser (never throws); the raw payload
      // stays the display source of truth.
      NextTripActivation.fromMap(map);
      _promoteQueuedTrip(map);
    };
    _socketService.offNextTripActivated();
    _socketService.onNextTripActivated(_nextTripListener!);
  }

  double? _parseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Normalise flat FCM payload into nested structure expected by ride panels.
  Map<String, dynamic> _normaliseRideData(dynamic raw) {
    if (raw is! Map<String, dynamic>) return raw is Map ? Map<String, dynamic>.from(raw) : {};

    final m = Map<String, dynamic>.from(raw);

    // Normalise booleans (FCM sends everything as strings)
    if (m['isScheduled'] is String) m['isScheduled'] = m['isScheduled'] == 'true';
    if (m['isPriority'] is String) m['isPriority'] = m['isPriority'] == 'true';
    // B2B flag arrives as 'true' string on the FCM path (20-02).
    if (m['isBackToBack'] is String) {
      m['isBackToBack'] = m['isBackToBack'] == 'true';
    }

    // Normalise numeric fields that FCM sends as strings
    if (m['fare'] is String) m['fare'] = double.tryParse(m['fare']) ?? m['fare'];
    if (m['distance'] is String) m['distance'] = double.tryParse(m['distance']) ?? m['distance'];

    // Build nested pickupLocation from flat fields
    if (m['pickupLocation'] == null && (m['pickupAddress'] != null || m['pickupLat'] != null)) {
      final lat = _parseNum(m['pickupLat']);
      final lng = _parseNum(m['pickupLon']);
      m['pickupLocation'] = {
        'address': m['pickupAddress'],
        if (lat != null && lng != null)
          'coordinates': [lng, lat],
      };
    }

    // Build nested dropoffLocation from flat fields
    if (m['dropoffLocation'] == null && (m['dropoffAddress'] != null || m['dropoffLat'] != null)) {
      final lat = _parseNum(m['dropoffLat']);
      final lng = _parseNum(m['dropoffLon']);
      m['dropoffLocation'] = {
        'address': m['dropoffAddress'],
        if (lat != null && lng != null)
          'coordinates': [lng, lat],
      };
    }

    // Build nested user from flat userName
    if (m['user'] == null && m['userName'] != null) {
      m['user'] = {'name': m['userName']};
    }

    return m;
  }

  /// Fetch scheduled pool when driver is online
  Future<void> _fetchScheduledPool() async {
    if (_status != 'online' || !mounted) return;
    setState(() => _isPoolLoading = true);
    try {
      final response = await _apiService.getScheduledPool();
      if (mounted && response['success'] == true) {
        final data = response['data'];
        setState(() {
          _scheduledPool = data is List ? data : [];
        });
      }
    } catch (e) {
      debugPrint('🔴 [DriverHomeScreen] Error fetching scheduled pool: $e');
    } finally {
      if (mounted) setState(() => _isPoolLoading = false);
    }
  }

  /// Adopt a confirmed scheduled ride (from the Scheduled Rides screen
  /// Go to Pickup entry) into the unified active-ride execution path.
  /// The ride enters the exact instant-ride pickup state: arrive → start →
  /// stops → complete via the existing navigation panel. `isScheduled: true`
  /// is preserved so the scheduled banner and cancel routing keep working.
  void _adoptScheduledRide(Map<String, dynamic> ride) {
    final rideId = ride['_id']?.toString();
    if (rideId == null || rideId.isEmpty) return;
    if (_status != 'online') {
      CustomSnackbar.show(
        context,
        message: 'Finish your current ride before starting a scheduled one',
        type: SnackbarType.info,
      );
      return;
    }
    AudioService.instance.stop();
    setState(() {
      _status = 'pickup';
      _currentRideId = rideId;
      _rideData = {...ride, 'isScheduled': true};
    });
    _persistActiveRide();
    _fetchNavigationRoute();
    CustomSnackbar.show(
      context,
      message: 'Scheduled ride started — head to pickup',
      type: SnackbarType.success,
    );
  }

  /// Claim a scheduled ride from the pool
  Future<void> _claimScheduledRide(Map<String, dynamic> ride) async {
    final rideId = ride['_id']?.toString();
    if (rideId == null) return;
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.acceptRide(rideId);
      if (response['success'] == true) {
        AudioService.instance.stop();
        final data = response['data'];
        final newData = data is Map<String, dynamic> ? data : <String, dynamic>{};
        setState(() {
          _status = 'pickup';
          _currentRideId = newData['_id']?.toString() ?? rideId;
          _rideData = {...ride, ...newData};
        });
        _persistActiveRide();
        _fetchNavigationRoute();
        CustomSnackbar.show(
          context,
          message: 'Scheduled ride claimed!',
          type: SnackbarType.success,
        );
        // Refresh pool to remove claimed ride
        _fetchScheduledPool();
      } else {
        final message = response['message']?.toString() ?? 'Failed to claim ride';
        ErrorDisplayHelper.showRideError(
          context,
          message,
          errors: response['errors'],
        );
      }
    } catch (e) {
      CustomSnackbar.show(
        context,
        message: 'Error: $e',
        type: SnackbarType.error,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Canonical ride id across socket payload shapes.
  static String? _canonicalRideId(Map<String, dynamic> m) {
    for (final k in ['rideId', 'bookingId', '_id', 'id']) {
      final v = m[k]?.toString();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  void _handleNewRideRequest(dynamic data, {bool quiet = false}) {
    debugPrint(
      '🔔 [DriverHomeScreen] Handling request. Current status: $_status',
    );
    final normalised = _normaliseRideData(data);
    final rideId = _canonicalRideId(normalised);

    // Per-ride dedupe: an already-queued ride must never double-queue.
    // (Deliberately NOT the global RideEventDedupe 5s window — a genuinely
    // new request for another ride must still queue.) This is also what makes
    // dual FCM+socket delivery safe: whichever transport is second no-ops
    // here without a second ringtone.
    if (rideId != null &&
        _requestQueue.any((r) => _canonicalRideId(r) == rideId)) {
      debugPrint(
        '🔔 [DriverHomeScreen] Duplicate request for $rideId — already queued',
      );
      return;
    }

    // Back-to-back offer (driver-multirequest.md §3.1): the backend sends
    // ride:newRequest with isBackToBack:true to busy drivers near the
    // dropoff. It must NEVER enter the idle request queue (that would flip
    // _status/_currentRideId away from Trip A) — it docks as a B2B offer.
    if (normalised['isBackToBack'] == true) {
      _handleB2bOffer(normalised, quiet: quiet);
      return;
    }

    // First request: today's behavior (status=request, ring unless scheduled).
    if (_status == 'online') {
      // Ringtone for instant requests only — scheduled pool entries notify
      // via snackbar so prebook browsing stays quiet (reminders still ring).
      // `quiet` (FCM path) skips the ring — FCM already played the sound.
      if (!quiet && normalised['isScheduled'] != true) {
        debugPrint('🔔 [DriverHomeScreen] Starting ringtone sound...');
        // Use playRingtone for better visibility as it's meant for alerts
        // Play app custom notification sound
        AudioService.instance.playNotification();
      }

      setState(() {
        _requestQueue.add(normalised);
        _requestIndex = 0;
        _status = 'request';
        _currentRideId = rideId;
        _rideData = normalised;
        _acceptError = null;
      });

      // Show notification
      final isScheduled = normalised['isScheduled'] == true;
      final isFallback = normalised['isFallback']?.toString().toLowerCase() == 'true';

      String message = isScheduled ? 'Scheduled Ride Request!' : 'New Ride Request!';
      if (isFallback) {
        message = 'Open Ride Request (5-Seater)!';
      }

      CustomSnackbar.show(
        context,
        message: message,
        type: SnackbarType.success,
      );
    } else if (_status == 'request') {
      // A card is already open — stack instead of replacing or dropping.
      if (_requestQueue.length >= _maxQueuedRequests) {
        debugPrint(
          '⚠️ [DriverHomeScreen] Request queue full ($_maxQueuedRequests) — dropping $rideId',
        );
        return;
      }
      setState(() {
        // Newest surfaces first (index 0) — the fresh offer takes the card
        // and the previous card becomes a background row.
        _requestQueue.insert(0, normalised);
        _requestIndex = 0;
        _rideData = normalised;
        _currentRideId = rideId;
        _acceptError = null;
      });
      // No ringtone per append — only the empty→non-empty transition rings.
      CustomSnackbar.show(
        context,
        message: 'New request stacked (${_requestQueue.length} total)',
        type: SnackbarType.info,
      );
    } else {
      // Busy (on a ride, collecting cash, ...): drop the request.
      // Backend now suppresses ride:newRequest + FCM for active drivers
      // (getBusyDriverIds check). If a request still arrives (race, bug,
      // legacy path), we silently ignore it — no parking, no snackbar.
      // This matches the suppression intent and prevents queue pollution.
      if (_status == 'offline') {
        debugPrint(
          '⚠️ [DriverHomeScreen] Received request but status is $_status',
        );
        return;
      }
      // Active ride guard: _currentRideId is set for all busy states
      // (pickup, arrived, driver_arrived, in_progress, at_stop,
      // awaiting_payment, awaiting_cash_confirmation).
      if (_currentRideId != null) {
        debugPrint(
          '🔔 [DriverHomeScreen] Dropping request $rideId — driver has active ride ($_currentRideId, status=$_status)',
        );
        return;
      }
      // No active ride but not online/request (should not happen).
      // Park as fallback for any unforeseen intermediate state.
      if (_requestQueue.length >= _maxQueuedRequests) {
        debugPrint(
          '⚠️ [DriverHomeScreen] Parked queue full ($_maxQueuedRequests) — dropping $rideId',
        );
        return;
      }
      debugPrint(
        '🔔 [DriverHomeScreen] Parking request $rideId while $_status (no active ride) — promotes on online',
      );
      setState(() {
        _requestQueue.insert(0, normalised);
        _requestIndex = 0;
      });
      CustomSnackbar.show(
        context,
        message: 'New request received — shows after your current step',
        type: SnackbarType.info,
      );
    }
  }

  /// Back-to-back offer entry (socket ride:newRequest + FCM ride_request
  /// foreground/tap all funnel through `_handleNewRideRequest`, so this is
  /// the single B2B intake). Busy drivers (active Trip A) get the offer
  /// docked; idle drivers fall through to the normal card flow with the
  /// flag riding along for the panel badge.
  void _handleB2bOffer(Map<String, dynamic> offer, {bool quiet = false}) {
    if (!mounted) return;
    // Single queue: one queued trip at a time (backend enforces too).
    // A queue whose previousRide is no longer the active ride is stale —
    // recover it from the server instead of dropping every future offer.
    if (shouldBlockB2bOffer(
      hasQueuedTrip: _queuedTrip != null,
      queuedPreviousRideId: _queuedTrip?['previousRide']?.toString(),
      currentRideId: _currentRideId,
    )) {
      debugPrint(
        '🔄 [DriverHomeScreen][B2B] Second offer dropped — queued trip already held',
      );
      return;
    }
    if (_queuedTrip != null) {
      final staleId = _canonicalRideId(_queuedTrip!);
      debugPrint(
        '🔄 [DriverHomeScreen][B2B] Stale queue $staleId — recovering from server',
      );
      if (staleId != null) _recoverQueuedTrip(staleId);
      return;
    }
    const busy = [
      'pickup',
      'arrived',
      'driver_arrived',
      'in_progress',
      'at_stop',
      'awaiting_cash_confirmation',
      'awaiting_payment',
    ];
    if (_currentRideId == null || !busy.contains(_status)) {
      // Idle (or unforeseen state without an active ride): normal card flow.
      debugPrint(
        '🔄 [DriverHomeScreen][B2B] Flag on idle driver — normal card flow',
      );
      _handleIdleB2bOffer(offer, quiet: quiet);
      return;
    }
    // Mid-trip: dock the offer, keep Trip A navigation untouched.
    if (!quiet) AudioService.instance.playNotification();
    setState(() {
      _b2bOffer = offer;
      _b2bOfferError = null;
    });
    debugPrint(
      '🔄 [DriverHomeScreen][B2B] Docked offer ${_canonicalRideId(offer)} (fare=${offer['fare']})',
    );
    debugPrint(
      '🔄 [DriverHomeScreen][B2B] Offer payload pickup=${offer['pickupLocation']} dropoff=${offer['dropoffLocation']} flatPickup=${offer['pickupAddress']} flatDropoff=${offer['dropoffAddress']}',
    );
    CustomSnackbar.show(
      context,
      message: 'New ride near your dropoff — tap to queue it',
      type: SnackbarType.success,
    );
  }

  /// Idle-path B2B intake: mirrors the first-request branch of
  /// `_handleNewRideRequest` without duplicating its guards.
  void _handleIdleB2bOffer(Map<String, dynamic> offer, {bool quiet = false}) {
    if (_status == 'online') {
      if (!quiet) AudioService.instance.playNotification();
      final rideId = _canonicalRideId(offer);
      setState(() {
        _requestQueue.add(offer);
        _requestIndex = 0;
        _status = 'request';
        _currentRideId = rideId;
        _rideData = offer;
        _acceptError = null;
      });
      CustomSnackbar.show(
        context,
        message: 'New Ride Request!',
        type: SnackbarType.success,
      );
    } else if (_status == 'request') {
      if (_requestQueue.length >= _maxQueuedRequests) return;
      final rideId = _canonicalRideId(offer);
      setState(() {
        _requestQueue.insert(0, offer);
        _requestIndex = 0;
        _rideData = offer;
        _currentRideId = rideId;
        _acceptError = null;
      });
    } else {
      debugPrint(
        '⚠️ [DriverHomeScreen][B2B] Offer dropped while $_status (no active ride)',
      );
    }
  }

  /// Accept the docked B2B offer. Trip A stays active; on success with
  /// isQueued:true the trip docks into `_queuedTrip`. A non-queued success
  /// (Trip A ended mid-accept) falls back to normal adoption.
  Future<void> _acceptB2bOffer() async {
    final offer = _b2bOffer;
    if (offer == null || _b2bAccepting) return;
    final offerId = _canonicalRideId(offer);
    if (offerId == null) return;
    setState(() {
      _b2bAccepting = true;
      _b2bOfferError = null;
    });
    try {
      if (!_socketService.isConnected) {
        await _socketService.initSocket(forceReconnect: true);
      }
      _socketService.emitRideAccept(offerId);
      final response = await _apiService.acceptRide(offerId);
      if (!mounted) return;
      if (response['success'] == true) {
        final data = response['data'];
        final newData = data is Map<String, dynamic> ? data : <String, dynamic>{};
        // Validate through the 20-01 parser (never throws); the raw merged
        // map stays the display source of truth.
        QueuedRide.fromMap({...offer, ...newData});
        AudioService.instance.stop();
        if (newData['isQueued'] == true) {
          setState(() {
            _queuedTrip = {...offer, ...newData};
            _b2bOffer = null;
          });
          debugPrint(
            '🔄 [DriverHomeScreen][B2B] Queued trip $offerId accepted (isQueued:true)',
          );
          CustomSnackbar.show(
            context,
            message: 'Next trip queued!',
            type: SnackbarType.success,
          );
        } else {
          // Trip A ended before accept landed — adopt normally.
          setState(() {
            _status = 'pickup';
            _currentRideId = newData['_id']?.toString() ?? offerId;
            _rideData = {...offer, ...newData};
            _b2bOffer = null;
          });
          _persistActiveRide();
          _fetchNavigationRoute();
          CustomSnackbar.show(
            context,
            message: 'Ride Accepted!',
            type: SnackbarType.success,
          );
        }
      } else {
        final message = response['message']?.toString() ?? 'Failed to accept ride';
        final info = RideErrorMapper.map(message, response['errors']);
        setState(() => _b2bOfferError = '${info.title}: ${info.copy}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _b2bOfferError = 'Error: $e');
    } finally {
      if (mounted) setState(() => _b2bAccepting = false);
    }
  }

  /// Dismiss the docked B2B offer locally (no endpoint: the backend
  /// re-pools unaccepted offers on timeout, same as declined cards).
  void _declineB2bOffer() {
    AudioService.instance.stop();
    setState(() {
      _b2bOffer = null;
      _b2bOfferError = null;
    });
  }

  /// Cancel the accepted queued trip (§2.1B). Trip A is untouched.
  Future<Map<String, dynamic>> _performQueuedCancel(String reason) async {
    final queuedId = _canonicalRideId(_queuedTrip ?? {});
    if (queuedId == null) {
      return {'ok': false, 'message': 'No queued trip.'};
    }
    try {
      final response = await _apiService.cancelRideByDriver(
        queuedId,
        reason: reason,
      );
      if (response['success'] != true) {
        final info = RideErrorMapper.map(
          response['message']?.toString() ?? 'Failed to cancel queued ride',
          response['errors'],
        );
        return {'ok': false, 'message': '${info.title}: ${info.copy}'};
      }
      return {'ok': true};
    } catch (e) {
      return {
        'ok': false,
        'message':
            'Error cancelling queued ride: ${e.toString().replaceAll('Exception: ', '')}',
      };
    }
  }

  /// Compact reason sheet for the queued pill's Cancel action. Reuses the
  /// active-trip reason values; success clears the pill only.
  void _showQueuedCancelDialog() {
    String? selectedReason;
    bool sheetLoading = false;
    String? sheetError;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cancel Next Trip'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your current trip is unaffected.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _driverCancelReasons
                    .map(
                      (reason) => ChoiceChip(
                        label: Text(reason['label']!),
                        selected: selectedReason == reason['value'],
                        onSelected: sheetLoading
                            ? null
                            : (selected) => setDialogState(() {
                                  selectedReason =
                                      selected ? reason['value'] : null;
                                }),
                      ),
                    )
                    .toList(),
              ),
              if (sheetError != null) ...[
                const SizedBox(height: 8),
                Text(
                  sheetError!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed:
                  sheetLoading ? null : () => Navigator.pop(context),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: sheetLoading
                  ? null
                  : () async {
                      if (selectedReason == null) {
                        setDialogState(
                          () => sheetError = 'Select a reason to continue.',
                        );
                        return;
                      }
                      setDialogState(() {
                        sheetLoading = true;
                        sheetError = null;
                      });
                      final outcome = await _performQueuedCancel(
                        selectedReason!,
                      );
                      if (!mounted) return;
                      if (!outcome['ok']) {
                        setDialogState(() {
                          sheetLoading = false;
                          sheetError = outcome['message']?.toString();
                        });
                        return;
                      }
                      Navigator.pop(context);
                      setState(() => _queuedTrip = null);
                      debugPrint(
                        '🔄 [DriverHomeScreen][B2B] Queued trip cancelled by driver',
                      );
                      CustomSnackbar.show(
                        context,
                        message: 'Queued trip cancelled.',
                        type: SnackbarType.info,
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Cancel Trip'),
            ),
          ],
        ),
      ),
    );
  }

  /// Promote the queued trip to the active trip (§5.1 transition).
  /// First trigger wins: the completeRide response path and the
  /// ride:nextTripActivated event race — whichever runs second finds
  /// `_queuedTrip == null` (or an id mismatch) and no-ops.
  void _promoteQueuedTrip(Map<String, dynamic> next) {
    final nextId = _canonicalRideId(next);
    final queuedId =
        _queuedTrip == null ? null : _canonicalRideId(_queuedTrip!);
    // Event for an unknown ride: ignore — EXCEPT when the driver has no
    // active ride (late/lost event after local state was cleared). The
    // event payload is authoritative then: promote straight from it.
    if (nextId == null || nextId.isEmpty) return;
    if (queuedId != nextId) {
      if (_currentRideId == nextId) return;
      final driverFree = _currentRideId == null &&
          const ['online', 'offline', 'complete', 'awaiting_cash_confirmation']
              .contains(_status);
      if (!driverFree) {
        debugPrint(
          '🔄 [DriverHomeScreen][B2B] Ignoring promotion for unknown ride $nextId',
        );
        return;
      }
      debugPrint(
        '🔄 [DriverHomeScreen][B2B] Late promotion event for $nextId — activating',
      );
    }
    AudioService.instance.stop();
    setState(() {
      _status = 'pickup';
      _currentRideId = nextId;
      _rideData = {...?_queuedTrip, ...next};
      _queuedTrip = null;
      _b2bOffer = null;
      _b2bOfferError = null;
    });
    debugPrint(
      '🔄 [DriverHomeScreen][B2B] Promoted queued trip $nextId to active',
    );
    _persistActiveRide();
    _fetchNavigationRoute();
    CustomSnackbar.show(
      context,
      message: 'Your next ride is ready! Head to the pickup location.',
      type: SnackbarType.success,
    );
  }

  /// True when the completeRide response carries a queued promotion
  /// (§2.1C: hasQueuedRidePromoted + nextRideId) matching the docked trip.
  bool _hasQueuedPromotion(Map<String, dynamic> rideResult) {
    if (_queuedTrip == null) return false;
    final promo = CompletePromotion.fromMap(rideResult);
    if (!promo.hasQueuedRidePromoted || promo.nextRideId.isEmpty) return false;
    return _canonicalRideId(_queuedTrip!) == promo.nextRideId;
  }

  /// Authoritative queued-trip reconciliation. Runs when the local belief
  /// ("still queued") and the server disagree, or the promotion trigger was
  /// lost: the pill must never strand the driver invisible-and-bricked.
  ///
  /// - Server says promoted (`isQueued:false` present and not true) → promote.
  /// - Still queued → keep the docked pill visible and log for the trail.
  Future<void> _recoverQueuedTrip(String queuedId) async {
    if (_isLoading) return;
    try {
      final response = await _apiService.getRideDetails(queuedId);
      if (!mounted) return;
      if (_canonicalRideId(_queuedTrip ?? {}) != queuedId) return;
      final data = response['data'];
      if (data is Map) {
        final ride = Map<String, dynamic>.from(data);
        final serverQueued = ride['isQueued'];
        if (serverQueued != null && serverQueued != true) {
          debugPrint(
            '🔄 [DriverHomeScreen][B2B] Server promoted $queuedId — activating',
          );
          _promoteQueuedTrip(ride);
          return;
        }
        // Still queued on the server: refresh the pill payload (fresh fare,
        // address) so the driver sees current truth.
        setState(() => _queuedTrip = {..._queuedTrip!, ...ride});
      }
      debugPrint(
        '🔄 [DriverHomeScreen][B2B] $queuedId still queued — pill stays visible',
      );
    } catch (e) {
      debugPrint('🔄 [DriverHomeScreen][B2B] Recovery fetch failed: $e');
    }
  }

  /// Schedule a reconciliation after a completion that carried no promotion
  /// flags — the promotion event may still be in flight, and if it never
  /// arrives the server check repairs local state.
  void _scheduleQueuedRecovery() {
    final queuedId = _canonicalRideId(_queuedTrip ?? {});
    if (queuedId == null) return;
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) _recoverQueuedTrip(queuedId);
    });
  }

  /// Surface a parked request now that the driver is free.
  /// No-op unless genuinely back to online with no active ride and a
  /// non-empty park queue. Call after every reset-to-online.
  /// Note: Since backend suppression (getBusyDriverIds), requests during
  /// active rides are dropped in _handleNewRideRequest, not parked. This
  /// promotes only requests parked in unforeseen intermediate states.
  void _promoteParkedRequests() {
    if (!mounted ||
        _status != 'online' ||
        _currentRideId != null ||
        _requestQueue.isEmpty) {
      return;
    }
    var head = _requestIndex;
    if (head < 0) head = 0;
    if (head >= _requestQueue.length) head = _requestQueue.length - 1;
    final current = _requestQueue[head];
    final id = _canonicalRideId(current);
    debugPrint('🔔 [DriverHomeScreen] Promoting parked request $id to card');
    setState(() {
      _requestIndex = head;
      _status = 'request';
      _currentRideId = id;
      _rideData = current;
      _acceptError = null;
    });
    // The parked arrival stayed quiet (or rang via FCM) — ring now so the
    // surfaced card is noticed.
    if (current['isScheduled'] != true) {
      AudioService.instance.playNotification();
    }
    CustomSnackbar.show(
      context,
      message: current['isScheduled'] == true
          ? 'Scheduled Ride Request!'
          : 'New Ride Request!',
      type: SnackbarType.success,
    );
  }

  /// Extract a canonical ride id from a socket payload of unknown shape.
  static String? _socketRideId(dynamic data) {
    if (data is Map) {
      return _canonicalRideId(Map<String, dynamic>.from(data as Map));
    }
    return null;
  }

  /// Switch the visible card without accepting/declining. Clamps the index
  /// so out-of-range panel calls can never desync _rideData/_currentRideId.
  void _selectQueuedRequest(int index) {
    if (_status != 'request' || _requestQueue.isEmpty) return;
    var next = index;
    if (next < 0) next = 0;
    if (next >= _requestQueue.length) next = _requestQueue.length - 1;
    if (next == _requestIndex) return;
    setState(() {
      _requestIndex = next;
      final current = _requestQueue[_requestIndex];
      _currentRideId = _canonicalRideId(current);
      _rideData = current;
      // Error banner belongs to the visible card — never carry it across.
      _acceptError = null;
    });
  }

  /// Remove one queued request by ride id. While requests remain, the current
  /// card points at queue[_requestIndex] and status stays request; when the
  /// last one goes, drains to online mirroring the _declineRide reset.
  /// Returns true when something was actually removed.
  bool _removeQueuedRequest(String rideId, {String? goneMessage}) {
    final idx = _requestQueue.indexWhere((r) => _canonicalRideId(r) == rideId);
    if (idx == -1) return false;
    setState(() {
      _requestQueue.removeAt(idx);
      if (idx <= _requestIndex && _requestIndex > 0) _requestIndex--;
      if (_requestQueue.isEmpty) {
        _status = 'online';
        _currentRideId = null;
        _rideData = null;
        _requestIndex = 0;
        _clearNavigationUi();
        _clearActiveRideStorage();
        AudioService.instance.stop();
      } else {
        if (_requestIndex >= _requestQueue.length) {
          _requestIndex = _requestQueue.length - 1;
        }
        final current = _requestQueue[_requestIndex];
        _currentRideId = _canonicalRideId(current);
        _rideData = current;
        _status = 'request';
      }
    });
    if (goneMessage != null && mounted) {
      CustomSnackbar.show(
        context,
        message: goneMessage,
        type: SnackbarType.info,
      );
    }
    return true;
  }

  Future<void> _toggleOnline() async {
    if (_isLoading) return;

    final bool isGoingOnline = _status == 'offline';

    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint(
        '🔵 [DriverHomeScreen] Toggling status. Current: $_status, Target: ${isGoingOnline ? 'online' : 'offline'}',
      );

      final response = await _apiService.updateDriverStatus(isGoingOnline);

      if (response['success'] == true) {
        setState(() {
          _status = isGoingOnline ? 'online' : 'offline';

          // If going offline, ensure any previous ride route is cleared from the map.
          if (!isGoingOnline) {
            _currentRideId = null;
            _rideData = null;
            _requestQueue.clear();
            _requestIndex = 0;
            _clearNavigationUi();
            AudioService.instance.stop();
          }
        });

        if (mounted) {
          CustomSnackbar.show(
            context,
            message:
                response['message'] ??
                (isGoingOnline ? 'You are now Online' : 'You are now Offline'),
            type: SnackbarType.success,
          );

          if (isGoingOnline) {
            _emitDriverOnline(force: true);
            _startLocationUpdates();
            _fetchScheduledPool();
          } else {
            _positionStreamSubscription?.cancel();
            setState(() => _scheduledPool = []);
            // Optional: emit driver:goOffline
          }
        }
        debugPrint(
          '🟢 [DriverHomeScreen] Status updated successfully to $_status',
        );
      } else {
        // Handle error responses, including 403 validation errors
        // Check for error code in both locations: root level or nested in 'errors' object
        final errors = response['errors'] as Map<String, dynamic>?;
        final errorCode =
            errors?['code']?.toString() ?? response['code']?.toString() ?? '';
        final errorMessage =
            response['message']?.toString() ?? 'Failed to update status';

        debugPrint('🔴 [DriverHomeScreen] Failed to update status');
        debugPrint('🔴 [DriverHomeScreen] Error Code: $errorCode');
        debugPrint('🔴 [DriverHomeScreen] Error Message: $errorMessage');

        if (mounted) {
          // Check for specific error codes
          if (errorCode == 'PROFILE_INCOMPLETE') {
            _showProfileIncompleteDialog(errorMessage);
          } else if (errorCode == 'NOT_APPROVED') {
            _showNotApprovedDialog(errorMessage);
          } else {
            CustomSnackbar.show(
              context,
              message: errorMessage,
              type: SnackbarType.error,
            );
          }
        }
      }
    } catch (e) {
      // This should rarely happen now since API service returns errors instead of throwing
      debugPrint('🔴 [DriverHomeScreen] Unexpected error updating status: $e');

      if (mounted) {
        CustomSnackbar.show(
          context,
          message: 'Unexpected error: ${e.toString()}',
          type: SnackbarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        if (_status == 'online') {
          _fetchRideHistory();
        }
      }
    }
  }

  void _showProfileIncompleteDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Profile Incomplete'),
          ],
        ),
        content: Text(
          message.isEmpty
              ? 'Please complete your profile by uploading all required documents before going online.'
              : message,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to document checklist screen
              Navigator.pushNamed(context, '/driver/documents');
            },
            child: const Text('Complete Profile'),
          ),
        ],
      ),
    );
  }

  void _showNotApprovedDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.pending, color: Colors.blue),
            SizedBox(width: 8),
            Text('Pending Approval'),
          ],
        ),
        content: Text(
          message.isEmpty
              ? 'Your account is pending admin approval. Please wait for verification to complete before going online.'
              : message,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to document checklist screen to view status
              Navigator.pushNamed(context, '/driver/documents');
            },
            child: const Text('View Status'),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchRideHistory() async {
    if (!mounted) return;
    setState(() => _isHistoryLoading = true);

    try {
      final response = await _apiService.getDriverRides();
      if (response['success'] == true) {
        final rides = response['data'] as List<dynamic>;

        // Process today's stats
        final now = DateTime.now();
        final todayRides = rides.where((ride) {
          if (ride['createdAt'] == null) return false;
          final createdAt = DateTime.parse(ride['createdAt']);
          return createdAt.year == now.year &&
              createdAt.month == now.month &&
              createdAt.day == now.day;
        }).toList();

        double totalHours = 0;
        double totalEarnings = 0;
        for (var ride in todayRides) {
          final status = ride['status']?.toString().toLowerCase();
          if (status == 'completed' || status == 'early_completed') {
            // Get duration in minutes
            double durationMin = (ride['duration'] as num?)?.toDouble() ?? 0;

            // If duration is 0/null, calculate from timestamps
            if (durationMin == 0 && ride['acceptedAt'] != null) {
              try {
                final start = DateTime.parse(ride['acceptedAt']);
                final endInput =
                    ride['completedAt'] ??
                    ride['updatedAt'] ??
                    ride['createdAt'];
                if (endInput != null) {
                  final end = DateTime.parse(endInput);
                  durationMin = end.difference(start).inMinutes.toDouble();
                }
              } catch (e) {
                debugPrint('⚠️ [DriverStats] Error calculating duration: $e');
              }
            }

            totalHours += durationMin / 60.0;
            totalEarnings += (ride['fare'] as num?)?.toDouble() ?? 0.0;
          }
        }

        if (mounted) {
          setState(() {
            _recentRides = rides.take(5).toList();
            _todayStats = {
              'trips': todayRides.length.toString(),
              'hours': totalHours.toStringAsFixed(1),
              'earnings': totalEarnings.toStringAsFixed(2),
            };
          });
        }
      }
    } catch (e) {
      debugPrint('🔴 [DriverHomeScreen] Error fetching history: $e');
    } finally {
      if (mounted) setState(() => _isHistoryLoading = false);
    }
  }

  Future<void> _handleRideAction() async {
    if (_currentRideId == null) {
      CustomSnackbar.show(
        context,
        message: 'Error: No active ride',
        type: SnackbarType.error,
      );
      return;
    }
    // In-flight guard: both arrive and start buttons route here.
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      if (_status == 'request') {
        // Accept Ride
        debugPrint('🚖 [DriverHomeScreen] Accepting ride: $_currentRideId');

        // Ensure the socket is connected so the ride:accept event reaches
        // the backend reliably. On iOS the socket drops more often, so we
        // force a reconnect instead of silently skipping the emit.
        if (!_socketService.isConnected) {
          debugPrint(
            '🔌 [DriverHomeScreen] Socket not connected, forcing reconnect before accept',
          );
          await _socketService.initSocket(forceReconnect: true);
        }

        // Always emit ride:accept via socket (emitReliable queues if still
        // reconnecting). The backend uses this event to broadcast to the
        // passenger — the REST call alone may not trigger the push.
        debugPrint('🔌 [DriverHomeScreen] Emitting ride:accept via socket');
        _socketService.emitRideAccept(_currentRideId!);

        // Always call REST API as a reliable fallback/method if socket is shaky or as primary
        final response = await _apiService.acceptRide(_currentRideId!);
        if (response['success'] == true) {
          AudioService.instance.stop();
          setState(() {
            _status = 'pickup';
            _acceptError = null;
            // Driver is now busy — pending stacked requests are stale.
            _requestQueue.clear();
            _requestIndex = 0;
            if (response['data'] != null) {
              final newData = response['data'] as Map<String, dynamic>;
              _rideData = {...?_rideData, ...newData};
              _currentRideId = newData['_id']?.toString() ?? _currentRideId;
            }
          });
          _persistActiveRide();
          CustomSnackbar.show(
            context,
            message: 'Ride Accepted!',
            type: SnackbarType.success,
          );
          // Fetch navigation route to pickup
          _fetchNavigationRoute();
        } else {
          final message = response['message']?.toString() ?? 'Failed to accept ride';
          final info = RideErrorMapper.map(message, response['errors']);
          setState(() => _acceptError = '${info.title}: ${info.copy}');
        }
      } else if (_status == 'pickup') {
        // Arrive at Pickup
        // Get current location
        final pos = _currentLocation;

        final response = await _apiService.arriveAtPickup(
          _currentRideId!,
          pos.latitude,
          pos.longitude,
        );

        if (response['success'] == true) {
          final data = response['data'] is Map<String, dynamic>
              ? response['data'] as Map<String, dynamic>
              : <String, dynamic>{};
          setState(() {
            _status = 'arrived';
            // Proximity resolved — drop the banner.
            _proximityDistance = null;
            _proximityRequired = null;
            // Backend-authoritative wait policy; WaitFeePolicy fallback.
            _harvestWaitPolicy(data);
            if (response['data'] != null) {
              final newData = response['data'] as Map<String, dynamic>;
              _rideData = {...?_rideData, ...newData};
            }
          });
          _persistActiveRide();
          CustomSnackbar.show(
            context,
            message: 'You have arrived!',
            type: SnackbarType.success,
          );
        } else {
          final errors = response['errors'];
          final distance = errors is Map ? errors['distance'] : null;
          if (distance != null) {
            // Proximity error: persistent banner + mapper copy (never a
            // dismiss-only toast — banner stays until arrival succeeds).
            final distInt = distance is num
                ? distance.toInt()
                : int.tryParse(distance.toString()) ?? 0;
            final reqRaw = errors is Map ? errors['required'] : null;
            final reqInt = reqRaw is num
                ? reqRaw.toInt()
                : int.tryParse(reqRaw?.toString() ?? '') ?? 100;
            setState(() {
              _proximityDistance = distInt;
              _proximityRequired = reqInt;
              _proximityTarget = 'pickup';
            });
          }
          if (!mounted) return;
          ErrorDisplayHelper.showRideError(
            context,
            response['message']?.toString() ?? 'Failed to arrive',
            errors: response['errors'],
            onAction: _handleRideAction,
          );
        }
      } else if (_status == 'arrived' || _status == 'driver_arrived') {
        // One-tap start — no code entry on the driver side.
        await _startRideNoOtp();
      } else if (_status == 'at_stop') {
        // Main action mirrors the per-stop card: resume the trip.
        await _handleStopResume();
      } else if (_status == 'in_progress') {
        // Complete Ride — silent guard picks the freshest known fix first,
        // always falls back to last known. Never blocks, never prompts.
        //
        // Offline (19-03): completion is REST-only (no socket contract for
        // it), so the button stays enabled with queued-intent copy and no
        // state change — never a fake success, never a double-fire.
        if (!_socketService.isConnected) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          CustomSnackbar.show(
            context,
            message: 'Complete ride — $kQueuedIntentCopy',
            type: SnackbarType.info,
          );
          return;
        }
        final pos = await _bestEffortCompletionLocation();
        final response = await _apiService.completeRide(
          _currentRideId!,
          pos.latitude,
          pos.longitude,
        );
        if (response['success'] == true) {
          final paymentMethod = _rideData?['paymentMethod'];
          final rideResult = response['data'] as Map<String, dynamic>? ?? {};
          // B2B: complete response carries the queued promotion (§2.1C).
          // Fires immediately except on cash trips, where confirmation
          // still has to happen first (20-02 Task 3).
          final promoteQueued = _hasQueuedPromotion(rideResult);
          final summary = FareSummary.fromJson({
            ...?_rideData,
            ...rideResult,
          });
          setState(() {
            _rideData = {...?_rideData, ...rideResult};
          });
          final bool isPromoFreeRide =
              rideResult['isPromoRide'] == true &&
              (rideResult['fare'] is num
                      ? (rideResult['fare'] as num).toDouble()
                      : 0.0) ==
                  0.0;

          if (paymentMethod == 'cash' && isPromoFreeRide) {
            // Fully discounted promo ride — no cash to collect, auto-finalize
            final confirmResponse = await _apiService.confirmCashCollection(
              _currentRideId!,
            );
            if (confirmResponse['success'] == true) {
              // B2B: Trip B takes over instead of going online (20-02).
              if (promoteQueued && _queuedTrip != null) {
                _promoteQueuedTrip(_queuedTrip!);
                _fetchRideHistory();
                if (!mounted) return;
                _showFareSummary(
                  summary: summary,
                  headline: 'Promotional ride complete',
                  subline: 'No cash to collect.',
                );
                return;
              }
              setState(() {
                _status = 'online';
                _currentRideId = null;
                _rideData = null;
                _clearNavigationUi();
              });
              _promoteParkedRequests();
              _fetchRideHistory();
              if (!mounted) return;
              _showFareSummary(
                summary: summary,
                headline: 'Promotional ride complete',
                subline: 'No cash to collect.',
              );
            } else {
              if (!mounted) return;
              ErrorDisplayHelper.showRideError(
                context,
                confirmResponse['message']?.toString() ?? 'Failed to finalize',
                errors: confirmResponse['errors'],
              );
            }
          } else if (paymentMethod == 'cash') {
          // B2B: promotion defers until cash is confirmed (20-02).
          _queuedPromotionPending = promoteQueued;
          setState(() {
            _status = 'awaiting_cash_confirmation';
          });
          _persistActiveRide();
          if (!mounted) return;
          _showFareSummary(
            summary: summary,
            headline: 'Ride completed',
            subline: 'Collect cash from the passenger.',
          );
          } else {
            // B2B: Trip B takes over instead of going online (20-02).
            if (promoteQueued && _queuedTrip != null) {
              _promoteQueuedTrip(_queuedTrip!);
              _fetchRideHistory();
              if (!mounted) return;
              _showFareSummary(
                summary: summary,
                headline: 'Ride completed successfully',
                subline: null,
              );
              return;
            }
            setState(() {
              _status = 'online';
              _currentRideId = null;
              _rideData = null;
              _clearNavigationUi();
            });
            // Promotion flags absent: keep the pill and reconcile with the
            // server — the promotion event may still be in flight, or the
            // local queue may be stale (20-02 recovery).
            if (_queuedTrip != null) _scheduleQueuedRecovery();
            _promoteParkedRequests();
            _fetchRideHistory();
            if (!mounted) return;
            _showFareSummary(
              summary: summary,
              headline: 'Ride completed successfully',
              subline: null,
            );
          }
        } else {
          if (!mounted) return;
          ErrorDisplayHelper.showRideError(
            context,
            response['message']?.toString() ?? 'Failed to complete',
            errors: response['errors'],
            onAction: _handleRideAction,
          );
        }
      } else if (_status == 'awaiting_cash_confirmation') {
        // Confirm Cash Collection.
        //
        // Offline (19-03): REST-only action — button stays enabled with
        // queued-intent copy, no state change, no double-fire.
        if (!_socketService.isConnected) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          CustomSnackbar.show(
            context,
            message: 'Confirm cash — $kQueuedIntentCopy',
            type: SnackbarType.info,
          );
          return;
        }
        final response = await _apiService.confirmCashCollection(
          _currentRideId!,
        );
        if (response['success'] == true) {
          CustomSnackbar.show(
            context,
            message: 'Cash collected. Ride finalized.',
            type: SnackbarType.success,
          );
          // B2B: deferred promotion fires after cash confirmation (20-02).
          if (_queuedPromotionPending && _queuedTrip != null) {
            _queuedPromotionPending = false;
            _promoteQueuedTrip(_queuedTrip!);
            _fetchRideHistory();
            return;
          }
          _queuedPromotionPending = false;
          // Reset to online
          setState(() {
            _status = 'online';
            _currentRideId = null;
            _rideData = null;
            _clearNavigationUi();
            _clearActiveRideStorage();
          });
          _promoteParkedRequests();
          _fetchRideHistory();
        } else {
          if (!mounted) return;
          ErrorDisplayHelper.showRideError(
            context,
            response['message']?.toString() ?? 'Failed to confirm cash',
            errors: response['errors'],
            onAction: _handleRideAction,
          );
        }
      }
    } catch (e) {
      CustomSnackbar.show(
        context,
        message: 'Error: $e',
        type: SnackbarType.error,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Stage 2 excess-cash collect modal (STAGE2-04/05): rider requested to
  /// pay the excess balance in cash. `barrierDismissible:false` so the
  /// driver must confirm; failure keeps the modal open with inline
  /// mapper copy, success pops + toasts.
  void _showExcessCashDialog(String rideId, double amount) {
    if (_excessCashDialogOpen || !mounted) return;
    _excessCashDialogOpen = true;
    final amountLabel = '£${amount.toStringAsFixed(2)}';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _excessCashDialogContext = dialogContext;
        bool confirming = false;
        String? sheetError;
        return StatefulBuilder(
          builder: (sheetContext, setDialogState) => AlertDialog(
            title: Text('Collect Cash: $amountLabel'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Passenger requested to pay $amountLabel excess '
                  'balance in cash.',
                ),
                if (sheetError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    sheetError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: confirming
                    ? null
                    : () async {
                        setDialogState(() {
                          confirming = true;
                          sheetError = null;
                        });
                        final response =
                            await _apiService.confirmDriverCash(rideId);
                        if (!mounted) return;
                        if (response['success'] == true) {
                          _excessCashDialogOpen = false;
                          _excessCashDialogContext = null;
                          Navigator.pop(dialogContext);
                          CustomSnackbar.show(
                            context,
                            message:
                                'Cash payment confirmed! Ride fully completed.',
                            type: SnackbarType.success,
                          );
                        } else {
                          final info = RideErrorMapper.map(
                            response['message']?.toString() ??
                                'Failed to confirm cash',
                            response['errors'],
                          );
                          setDialogState(() {
                            confirming = false;
                            sheetError = '${info.title}: ${info.copy}';
                          });
                        }
                      },
                child: confirming
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Confirm Cash Received'),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      _excessCashDialogOpen = false;
      _excessCashDialogContext = null;
    });
  }

  /// Pop the excess-cash modal if open. Used by the cancelled/succeeded
  /// auto-close paths — silent, no toast.
  void _closeExcessCashDialogIfOpen() {
    if (!_excessCashDialogOpen) return;
    _excessCashDialogOpen = false;
    final dialogCtx = _excessCashDialogContext;
    _excessCashDialogContext = null;
    if (dialogCtx != null && mounted) {
      Navigator.pop(dialogCtx);
    }
  }

  /// Fare receipt after completion: actualFare + accumulated wait totals.
  void _showFareSummary({
    required FareSummary summary,
    required String headline,
    String? subline,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(headline),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Trip total'),
                Text(
                  '£${summary.actualFare.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Base fare £${summary.fare.toStringAsFixed(2)}'),
            if (summary.totalWaitMinutes > 0 || summary.totalWaitFee > 0)
              Text(
                'Wait ${summary.totalWaitMinutes} min · '
                '£${summary.totalWaitFee.toStringAsFixed(2)} fees',
              ),
            if (subline != null) ...[
              const SizedBox(height: 12),
              Text(
                subline,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// Current stop label for proximity guidance ("stop #2").
  String get _currentStopLabel {
    final stops = parseRideStops(_rideData?['stops']);
    final idx = (_rideData?['currentStopIndex'] as num?)?.toInt() ?? 0;
    final active = stops.firstWhere(
      (s) => !s.isCompleted,
      orElse: () => const RideStop(),
    );
    final order = active.stopOrder != 0 ? active.stopOrder : idx + 1;
    return 'stop #$order';
  }

  /// Mark arrival at the current intermediate stop (100m enforced backend).
  /// Proximity errors reuse the persistent banner pattern from pickup.
  Future<void> _handleStopArrive() async {
    if (_currentRideId == null) return;
    final manageLoading = !_isLoading;
    if (manageLoading) setState(() => _isLoading = true);
    try {
      final response = await _apiService.stopArrive(
        _currentRideId!,
        _currentLocation.latitude,
        _currentLocation.longitude,
      );
      if (response['success'] == true) {
        final data = response['data'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(response['data'] as Map)
            : <String, dynamic>{};
        setState(() {
          _status = 'at_stop';
          _proximityDistance = null;
          _proximityRequired = null;
          // Stop-arrive may carry an updated per-ride policy — harvest it.
          _harvestWaitPolicy(data);
          _rideData = {...?_rideData, ...data};
        });
        _persistActiveRide();
        if (!mounted) return;
        CustomSnackbar.show(
          context,
          message: 'Arrived at ${_currentStopLabel} — waiting time started.',
          type: SnackbarType.success,
        );
        _fetchNavigationRoute();
      } else {
        final errors = response['errors'];
        final distance = errors is Map ? errors['distance'] : null;
        if (distance != null) {
          final distInt = distance is num
              ? distance.toInt()
              : int.tryParse(distance.toString()) ?? 0;
          final reqRaw = errors is Map ? errors['required'] : null;
          final reqInt = reqRaw is num
              ? reqRaw.toInt()
              : int.tryParse(reqRaw?.toString() ?? '') ?? 100;
          setState(() {
            _proximityDistance = distInt;
            _proximityRequired = reqInt;
            _proximityTarget = _currentStopLabel;
          });
        }
        if (!mounted) return;
        ErrorDisplayHelper.showRideError(
          context,
          response['message']?.toString() ?? 'Failed to arrive at stop',
          errors: response['errors'],
          onAction: _handleStopArrive,
        );
      }
    } catch (e) {
      if (!mounted) return;
      CustomSnackbar.show(
        context,
        message: 'Error: $e',
        type: SnackbarType.error,
      );
    } finally {
      if (manageLoading && mounted) setState(() => _isLoading = false);
    }
  }

  /// Resume from the stop — backend accrues the leg wait fee into totals.
  Future<void> _handleStopResume() async {
    if (_currentRideId == null) return;
    final manageLoading = !_isLoading;
    if (manageLoading) setState(() => _isLoading = true);
    try {
      final response = await _apiService.stopResume(_currentRideId!);
      if (response['success'] == true) {
        final data = response['data'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(response['data'] as Map)
            : <String, dynamic>{};
        final totalFee = data['totalWaitFee'] is num
            ? (data['totalWaitFee'] as num).toDouble()
            : null;
        final totalMins = data['totalWaitMinutes'] is num
            ? (data['totalWaitMinutes'] as num).toInt()
            : null;
        setState(() {
          _status = 'in_progress';
          _proximityDistance = null;
          _proximityRequired = null;
          _rideData = {...?_rideData, ...data};
        });
        _persistActiveRide();
        if (!mounted) return;
        CustomSnackbar.show(
          context,
          message: totalFee != null
              ? 'Trip resumed — wait total £${totalFee.toStringAsFixed(2)}'
                  '${totalMins != null ? ' ($totalMins min)' : ''}.'
              : 'Trip resumed.',
          type: SnackbarType.success,
        );
        _fetchNavigationRoute();
      } else {
        if (!mounted) return;
        ErrorDisplayHelper.showRideError(
          context,
          response['message']?.toString() ?? 'Failed to resume trip',
          errors: response['errors'],
          onAction: _handleStopResume,
        );
      }
    } catch (e) {
      if (!mounted) return;
      CustomSnackbar.show(
        context,
        message: 'Error: $e',
        type: SnackbarType.error,
      );
    } finally {
      if (manageLoading && mounted) setState(() => _isLoading = false);
    }
  }

  void _declineRide() {
    if (_currentRideId == null) return;

    // With stacked requests, declining drops the visible card and reveals
    // the next one; only the last decline returns to online. Audio keeps
    // ringing while the queue is non-empty (_removeQueuedRequest stops it
    // only when drained), so no stop() here.
    if (_status == 'request' && _requestQueue.isNotEmpty) {
      _removeQueuedRequest(_currentRideId!);
      return;
    }

    AudioService.instance.stop();

    // Just reset to online state without calling API
    setState(() {
      _status = 'online';
      _currentRideId = null;
      _rideData = null;
      _clearNavigationUi();
    });
  }

  /// Driver-cancel reasons (flow doc example uses vehicle_breakdown;
  /// ApiService historically sent vehicle_issue — both offered).
  static const List<Map<String, String>> _driverCancelReasons = [
    {'value': 'rider_no_show', 'label': 'Rider no-show'},
    {'value': 'rider_unreachable', 'label': 'Rider unreachable'},
    {'value': 'safety_concern', 'label': 'Safety concern'},
    {'value': 'vehicle_breakdown', 'label': 'Vehicle breakdown'},
    {'value': 'vehicle_issue', 'label': 'Vehicle issue'},
    {'value': 'driver_no_show', 'label': "Can't make it"},
  ];

  /// End-early reasons per the ride-flow contract.
  static const List<Map<String, String>> _endEarlyReasons = [
    {'value': 'user_requested', 'label': 'Rider requested'},
    {'value': 'wrong_destination', 'label': 'Wrong destination'},
    {'value': 'rider_misbehavior', 'label': 'Rider misbehavior'},
    {'value': 'safety_concern', 'label': 'Safety concern'},
    {'value': 'vehicle_issue', 'label': 'Vehicle issue'},
  ];

  /// Show cancellation reason picker and cancel the ride
  void _showCancellationReasonDialog() {
    String? selectedReason;
    bool showReasonError = false;
    bool sheetLoading = false;
    String? sheetError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cancel Ride'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select a reason for cancellation:'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _driverCancelReasons
                      .map(
                        (reason) => ChoiceChip(
                          label: Text(reason['label']!),
                          selected: selectedReason == reason['value'],
                          onSelected: sheetLoading
                              ? null
                              : (selected) => setDialogState(() {
                                    selectedReason =
                                        selected ? reason['value'] : null;
                                    showReasonError = false;
                                  }),
                        ),
                      )
                      .toList(),
                ),
                if (showReasonError) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Please select a reason to continue.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
                if (sheetError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    sheetError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sheetLoading ? null : () => Navigator.pop(context),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: sheetLoading
                  ? null
                  : () async {
                      if (selectedReason == null) {
                        // Required selection — inline guidance, never raw 400.
                        setDialogState(() => showReasonError = true);
                        return;
                      }
                      setDialogState(() {
                        sheetLoading = true;
                        sheetError = null;
                      });
                      final outcome = await _performDriverCancel(
                        selectedReason!,
                      );
                      if (!mounted) return;
                      if (!outcome['ok']) {
                        // Failure stays on the sheet with mapper copy.
                        setDialogState(() {
                          sheetLoading = false;
                          sheetError = outcome['message'];
                        });
                        return;
                      }
                      Navigator.pop(context);
                      _resolveDriverCancelOutcome(outcome);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: sheetLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Cancel Ride',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cancel ride by driver with a reason.
  ///
  /// Returns an outcome map instead of touching UI directly so the sheet
  /// can stay open on failure: `{ok, reassigned, penalty, message}`.
  Future<Map<String, dynamic>> _performDriverCancel(String reason) async {
    if (_currentRideId == null) {
      return {'ok': false, 'message': 'No active ride.'};
    }

    final isScheduled = _rideData?['isScheduled'] == true;

    try {
      Map<String, dynamic> response;
      if (isScheduled) {
        response = await PaymentService.cancelScheduledRideDriver(
          _currentRideId!,
          reason,
        );
      } else {
        response = await _apiService.cancelRideByDriver(
          _currentRideId!,
          reason: reason,
        );
      }

      if (response['success'] != true) {
        final info = RideErrorMapper.map(
          response['message']?.toString() ?? 'Failed to cancel ride',
          response['errors'],
        );
        return {'ok': false, 'message': '${info.title}: ${info.copy}'};
      }

      // Pre-pickup cancel auto-reassigns: the ride lives on without this
      // driver. That's an outcome, not an error.
      final data = response['data'];
      final reassigned = response['reassigned'] == true ||
          (data is Map && data['reassigned'] == true);
      final penalty = isScheduled && data is Map
          ? data['driverPenaltyAmount']
          : null;
      return {
        'ok': true,
        'reassigned': reassigned,
        'penalty': penalty is num ? penalty.toDouble() : null,
      };
    } catch (e) {
      debugPrint('Error cancelling ride: $e');
      return {
        'ok': false,
        'message':
            'Error cancelling ride: ${e.toString().replaceAll('Exception: ', '')}',
      };
    }
  }

  /// Apply a successful driver-cancel outcome: reassigned → info + queue,
  /// full cancel → confirmation + exit.
  void _resolveDriverCancelOutcome(Map<String, dynamic> outcome) {
    final reassigned = outcome['reassigned'] == true;
    final penalty = outcome['penalty'] as double?;
    if (!mounted) return;
    setState(() {
      _status = 'online';
      _currentRideId = null;
      _rideData = null;
      // Trip A is gone — any B2B offer/queue dies with it (20-02).
      _b2bOffer = null;
      _b2bOfferError = null;
      _queuedTrip = null;
      _queuedPromotionPending = false;
      _clearNavigationUi();
      _clearActiveRideStorage();
    });

    if (reassigned) {
      CustomSnackbar.show(
        context,
        message: 'Reassigned to another driver — you are back in the queue.',
        type: SnackbarType.info,
      );
      return;
    }

    var message = 'Ride cancelled.';
    if (penalty != null) {
      message += ' A £${penalty.toStringAsFixed(2)} penalty was applied.';
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ride cancelled'),
        content: Text('$message\nYou are back online.'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show end ride early dialog with reason selection
  void _showEndRideEarlyDialog() {
    String? selectedReason;
    bool showReasonError = false;
    bool sheetLoading = false;
    String? sheetError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('End Ride Early'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The fare will be adjusted based on actual distance traveled.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                const Text('Select a reason:'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _endEarlyReasons
                      .map(
                        (reason) => ChoiceChip(
                          label: Text(reason['label']!),
                          selected: selectedReason == reason['value'],
                          onSelected: sheetLoading
                              ? null
                              : (selected) => setDialogState(() {
                                    selectedReason =
                                        selected ? reason['value'] : null;
                                    showReasonError = false;
                                  }),
                        ),
                      )
                      .toList(),
                ),
                if (showReasonError) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Please select a reason to continue.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
                if (sheetError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    sheetError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sheetLoading ? null : () => Navigator.pop(context),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: sheetLoading
                  ? null
                  : () async {
                      if (selectedReason == null) {
                        setDialogState(() => showReasonError = true);
                        return;
                      }
                      setDialogState(() {
                        sheetLoading = true;
                        sheetError = null;
                      });
                      final outcome = await _performEndEarly(selectedReason!);
                      if (!mounted) return;
                      if (!outcome['ok']) {
                        // Failure stays on the sheet with mapper copy.
                        setDialogState(() {
                          sheetLoading = false;
                          sheetError = outcome['message'];
                        });
                        return;
                      }
                      Navigator.pop(context);
                      _resolveEndEarlyOutcome(outcome);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: sheetLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'End Ride',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// End the ride early with adjusted fare.
  ///
  /// Returns an outcome map so the sheet can stay open on failure:
  /// `{ok, adjustedFare, actualDistance, paymentMethod, message}`.
  Future<Map<String, dynamic>> _performEndEarly(String reason) async {
    if (_currentRideId == null) {
      return {'ok': false, 'message': 'No active ride.'};
    }

    try {
      final response = await _apiService.endRideEarly(
        _currentRideId!,
        latitude: _currentLocation.latitude,
        longitude: _currentLocation.longitude,
        reason: reason,
      );

      if (response['success'] != true) {
        final info = RideErrorMapper.map(
          response['message']?.toString() ?? 'Failed to end ride',
          response['errors'],
        );
        return {'ok': false, 'message': '${info.title}: ${info.copy}'};
      }

      final data = response['data'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(response['data'] as Map)
          : <String, dynamic>{};
      final ride = data['ride'] is Map
          ? Map<String, dynamic>.from(data['ride'] as Map)
          : <String, dynamic>{};
      double asDouble(dynamic v) =>
          v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;
      return {
        'ok': true,
        'adjustedFare': asDouble(
          data['adjustedFare'] ?? data['fare'] ?? ride['fare'],
        ),
        'actualDistance': asDouble(
          data['actualDistance'] ?? ride['actualDistance'],
        ),
        'paymentMethod': _rideData?['paymentMethod'],
      };
    } catch (e) {
      debugPrint('Error ending ride early: $e');
      return {'ok': false, 'message': 'Error ending ride'};
    }
  }

  /// Apply a successful end-early outcome: show adjusted fare + distance,
  /// then route cash rides to collection, others back online.
  void _resolveEndEarlyOutcome(Map<String, dynamic> outcome) {
    final adjustedFare = (outcome['adjustedFare'] as num?)?.toDouble() ?? 0.0;
    final actualDistance =
        (outcome['actualDistance'] as num?)?.toDouble() ?? 0.0;
    final paymentMethod = outcome['paymentMethod'];
    if (!mounted) return;

    if (paymentMethod == 'cash') {
      setState(() {
        _status = 'awaiting_cash_confirmation';
      });
      _persistActiveRide();
      _showEndEarlySummary(
        adjustedFare: adjustedFare,
        actualDistance: actualDistance,
        subline: 'Collect cash from the passenger.',
      );
    } else {
      setState(() {
        _status = 'online';
        _currentRideId = null;
        _rideData = null;
        _clearNavigationUi();
        _clearActiveRideStorage();
      });
      _promoteParkedRequests();
      _fetchRideHistory();
      // payment:succeeded socket will finalize
      _showEndEarlySummary(
        adjustedFare: adjustedFare,
        actualDistance: actualDistance,
        subline: null,
      );
    }
  }

  /// Outcome dialog: adjusted fare + actual distance, never a bare toast.
  void _showEndEarlySummary({
    required double adjustedFare,
    required double actualDistance,
    String? subline,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ride ended early'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Adjusted fare'),
                Text(
                  '£${adjustedFare.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Distance traveled ${actualDistance.toStringAsFixed(1)} mi',
            ),
            if (subline != null) ...[
              const SizedBox(height: 12),
              Text(
                subline,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// One-tap start: backend starts the ride from driver_arrived
  /// state with an empty body. Wrong-state 400s go through RideErrorMapper.
  Future<void> _startRideNoOtp() async {
    if (_currentRideId == null) return;

    try {
      final response = await _apiService.startRide(_currentRideId!);
      if (response['success'] == true) {
        setState(() {
          _status = 'in_progress';
          if (response['data'] != null) {
            final newData = response['data'] as Map<String, dynamic>;
            _rideData = {...?_rideData, ...newData};
          }
        });
        _persistActiveRide();
        CustomSnackbar.show(
          context,
          message: 'Trip Started.',
          type: SnackbarType.success,
        );
        // Fetch navigation route to dropoff
        _fetchNavigationRoute();
      } else {
        if (!mounted) return;
        ErrorDisplayHelper.showRideError(
          context,
          response['message']?.toString() ?? 'Failed to start ride',
          errors: response['errors'],
          onAction: _handleRideAction,
        );
      }
    } catch (e) {
      CustomSnackbar.show(
        context,
        message: 'Error: $e',
        type: SnackbarType.error,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  /// Back-to-back overlay (§5.1 UI rules): pending offer card or docked
  /// next-trip pill, top-anchored above the map. Renders only during busy
  /// statuses — the map polyline/destination and every action button stay
  /// bound to `_currentRideId` (Trip A). Single-queue: offer and pill never
  /// co-exist (new offers drop while `_queuedTrip` is held).
  bool get _showB2bOverlay => shouldShowB2bOverlay(
    hasQueuedTrip: _queuedTrip != null,
    hasOffer: _b2bOffer != null,
    status: _status,
  );

  static String _b2bFareLabel(Map<String, dynamic> trip) {
    final fare = trip['fare'];
    final amount = fare is num
        ? fare.toDouble()
        : double.tryParse(fare?.toString() ?? '');
    return amount == null ? '' : '£${amount.toStringAsFixed(2)}';
  }

  static String _b2bPickupLabel(Map<String, dynamic> trip) {
    return B2bOfferData.fromMap(trip).pickupLabel;
  }

  Widget _buildB2bOfferCard() {
    return B2bOfferCard(
      data: B2bOfferData.fromMap(_b2bOffer ?? const {}),
      busy: _b2bAccepting,
      error: _b2bOfferError,
      driverLat: _currentLocation.latitude,
      driverLng: _currentLocation.longitude,
      onQueue: _acceptB2bOffer,
      onSkip: _declineB2bOffer,
    );
  }

  Widget _buildQueuedPill() {
    final queued = _queuedTrip!;
    final data = B2bOfferData.fromMap(queued);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 16,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Next trip queued',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (data.distanceLabel.isNotEmpty) ...[
                        const Text(
                          '  ·  ',
                          style: TextStyle(color: Colors.black26, fontSize: 12),
                        ),
                        Text(
                          data.distanceLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  _QueuedRouteLine(
                    icon: const Icon(
                      Icons.circle,
                      size: 8,
                      color: AppTheme.primaryColor,
                    ),
                    text: data.pickupLabel,
                  ),
                  const SizedBox(height: 2),
                  _QueuedRouteLine(
                    icon: const Icon(
                      Icons.flag_rounded,
                      size: 12,
                      color: Color(0xFFE23D3D),
                    ),
                    text: data.dropoffLabel,
                  ),
                ],
              ),
            ),
            if (data.hasFare)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 6),
                child: Text(
                  data.fareLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            TextButton(
              onPressed: _showQueuedCancelDialog,
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SlidingUpPanel(
            controller: _panelController,
            minHeight: _getPanelMinHeight(),
            maxHeight: _getPanelMaxHeight(),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            parallaxEnabled: true,
            parallaxOffset: 0.5,
            body: _buildMapBackground(),
            panel: _buildPanelWithQueuedRow(),
            boxShadow: [
              BoxShadow(blurRadius: 20.0, color: Colors.black.withOpacity(0.1)),
            ],
          ),
          // Connection state (19-03): overlay pill above the map, top-center.
          // Renders nothing when live (zero layout shift); never resizes map.
          Positioned(
            top: 56,
            left: 0,
            right: 0,
            child: Center(
              child: ConnectionBanner(rideId: _currentRideId),
            ),
          ),
          // Back-to-back dispatch (20-02): pending offer card or docked
          // next-trip pill. Top-anchored below the connection banner so
          // the sliding panel never fights it; renders nothing when idle.
          if (_showB2bOverlay)
            Positioned(
              top: 104,
              left: 12,
              right: 12,
              child: _b2bOffer != null
                  ? _buildB2bOfferCard()
                  : _buildQueuedPill(),
            ),
        ],
      ),
    );
  }

  double _getPanelMinHeight() {
    switch (_status) {
      case 'offline':
      case 'online':
        return 160;
      case 'request':
        return 320; // Increased to accommodate message banner and prevent overflow
      case 'pickup':
      case 'arrived':
      case 'in_progress':
        return 200;
      case 'complete':
        return 0; // Hidden, overlay takes over
      default:
        return 160;
    }
  }

  double _getPanelMaxHeight() {
    return MediaQuery.of(context).size.height * 0.8;
  }

  Widget _buildMapBackground() {
    if (_isMapLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }

    // Get dynamic destination
    double destLat = 51.5074;
    double destLng = -0.1278;

    if (_rideData != null) {
      if (_status == 'pickup') {
        final coords =
            _rideData!['pickupLocation']?['coordinates'] ?? [0.0, 0.0];
        destLat = coords[1];
        destLng = coords[0];
      } else if (_status == 'in_progress') {
        final coords =
            _rideData!['dropoffLocation']?['coordinates'] ?? [0.0, 0.0];
        destLat = coords[1];
        destLng = coords[0];
      }
    }

    bool isNavigationMode = _status == 'pickup' ||
        _status == 'in_progress' ||
        _status == 'arrived' ||
        _status == 'driver_arrived' ||
        _status == 'at_stop';

    return Stack(
      children: [
        PlatformMap(
          initialLat: _currentLocation.latitude,
          initialLng: _currentLocation.longitude,
          bearing: isNavigationMode ? _currentBearing : 0.0,
          tilt: isNavigationMode ? 45.0 : 0.0,
          markers: [
            MapMarker(
              id: 'driver',
              lat: _currentLocation.latitude,
              lng: _currentLocation.longitude,
              child: const Icon(
                Icons.directions_car,
                color: AppTheme.primaryColor,
                size: 40,
              ),
              title: 'Driver',
            ),
            if (_status == 'pickup' || _status == 'in_progress')
              MapMarker(
                id: _status == 'pickup' ? 'pickup' : 'dropoff',
                lat: destLat,
                lng: destLng,
                child: Icon(
                  Icons.location_on,
                  color: _status == 'pickup' ? Colors.green : Colors.red,
                  size: 40,
                ),
                title: _status == 'pickup' ? 'Pickup' : 'Dropoff',
              ),
            // Numbered intermediate stops during the trip (Uber/Bolt style).
            if (_status == 'in_progress' || _status == 'at_stop')
              ...RouteMapHelpers.stopMarkers(
                parseRideStops(_rideData?['stops']),
                statuses: parseRideStops(
                  _rideData?['stops'],
                ).map((s) => s.status).toList(),
              ),
          ],
          polylines: _navigationPolylines.isNotEmpty
              ? _navigationPolylines
              : [
                  if (_status == 'pickup' || _status == 'in_progress')
                    ...RouteMapHelpers.routePolylines(
                      [
                        _currentLocation,
                        ...RouteMapHelpers.stopPoints(
                          (_status == 'in_progress' || _status == 'at_stop')
                              ? parseRideStops(_rideData?['stops'])
                              : const [],
                        ),
                        LatLng(destLat, destLng),
                      ],
                      color: AppTheme.primaryColor,
                    ),
                ],
        ),

        // Top Bar (Earnings & Status) - Only show when not in full ride flow or make it collapsible
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Earnings Pill
                    // GestureDetector(
                    //   onTap: () =>
                    //       Navigator.pushNamed(context, '/driver-earnings'),
                    //   child: Container(
                    //     padding: const EdgeInsets.symmetric(
                    //       horizontal: 16,
                    //       vertical: 8,
                    //     ),
                    //     decoration: BoxDecoration(
                    //       color: Colors.white,
                    //       borderRadius: BorderRadius.circular(24),
                    //       boxShadow: [
                    //         BoxShadow(
                    //           color: Colors.black.withValues(alpha: 0.1),
                    //           blurRadius: 10,
                    //         ),
                    //       ],
                    //     ),
                    //     child: Row(
                    //       children: [
                    //         Icon(
                    //           Icons.account_balance_wallet,
                    //           color: AppTheme.primaryColor,
                    //         ),
                    //         SizedBox(width: 8),
                    //         Text(
                    //           '£${_todayStats['earnings']}',
                    //           style: GoogleFonts.outfit(
                    //             fontWeight: FontWeight.bold,
                    //             fontSize: 16,
                    //             color: AppTheme.textPrimary,
                    //           ),
                    //         ),
                    //       ],
                    //     ),
                    //   ),
                    // ),

                    // Profile Button
                    CircleAvatar(
                      backgroundColor: Colors.white,
                      child: IconButton(
                        icon: const Icon(Icons.person, color: Colors.black),
                        onPressed: () =>
                            Navigator.pushNamed(context, '/driver-profile'),
                      ),
                    ),
                  ],
                ),
                if (_status == 'online') ...[const SizedBox(height: 16)],
              ],
            ),
          ),
        ),

        // Proximity guidance — persistent until arrival succeeds
        if (_proximityDistance != null &&
            (_status == 'pickup' || _status == 'in_progress'))
          _buildProximityBanner(),

        // Complete Trip Overlay
        if (_status == 'complete')
          Container(
            color: Colors.black.withOpacity(0.7),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(32),
                margin: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Trip Completed!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You earned £${(_rideData?['fare'] ?? 0.0).toStringAsFixed(2)}',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPanelContent() {
    if (_status == 'offline' || _status == 'online') {
      return _buildOfflineOnlineContent();
    } else if (_status == 'request') {
      return DriverRequestPanel(
        rideData: _rideData,
        requests: List<Map<String, dynamic>>.unmodifiable(_requestQueue),
        requestIndex: _requestIndex,
        onSelectRequest: _selectQueuedRequest,
        onAccept: _handleRideAction,
        onDecline: _declineRide,
        isLoading: _isLoading,
        acceptError: _acceptError,
      );
    } else if (_status == 'pickup' ||
        _status == 'arrived' ||
        _status == 'driver_arrived' ||
        _status == 'in_progress' ||
        _status == 'at_stop' ||
        _status == 'awaiting_payment' ||
        _status == 'awaiting_cash_confirmation') {
      final stops = parseRideStops(_rideData?['stops']);
      final stopIndex =
          (_rideData?['currentStopIndex'] as num?)?.toInt() ?? 0;
      final waitMinutes =
          (_rideData?['totalWaitMinutes'] as num?)?.toInt();
      final waitFee = _rideData?['totalWaitFee'] is num
          ? (_rideData!['totalWaitFee'] as num).toDouble()
          : null;
      final farePreview = FareSummary.parse(_rideData).actualFare;
      return DriverNavigationPanel(
        // Backend may report driver_arrived; panel treats it as arrived
        // (same one-tap Start Trip action).
        status: _status == 'driver_arrived' ? 'arrived' : _status,
        rideData: _rideData,
        onAction: _handleRideAction,
        onCancel: _showCancellationReasonDialog,
        onEndEarly: _showEndRideEarlyDialog,
        navigationState: _navigationState,
        isLoading: _isLoading,
        freeWaitLabel: _freeWaitLabel,
        freeWaitMinutes: _freeWaitMinutes,
        perMinuteRate: _freeWaitRate,
        stops: stops,
        currentStopIndex: stopIndex,
        onStopArrive: _handleStopArrive,
        onStopResume: _handleStopResume,
        totalWaitMinutes: waitMinutes,
        totalWaitFee: waitFee,
        farePreview: farePreview > 0 ? farePreview : null,
      );
    } else {
      return _buildOfflineOnlineContent();
    }
  }

  /// Bottom-sheet queued row: the persistent "Next ride queued ✓" strip
  /// pinned at the top of the sliding panel. Renders in every status
  /// (including idle between trips) so the queued trip is never invisible
  /// after the previous trip ends.
  Widget _buildQueuedPanelRow() {
    final queued = _queuedTrip!;
    final fareLabel = _b2bFareLabel(queued);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.06),
        border: Border(
          bottom: BorderSide(
            color: AppTheme.primaryColor.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: AppTheme.primaryColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Next ride queued',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  _b2bPickupLabel(queued),
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (fareLabel.isNotEmpty)
            Text(
              fareLabel,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
          TextButton(
            onPressed: _showQueuedCancelDialog,
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelWithQueuedRow() {
    final content = _buildPanelContent();
    if (_queuedTrip == null) return content;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildQueuedPanelRow(),
        Flexible(child: content),
      ],
    );
  }

  Widget _buildOfflineOnlineContent() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Handle
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Prominent Toggle Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GestureDetector(
              onTap: _toggleOnline,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _status == 'online'
                        ? [Colors.redAccent, Colors.red]
                        : [const Color(0xFFFF6B35), const Color(0xFFFF8E53)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (_status == 'online'
                                  ? Colors.red
                                  : const Color(0xFFFF6B35))
                              .withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Center(
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _status == 'online' ? 'GO OFFLINE' : 'GO ONLINE',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 36),

          // Content section
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Today's Summary Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Today's Summary",
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/driver-ride-history');
                        },
                        child: Text(
                          'See All',
                          style: GoogleFonts.outfit(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Stats row
                  Row(
                    children: [
                      _buildStatCard(
                        'Trips',
                        _todayStats['trips']!,
                        Icons.local_taxi_outlined,
                      ),
                      const SizedBox(width: 16),
                      _buildStatCard(
                        'Hours',
                        _todayStats['hours']!,
                        Icons.access_time_rounded,
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Scheduled Rides Button
                  if (_status == 'online') ...[
                    GestureDetector(
                      onTap: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DriverScheduledRidesScreen(),
                          ),
                        );
                        if (!mounted) return;
                        if (result is Map<String, dynamic> &&
                            result['_id'] != null) {
                          _adoptScheduledRide(result);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primaryColor.withOpacity(0.9),
                              AppTheme.primaryColor,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.calendar_month,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Scheduled Rides',
                                    style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'View requests & confirmed rides',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.white.withOpacity(0.7),
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Recent Activity Header
                  Text(
                    'Recent Activity',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Activity List
                  if (_isHistoryLoading && _recentRides.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_recentRides.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            Icon(
                              Icons.history,
                              size: 48,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No recent rides yet',
                              style: GoogleFonts.outfit(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._recentRides.map((ride) => _buildRideItem(ride)),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Icon(icon, color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRideItem(dynamic ride) {
    final createdAt = DateTime.parse(ride['createdAt']);
    final timeStr = DateFormat('hh:mm a').format(createdAt);
    final isCancelled = ride['status'].toString().contains('cancelled');
    final pickupAddr = ride['pickupLocation']?['address'] ?? 'Unknown Pickup';

    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, '/driver-ride-detail', arguments: ride);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isCancelled
                    ? Colors.red.withOpacity(0.1)
                    : AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.history,
                color: isCancelled ? Colors.red : AppTheme.primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pickupAddr,
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeStr,
                    style: GoogleFonts.outfit(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '£${(ride['fare'] ?? 0.0).toStringAsFixed(2)}',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: isCancelled ? Colors.red : AppTheme.primaryColor,
                  ),
                ),
                if (isCancelled)
                  Text(
                    'Cancelled',
                    style: GoogleFonts.outfit(
                      color: Colors.red,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduledPoolTile(dynamic ride) {
    final pickupTime = ride['scheduledPickupTime']?.toString();
    final pickupAddr = ride['pickupLocation']?['address'] ?? 'Unknown Pickup';
    final dropoffAddr = ride['dropoffLocation']?['address'] ?? '';
    final fare = (ride['fare'] as num?)?.toDouble() ?? 0.0;
    final userName = ride['user']?['name'] ?? 'Passenger';
    final stops = ride['stops'] is List ? ride['stops'] as List : [];
    final distance = (ride['distance'] as num?)?.toDouble() ?? 0.0;
    final isClaiming = _isLoading;

    String timeDisplay = '';
    if (pickupTime != null) {
      try {
        final dt = DateTime.parse(pickupTime).toLocal();
        final now = DateTime.now();
        final diff = dt.difference(now);
        if (diff.inMinutes > 0) {
          if (diff.inHours > 0) {
            timeDisplay = '${diff.inHours}h ${diff.inMinutes % 60}m';
          } else {
            timeDisplay = '${diff.inMinutes}m';
          }
        } else {
          timeDisplay = 'Overdue';
        }
        timeDisplay += ' · ${DateFormat('MMM d, hh:mm a').format(dt)}';
      } catch (_) {
        timeDisplay = pickupTime;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month, color: AppTheme.primaryColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pickupAddr,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '£${fare.toStringAsFixed(2)}',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
          if (dropoffAddr.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '→ $dropoffAddr',
              style: GoogleFonts.outfit(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.person_outline, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(
                userName,
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(width: 12),
              Icon(Icons.directions_car, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(
                '${distance.toStringAsFixed(1)} mi',
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[600]),
              ),
              if (stops.isNotEmpty) ...[
                const SizedBox(width: 12),
                Icon(Icons.stop_circle, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  '${stops.length} stop${stops.length > 1 ? 's' : ''}',
                  style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
              const Spacer(),
              if (timeDisplay.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    timeDisplay,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isClaiming
                  ? null
                  : () => _claimScheduledRide(ride as Map<String, dynamic>),
              icon: isClaiming
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: Text(isClaiming ? 'Claiming...' : 'Claim Ride'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One route line (pickup or dropoff) inside the queued-trip strip.
class _QueuedRouteLine extends StatelessWidget {
  final Widget icon;
  final String text;
  const _QueuedRouteLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 14, height: 14, child: Center(child: icon)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
