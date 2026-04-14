// ignore_for_file: unused_field

import 'dart:async';

import 'package:achievr_app/Services/app_clock.dart';
import 'package:achievr_app/Services/app_policy_service.dart';
import 'package:achievr_app/Services/device_runtime_service.dart';
import 'package:achievr_app/Services/focus_runtime_service.dart';
import 'package:achievr_app/Services/location_runtime_service.dart';
import 'package:achievr_app/Services/verification_service.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

class GlobalFocusSessionController extends ChangeNotifier
    with WidgetsBindingObserver {
  GlobalFocusSessionController({
    FocusRuntimeService? focusRuntimeService,
    VerificationService? verificationService,
    AppPolicyService? appPolicyService,
    DeviceRuntimeService? deviceRuntimeService,
    LocationRuntimeService? locationRuntimeService,
  })  : _focusRuntimeService = focusRuntimeService ?? FocusRuntimeService(),
        _verificationService = verificationService ?? VerificationService(),
        _appPolicyService = appPolicyService ?? AppPolicyService(),
        _deviceRuntimeService = deviceRuntimeService ?? DeviceRuntimeService(),
        _locationRuntimeService =
            locationRuntimeService ?? LocationRuntimeService() {
    WidgetsBinding.instance.addObserver(this);
    _lastLifecycleState = AppLifecycleState.resumed;
    _startUiTimer();
  }

  final FocusRuntimeService _focusRuntimeService;
  final VerificationService _verificationService;
  final AppPolicyService _appPolicyService;
  final DeviceRuntimeService _deviceRuntimeService;
  final LocationRuntimeService _locationRuntimeService;

  static const Set<String> _achievrAppIds = {
    'com.example.achievr_app',
    'com.achievr.app',
    'achievr',
  };

  static const Duration _backendSyncInterval = Duration(seconds: 10);
  static const Duration _locationRefreshInterval = Duration(minutes: 2);

  StreamSubscription<DeviceRuntimeSnapshot>? _runtimeSub;
  Timer? _uiTimer;

  DeviceRuntimeSnapshot? _latestRuntimeSnapshot;
  Position? _latestPosition;
  DateTime _now = AppClock.now();
  DateTime? _lastBackendSyncAt;
  DateTime? _lastLocationRefreshAt;
  AppLifecycleState? _lastLifecycleState;

  bool _usageAccessReady = false;
  bool _locationPermissionReady = false;
  bool _deviceMonitoringStarted = false;
  bool _localGraceActive = false;

  String? _error;
  String? _syncWarning;
  String? _localGraceReason;

  Map<String, dynamic>? _session;
  Map<String, dynamic>? _habit;
  Map<String, dynamic>? _appPolicySnapshot;
  Map<String, dynamic>? _locationConfig;
  Map<String, dynamic>? _currentLog;

  bool get hasSession => _session != null;

  bool get hasLiveSession {
    if (_session == null) return false;
    final status = (_session!['status'] ?? '').toString();
    return status == 'running' || status == 'paused' || status == 'grace';
  }

  bool get localGraceActive => _localGraceActive;
  String? get localGraceReason => _localGraceReason;
  String? get error => _error;
  String? get syncWarning => _syncWarning;
  Map<String, dynamic>? get session => _session;
  Map<String, dynamic>? get habit => _habit;
  Map<String, dynamic>? get currentLog => _currentLog;
  bool get usageAccessReady => _usageAccessReady;
  bool get locationPermissionReady => _locationPermissionReady;

  String get status => (_session?['status'] ?? '').toString();

  int _coerceInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool get needsLocation =>
      ((_habit?['verification_type'] ?? '').toString()).contains('location');

  int get validFocusSeconds => _coerceInt(_session?['valid_focus_seconds']);
  int get graceSecondsUsed => _coerceInt(_session?['grace_seconds_used']);

  int get leaveGraceSeconds {
    final value = _coerceInt(_appPolicySnapshot?['leave_grace_seconds']);
    return value <= 0 ? 30 : value;
  }

  int get displayedGraceRemaining {
    final remaining = leaveGraceSeconds - graceSecondsUsed;
    return remaining < 0 ? 0 : remaining;
  }

  String get habitTitle {
    final nestedHabit = _currentLog?['habits'];
    if (nestedHabit is Map<String, dynamic>) {
      return (nestedHabit['title'] ?? 'Focus task').toString();
    }
    if (nestedHabit is Map) {
      return (nestedHabit['title'] ?? 'Focus task').toString();
    }
    return (_currentLog?['habit_title'] ?? 'Focus task').toString();
  }

  String? get focusSessionId => _session?['focus_session_id']?.toString();

  String? get habitId {
    final nestedHabit = _currentLog?['habits'];
    if (nestedHabit is Map<String, dynamic>) {
      return nestedHabit['habit_id']?.toString();
    }
    if (nestedHabit is Map) {
      return nestedHabit['habit_id']?.toString();
    }
    return _currentLog?['habit_id']?.toString();
  }

  String? get logId => _currentLog?['log_id']?.toString();

  bool get _isAchievrScreenActive =>
      _lastLifecycleState == null ||
      _lastLifecycleState == AppLifecycleState.resumed;

  bool get _screenOffAllowed =>
      (_appPolicySnapshot?['allow_screen_off'] as bool?) ?? true;

  Set<String> get _resolvedAllowedAppIds {
    final ids = <String>{..._achievrAppIds};

    final fromSnapshot =
        (_appPolicySnapshot?['allowed_app_identifiers'] as List<dynamic>? ?? [])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty);

    ids.addAll(fromSnapshot);
    return ids;
  }

  double? get _targetLatitude {
    final value = _locationConfig?['latitude'];
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  double? get _targetLongitude {
    final value = _locationConfig?['longitude'];
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  double? get _distanceToTargetMeters {
    final current = _latestPosition;
    final targetLat = _targetLatitude;
    final targetLng = _targetLongitude;

    if (current == null || targetLat == null || targetLng == null) return null;

    return Geolocator.distanceBetween(
      current.latitude,
      current.longitude,
      targetLat,
      targetLng,
    );
  }

  bool? get _insidePinnedRadius {
    final distance = _distanceToTargetMeters;
    final radius = _locationConfig?['radius_meters'];
    final radiusValue =
        radius is int ? radius.toDouble() : double.tryParse('${radius ?? ''}');

    if (distance == null || radiusValue == null) return null;
    return distance <= radiusValue;
  }

  String _effectiveForegroundAppId(DeviceRuntimeSnapshot event) {
    final raw = event.foregroundAppIdentifier?.trim();

    if (raw != null && raw.isNotEmpty) return raw;

    if (_isAchievrScreenActive) {
      return 'com.example.achievr_app';
    }

    return 'unknown_foreground_app';
  }

  bool _isAppContextAllowed(DeviceRuntimeSnapshot event) {
    if (event.isScreenOff) {
      return _screenOffAllowed;
    }

    final foreground = _effectiveForegroundAppId(event);

    if (_achievrAppIds.contains(foreground)) {
      return true;
    }

    return _resolvedAllowedAppIds.contains(foreground);
  }

  bool _isLocationContextAllowed() {
    if (!needsLocation) return true;
    final inside = _insidePinnedRadius;
    return inside != false;
  }

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _now = AppClock.now();
      _applyLocalRealtimeTick();
      notifyListeners();
    });
  }

  void _applyLocalRealtimeTick() {
    if (!hasLiveSession) return;
    if (_session == null) return;

    final status = (_session?['status'] ?? '').toString();
    if (status == 'completed' ||
        status == 'failed' ||
        status == 'abandoned' ||
        status == 'invalidated') {
      return;
    }

    final event = _latestRuntimeSnapshot;

    if (event == null) {
      final currentValid = _coerceInt(_session?['valid_focus_seconds']);
      _session = {
        ..._session!,
        'status': 'running',
        'valid_focus_seconds': currentValid + 1,
      };
      _localGraceActive = false;
      _localGraceReason = null;
      return;
    }

    final appAllowed = _isAppContextAllowed(event);
    final locationAllowed = _isLocationContextAllowed();
    final isAllowed = appAllowed && locationAllowed;

    if (isAllowed) {
      final currentValid = _coerceInt(_session?['valid_focus_seconds']);
      _session = {
        ..._session!,
        'status': 'running',
        'valid_focus_seconds': currentValid + 1,
      };
      _localGraceActive = false;
      _localGraceReason = null;
      return;
    }

    final currentGrace = _coerceInt(_session?['grace_seconds_used']);
    final nextGrace = currentGrace + 1;

    _session = {
      ..._session!,
      'status': 'grace',
      'grace_seconds_used': nextGrace,
    };

    _localGraceActive = true;
    _localGraceReason = !appAllowed
        ? 'You left the allowed app.'
        : 'You left the required location.';
  }

  Future<void> attachToLog(Map<String, dynamic> log) async {
    _currentLog = Map<String, dynamic>.from(log);
    await _boot();
  }

  Future<void> _boot() async {
    final currentHabitId = habitId;
    final currentLogId = logId;

    if (currentHabitId == null || currentLogId == null) {
      _error = 'This log is missing habit or log identifiers.';
      notifyListeners();
      return;
    }

    try {
      final habit =
          await _verificationService.fetchHabitById(habitId: currentHabitId);
      final latestSession = await _focusRuntimeService
          .getLatestFocusSessionForLog(logId: currentLogId);

      Map<String, dynamic>? appPolicySnapshot;
      Map<String, dynamic>? locationConfig;

      try {
        appPolicySnapshot =
            await _appPolicyService.buildFocusSessionPolicySnapshot(
          habitId: currentHabitId,
        );
      } catch (_) {
        appPolicySnapshot = null;
      }

      try {
        locationConfig =
            await _verificationService.fetchHabitLocationConfig(
          habitId: currentHabitId,
        );
      } catch (_) {
        locationConfig = null;
      }

      _habit = habit;
      _session = latestSession;
      _appPolicySnapshot = appPolicySnapshot;
      _locationConfig = locationConfig;

      await _prepareDeviceMonitoring();
      await _prepareLocationTracking(forceRefresh: true);
      await _reattachToActiveMonitoringIfNeeded();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load focus mode.\n$e';
      notifyListeners();
    }
  }

  Future<void> _prepareDeviceMonitoring() async {
    try {
      final hasAccess = await _deviceRuntimeService.hasUsageAccess();
      _usageAccessReady = hasAccess;
    } catch (_) {
      _usageAccessReady = false;
    }
  }

  Future<void> _prepareLocationTracking({
    bool forceRefresh = false,
  }) async {
    if (!needsLocation) return;

    try {
      final enabled = await _locationRuntimeService.isServiceEnabled();
      if (!enabled) {
        _locationPermissionReady = false;
        _error = 'Location is off. Configure this in Verification.';
        return;
      }

      var permission = await _locationRuntimeService.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _locationRuntimeService.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _locationPermissionReady = false;
        _error =
            'Location permission is missing. Configure this in Verification.';
        return;
      }

      if (forceRefresh || _latestPosition == null) {
        await _refreshCurrentPosition();
      }

      _locationPermissionReady = true;
    } catch (e) {
      _locationPermissionReady = false;
      _error = 'Could not prepare location.\n$e';
    }
  }

  Future<void> _refreshCurrentPosition() async {
    final current = await _locationRuntimeService.getCurrentPosition();
    _latestPosition = current;
    _lastLocationRefreshAt = DateTime.now();
  }

  Future<void> _reattachToActiveMonitoringIfNeeded() async {
    if (!_usageAccessReady) return;
    if (!hasLiveSession) return;
    if (_deviceMonitoringStarted) return;

    await _attachRuntimeListenerOnly();
  }

  Future<void> _attachRuntimeListenerOnly() async {
    await _runtimeSub?.cancel();

    _runtimeSub = _deviceRuntimeService.runtimeStream().listen(
      (event) async {
        _latestRuntimeSnapshot = event;
        notifyListeners();

        final sessionId = _session?['focus_session_id']?.toString();
        if (sessionId == null || !hasLiveSession) {
          return;
        }

        final now = DateTime.now();

        if (needsLocation) {
          final shouldRefreshLocation = _lastLocationRefreshAt == null ||
              now.difference(_lastLocationRefreshAt!) >=
                  _locationRefreshInterval;

          if (shouldRefreshLocation) {
            try {
              await _refreshCurrentPosition();
            } catch (_) {}
          }
        }

        final appAllowed = _isAppContextAllowed(event);
        final locationAllowed = _isLocationContextAllowed();
        final violationNow = !(appAllowed && locationAllowed);

        if (violationNow && !_localGraceActive) {
          _localGraceActive = true;
          _localGraceReason = !appAllowed
              ? 'You left the allowed app.'
              : 'You left the required location.';
          notifyListeners();
        } else if (!violationNow && _localGraceActive) {
          _localGraceActive = false;
          _localGraceReason = null;
          notifyListeners();
        }

        final shouldSyncNow = _lastBackendSyncAt == null ||
            now.difference(_lastBackendSyncAt!) >= _backendSyncInterval ||
            violationNow ||
            _syncWarning != null;

        if (!shouldSyncNow) return;

        final elapsed = _lastBackendSyncAt == null
            ? 1
            : now.difference(_lastBackendSyncAt!).inSeconds.clamp(1, 60);

        try {
          final updated = await _focusRuntimeService.tickFocusSession(
            focusSessionId: sessionId,
            foregroundAppIdentifier: _effectiveForegroundAppId(event),
            isScreenOff: event.isScreenOff,
            elapsedSinceLastTickSeconds: elapsed,
            currentLatitude: _latestPosition?.latitude,
            currentLongitude: _latestPosition?.longitude,
          );

          _session = updated;
          _lastBackendSyncAt = now;
          _syncWarning = null;

          if (!hasLiveSession) {
            _deviceMonitoringStarted = false;
          }

          notifyListeners();
        } catch (e) {
          final text = e.toString().toLowerCase();
          final isTransientGatewayError =
              text.contains('502') || text.contains('bad gateway');

          _syncWarning = isTransientGatewayError
              ? 'Temporary sync issue. Monitoring will retry.'
              : 'Runtime sync issue. Monitoring will retry.';
          notifyListeners();
        }
      },
    );

    _deviceMonitoringStarted = true;
    notifyListeners();
  }

  Future<void> startForLog(Map<String, dynamic> log) async {
    _currentLog = Map<String, dynamic>.from(log);
    await _boot();

    final currentHabitId = habitId;
    final currentLogId = logId;

    if (currentHabitId == null || currentLogId == null) return;

    final started = await _focusRuntimeService.startFocusSession(
      logId: currentLogId,
      habitId: currentHabitId,
      currentLatitude: _latestPosition?.latitude,
      currentLongitude: _latestPosition?.longitude,
      initialForegroundAppIdentifier: 'com.example.achievr_app',
      isScreenOff: false,
    );

    _session = started;
    _lastBackendSyncAt = DateTime.now();
    _localGraceActive = false;
    _localGraceReason = null;
    notifyListeners();

    await _startRuntimeStream();
  }

  Future<void> _startRuntimeStream() async {
    if (!_usageAccessReady || _deviceMonitoringStarted) return;

    final currentHabitId = habitId;
    if (currentHabitId == null) return;

    final snapshot = _appPolicySnapshot ??
        await _appPolicyService.buildFocusSessionPolicySnapshot(
          habitId: currentHabitId,
        );

    final allowedApps =
        (snapshot['allowed_app_identifiers'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();

    await _deviceRuntimeService.startMonitoring(
      allowedAppIdentifiers: allowedApps,
      allowScreenOff: (snapshot['allow_screen_off'] as bool?) ?? true,
      pollIntervalMs: 1000,
      focusSessionId: _session?['focus_session_id']?.toString(),
      habitId: currentHabitId,
      logId: logId,
      graceSeconds: _coerceInt(snapshot['leave_grace_seconds']),
    );

    await _attachRuntimeListenerOnly();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastLifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _prepareDeviceMonitoring();
      if (needsLocation) {
        _prepareLocationTracking(forceRefresh: true);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiTimer?.cancel();
    _runtimeSub?.cancel();

    if (!hasLiveSession) {
      _deviceRuntimeService.stopMonitoring();
      _locationRuntimeService.stop();
    }

    super.dispose();
  }
}