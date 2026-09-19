import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/geofence_check.dart';
import '../utils/wifi_check.dart';
import '../utils/vpn_check.dart';

/// Represents the latest cached result of all background credential checks.
class PreVerificationStatus {
  /// True if all enabled checks passed and the result is still valid (within TTL).
  final bool isValid;

  /// The cached GPS position (null if geofence is disabled or check failed).
  final Position? position;

  /// Error message from VPN check (null if passed or disabled).
  final String? vpnError;

  /// Error message from WiFi check (null if passed or disabled).
  final String? wifiError;

  /// The full geo-fence decision (null if not yet checked).
  final GeoFenceDecision? geoDecision;

  /// When this status was last successfully computed.
  final DateTime? timestamp;

  /// Whether a background check is currently running.
  final bool isChecking;

  const PreVerificationStatus({
    this.isValid = false,
    this.position,
    this.vpnError,
    this.wifiError,
    this.geoDecision,
    this.timestamp,
    this.isChecking = false,
  });

  /// Returns true if the cached result is within the given [ttl] window.
  bool isWithinTTL(Duration ttl) {
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp!) < ttl;
  }

  /// A human-readable description of the first error found, or null if all OK.
  String? get firstError => vpnError ?? wifiError ?? geoDecision?.error;

  PreVerificationStatus copyWith({
    bool? isValid,
    Position? position,
    String? vpnError,
    String? wifiError,
    GeoFenceDecision? geoDecision,
    DateTime? timestamp,
    bool? isChecking,
    bool clearVpnError = false,
    bool clearWifiError = false,
    bool clearPosition = false,
    bool clearGeoDecision = false,
  }) {
    return PreVerificationStatus(
      isValid: isValid ?? this.isValid,
      position: clearPosition ? null : (position ?? this.position),
      vpnError: clearVpnError ? null : (vpnError ?? this.vpnError),
      wifiError: clearWifiError ? null : (wifiError ?? this.wifiError),
      geoDecision: clearGeoDecision ? null : (geoDecision ?? this.geoDecision),
      timestamp: timestamp ?? this.timestamp,
      isChecking: isChecking ?? this.isChecking,
    );
  }
}

/// Background service that continuously updates location, geofence, and WiFi
/// status so that face verification can skip those checks and run instantly.
///
/// Usage:
///   // Start on app/dashboard open (called from main.dart after login):
///   PreVerificationService.instance.start();
///
///   // Stop on logout:
///   PreVerificationService.instance.stop();
///
///   // Read the latest cached state:
///   final status = PreVerificationService.instance.status;
///
///   // Listen to changes in the UI:
///   PreVerificationService.instance.statusStream.listen((s) { ... });
class PreVerificationService {
  PreVerificationService._();
  static final PreVerificationService instance = PreVerificationService._();

  // ── Configuration ──────────────────────────────────────────────────────────

  /// How often to re-run all background checks.
  static const Duration _pollInterval = Duration(seconds: 30);

  /// How old a result can be before it is considered stale.
  /// Face verification will fall back to a live check if the result is older.
  static const Duration _ttl = Duration(seconds: 90);

  // ── State ──────────────────────────────────────────────────────────────────

  PreVerificationStatus _status = const PreVerificationStatus();
  final _controller = StreamController<PreVerificationStatus>.broadcast();
  Timer? _timer;
  bool _running = false;
  bool _checkInProgress = false;

  /// Latest cached status.
  PreVerificationStatus get status => _status;

  /// Stream that emits whenever the status is updated.
  Stream<PreVerificationStatus> get statusStream => _controller.stream;

  /// Whether the service is currently running.
  bool get isRunning => _running;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Start the background polling. Safe to call multiple times — idempotent.
  void start() {
    if (_running) return;
    _running = true;
    debugPrint('[PreVerif] Starting background pre-verification service.');
    // Run immediately on start, then keep polling.
    _runChecks();
    _timer = Timer.periodic(_pollInterval, (_) => _runChecks());
  }

  /// Stop the background polling and reset cached state.
  void stop() {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    _status = const PreVerificationStatus();
    if (!_controller.isClosed) {
      _controller.add(_status);
    }
    debugPrint('[PreVerif] Stopped background pre-verification service.');
  }

  /// Force an immediate check cycle (useful right before the face-verify dialog
  /// opens so the user gets the freshest data).
  Future<PreVerificationStatus> forceRefresh() async {
    await _runChecks();
    return _status;
  }

  // ── Core check logic ───────────────────────────────────────────────────────

  Future<void> _runChecks() async {
    if (_checkInProgress) return; // Prevent overlapping runs
    _checkInProgress = true;

    _emit(_status.copyWith(isChecking: true));

    try {
      // Always refresh app-level settings before any check.
      await AppSettings.refreshSettings();

      // ── 1. VPN check ──────────────────────────────────────────────────────
      String? vpnError;
      if (AppSettings.enforceVpnBlocking) {
        vpnError = await VpnChecker.validateVpnStatus();
      }

      // ── 2. WiFi check (native app only — web uses geofence) ──────────────
      String? wifiError;
      if (!kIsWeb && !AppSettings.allowAnyNetwork) {
        wifiError = await WifiChecker.validateCollegeWifi();
      }

      // ── 3. Geofence + location check ──────────────────────────────────────
      final geoDecision = await GeoFenceChecker.checkAttendanceFence();

      // GeoFenceChecker caches the position in lastFetchedPosition whenever
      // it successfully resolves GPS coordinates.
      final position = GeoFenceChecker.lastFetchedPosition;

      // ── Compute overall validity ──────────────────────────────────────────
      final bool valid =
          vpnError == null && wifiError == null && geoDecision.error == null;

      final updated = PreVerificationStatus(
        isValid: valid,
        position: position,
        vpnError: vpnError,
        wifiError: wifiError,
        geoDecision: geoDecision,
        timestamp: DateTime.now(),
        isChecking: false,
      );

      _emit(updated);

      debugPrint(
        '[PreVerif] Check done — valid=$valid | '
        'vpn=${vpnError ?? "ok"} | '
        'wifi=${wifiError ?? "ok"} | '
        'geo=${geoDecision.error ?? "ok"} | '
        'pos=${position != null ? "${position.latitude.toStringAsFixed(5)},${position.longitude.toStringAsFixed(5)}" : "null"}',
      );
    } catch (e) {
      debugPrint('[PreVerif] Error during background check: $e');
      // Keep previous status but clear the "checking" flag.
      _emit(_status.copyWith(isChecking: false));
    } finally {
      _checkInProgress = false;
    }
  }

  void _emit(PreVerificationStatus s) {
    _status = s;
    if (!_controller.isClosed) {
      _controller.add(s);
    }
  }

  // ── Consumption helper ─────────────────────────────────────────────────────

  /// Returns the cached status if it is still within [_ttl].
  /// If stale or empty, triggers a fresh synchronous check and returns the result.
  ///
  /// Call this from [_verifyFace] / [verifyAndMarkAttendance] instead of
  /// running VPN + WiFi + Geofence checks inline.
  Future<PreVerificationStatus> getOrRefresh() async {
    if (_status.isWithinTTL(_ttl)) {
      final age = DateTime.now().difference(_status.timestamp!).inSeconds;
      debugPrint('[PreVerif] Using most recent cached credentials instantly (age=${age}s).');
      return _status;
    }
    debugPrint('[PreVerif] Cache empty or stale — running fresh check before face-verify.');
    return await forceRefresh();
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

