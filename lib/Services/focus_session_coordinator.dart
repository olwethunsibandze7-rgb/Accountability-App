import 'dart:async';

import 'package:achievr_app/Services/app_policy_service.dart';
import 'package:achievr_app/Services/device_runtime_service.dart';
import 'package:achievr_app/Services/focus_runtime_service.dart';
import 'package:achievr_app/Services/location_runtime_service.dart';
import 'package:achievr_app/Services/verification_service.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

class FocusSessionViewState {
  final bool isInitialized;
  final bool isLoading;
  final bool hasLiveSession;

  final String? focusSessionId;
  final String? logId;
  final String? habitId;

  final String status;
  final int validFocusSeconds;
  final int graceSecondsUsed;
  final int graceSecondsAllowed;

  final int appViolationCount;
  final int locationViolationCount;

  final bool appAllowed;
  final bool locationAllowed;
  final bool isScreenOff;
  final bool usageAccessReady;
  final bool locationPermissionReady;

  final String? foregroundAppIdentifier;
  final String? localGraceReason;
  final String? error;
  final String? syncWarning;

  final Map<String, dynamic>? log;
  final Map<String, dynamic>? session;
  final Map<String, dynamic>? habit;
  final Map<String, dynamic>? policySnapshot;
  final Map<String, dynamic>? locationConfig;
  final Position? latestPosition;

  const FocusSessionViewState({
    required this.isInitialized,
    required this.isLoading,
    required this.hasLiveSession,
    required this.focusSessionId,
    required this.logId,
    required this.habitId,
    required this.status,
    required this.validFocusSeconds,
    required this.graceSecondsUsed,
    required this.graceSecondsAllowed,
    required this.appViolationCount,
    required this.locationViolationCount,
    required this.appAllowed,
    required this.locationAllowed,
    required this.isScreenOff,
    required this.usageAccessReady,
    required this.locationPermissionReady,
    required this.foregroundAppIdentifier,
    required this.localGraceReason,
    required this.error,
    required this.syncWarning,
    required this.log,
    required this.session,
    required this.habit,
    required this.policySnapshot,
    required this.locationConfig,
    required this.latestPosition,
  });

  factory FocusSessionViewState.initial() {
    return const FocusSessionViewState(
      isInitialized: false,
      isLoading: false,
      hasLiveSession: false,
      focusSessionId: null,
      logId: null,
      habitId: null,
      status: '',
      validFocusSeconds: 0,
      graceSecondsUsed: 0,
      graceSecondsAllowed: 30,
      appViolationCount: 0,
      locationViolationCount: 0,
      appAllowed: true,
      locationAllowed: true,
      isScreenOff: false,
      usageAccessReady: false,
      locationPermissionReady: false,
      foregroundAppIdentifier: null,
      localGraceReason: null,
      error: null,
      syncWarning: null,
      log: null,
      session: null,
      habit: null,
      policySnapshot: null,
      locationConfig: null,
      latestPosition: null,
    );
  }

  FocusSessionViewState copyWith({
    bool? isInitialized,
    bool? isLoading,
    bool? hasLiveSession,
    String? focusSessionId,
    String? logId,
    String? habitId,
    String? status,
    int? validFocusSeconds,
    int? graceSecondsUsed,
    int? graceSecondsAllowed,
    int? appViolationCount,
    int? locationViolationCount,
    bool? appAllowed,
    bool? locationAllowed,
    bool? isScreenOff,
    bool? usageAccessReady,
    bool? locationPermissionReady,
    String? foregroundAppIdentifier,
    String? localGraceReason,
    String? error,
    String? syncWarning,
    Map<String, dynamic>? log,
    Map<String, dynamic>? session,
    Map<String, dynamic>? habit,
    Map<String, dynamic>? policySnapshot,
    Map<String, dynamic>? locationConfig,
    Position? latestPosition,
  }) {
    return FocusSessionViewState(
      isInitialized: isInitialized ?? this.isInitialized,
      isLoading: isLoading ?? this.isLoading,
      hasLiveSession: hasLiveSession ?? this.hasLiveSession,
      focusSessionId: focusSessionId ?? this.focusSessionId,
      logId: logId ?? this.logId,
      habitId: habitId ?? this.habitId,
      status: status ?? this.status,
      validFocusSeconds: validFocusSeconds ?? this.validFocusSeconds,
      graceSecondsUsed: graceSecondsUsed ?? this.graceSecondsUsed,
      graceSecondsAllowed: graceSecondsAllowed ?? this.graceSecondsAllowed,
      appViolationCount: appViolationCount ?? this.appViolationCount,
      locationViolationCount:
          locationViolationCount ?? this.locationViolationCount,
      appAllowed: appAllowed ?? this.appAllowed,
      locationAllowed: locationAllowed ?? this.locationAllowed,
      isScreenOff: isScreenOff ?? this.isScreenOff,
      usageAccessReady: usageAccessReady ?? this.usageAccessReady,
      locationPermissionReady:
          locationPermissionReady ?? this.locationPermissionReady,
      foregroundAppIdentifier:
          foregroundAppIdentifier ?? this.foregroundAppIdentifier,
      localGraceReason: localGraceReason ?? this.localGraceReason,
      error: error ?? this.error,
      syncWarning: syncWarning ?? this.syncWarning,
      log: log ?? this.log,
      session: session ?? this.session,
      habit: habit ?? this.habit,
      policySnapshot: policySnapshot ?? this.policySnapshot,
      locationConfig: locationConfig ?? this.locationConfig,
      latestPosition: latestPosition ?? this.latestPosition,
    );
  }
}

class FocusSessionCoordinator extends ChangeNotifier
    with WidgetsBindingObserver {
  FocusSessionCoordinator({
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
    _state = FocusSessionViewState.initial();
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

  static const Duration _uiTickInterval = Duration(seconds: 1);
  static const Duration _backendSyncInterval = Duration(seconds: 12);
  static const Duration _locationRefreshInterval = Duration(minutes: 2);
  static const Duration _violationDebounce = Duration(seconds: 2);

  late FocusSessionViewState _state;
  FocusSessionViewState get state => _state;

  StreamSubscription<DeviceRuntimeSnapshot>? _runtimeSub;
  Timer? _uiTimer;

  DeviceRuntimeSnapshot? _latestRuntimeSnapshot;
  DateTime? _lastBackendSyncAt;
  DateTime? _lastLocationRefreshAt;
  AppLifecycleState? _lastLifecycleState;

  int _displayValidBase = 0;
  int _displayGraceBase = 0;
  int _displayValidOffset = 0;
  int _displayGraceOffset = 0;

  int _localAppViolationCount = 0;
  int _localLocationViolationCount = 0;

  DateTime? _lastAccountedAt;
  String _currentAccumulationMode = 'running';

  DateTime? _pendingViolationSince;
  bool _pendingViolationCommitted = false;
  bool _pendingViolationApp = false;
  bool _pendingViolationLocation = false;
  String? _pendingViolationReason;

  String? _extractHabitIdFromLog(Map<String, dynamic>? log) {
    if (log == null) return null;

    final nestedHabit = log['habits'];
    if (nestedHabit is Map<String, dynamic>) {
      return nestedHabit['habit_id']?.toString();
    }
    if (nestedHabit is Map) {
      return nestedHabit['habit_id']?.toString();
    }
    return log['habit_id']?.toString();
  }

  int _coerceInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _isLiveSession(Map<String, dynamic>? session) {
    if (session == null) return false;
    final status = (session['status'] ?? '').toString();
    return status == 'running' || status == 'paused' || status == 'grace';
  }

  bool _needsLocation(Map<String, dynamic>? habit) {
    return ((habit?['verification_type'] ?? '').toString()).contains('location');
  }

  Set<String> _resolvedAllowedAppIds(Map<String, dynamic>? policySnapshot) {
    final ids = <String>{..._achievrAppIds};
    final raw =
        (policySnapshot?['allowed_app_identifiers'] as List<dynamic>? ?? [])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty);
    ids.addAll(raw);
    return ids;
  }

  bool _screenOffAllowed(Map<String, dynamic>? policySnapshot) {
    return (policySnapshot?['allow_screen_off'] as bool?) ?? true;
  }

  String _effectiveForegroundAppId(DeviceRuntimeSnapshot? event) {
    final raw = event?.foregroundAppIdentifier?.trim();
    if (raw != null && raw.isNotEmpty) return raw;

    final isAchievrForeground = _lastLifecycleState == null ||
        _lastLifecycleState == AppLifecycleState.resumed;

    if (isAchievrForeground) {
      return 'com.example.achievr_app';
    }

    return 'unknown_foreground_app';
  }

  bool _computeAppAllowed() {
    final event = _latestRuntimeSnapshot;
    if (event == null) return true;

    if (event.isScreenOff) {
      return _screenOffAllowed(_state.policySnapshot);
    }

    final foreground = _effectiveForegroundAppId(event);

    if (_achievrAppIds.contains(foreground)) return true;

    return _resolvedAllowedAppIds(_state.policySnapshot).contains(foreground);
  }

  bool _computeLocationAllowed() {
    if (!_needsLocation(_state.habit)) return true;

    final position = _state.latestPosition;
    final config = _state.locationConfig;

    if (position == null || config == null) return false;

    final lat = config['latitude'];
    final lng = config['longitude'];
    final radius = config['radius_meters'];

    final targetLat = lat is double ? lat : double.tryParse('$lat');
    final targetLng = lng is double ? lng : double.tryParse('$lng');
    final radiusMeters =
        radius is int ? radius.toDouble() : double.tryParse('$radius');

    if (targetLat == null || targetLng == null || radiusMeters == null) {
      return false;
    }

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      targetLat,
      targetLng,
    );

    return distance <= radiusMeters;
  }

  void _emit() => notifyListeners();

  int _effectiveValidSeconds() => _displayValidBase + _displayValidOffset;
  int _effectiveGraceSeconds() => _displayGraceBase + _displayGraceOffset;

  void _setMonotonicBasesFromSession(Map<String, dynamic>? session) {
    final serverValid = _coerceInt(session?['valid_focus_seconds']);
    final serverGrace = _coerceInt(session?['grace_seconds_used']);

    final currentValid = _effectiveValidSeconds();
    final currentGrace = _effectiveGraceSeconds();

    _displayValidBase = serverValid > currentValid ? serverValid : currentValid;
    _displayGraceBase = serverGrace > currentGrace ? serverGrace : currentGrace;

    _displayValidOffset = 0;
    _displayGraceOffset = 0;

    final serverAppViolations = _coerceInt(session?['app_violation_count']);
    final serverLocationViolations =
        _coerceInt(session?['location_violation_count']);

    if (serverAppViolations > _localAppViolationCount) {
      _localAppViolationCount = serverAppViolations;
    }
    if (serverLocationViolations > _localLocationViolationCount) {
      _localLocationViolationCount = serverLocationViolations;
    }
  }

  void _resetElapsedAnchors({
    required DateTime now,
    required bool shouldCountAsRunning,
  }) {
    _lastAccountedAt = now;
    _currentAccumulationMode = shouldCountAsRunning ? 'running' : 'grace';
  }

  void _applyElapsedAccounting({
    required DateTime now,
    required bool shouldCountAsRunning,
  }) {
    if (!_state.hasLiveSession) {
      _lastAccountedAt = now;
      _currentAccumulationMode = shouldCountAsRunning ? 'running' : 'grace';
      return;
    }

    _lastAccountedAt ??= now;

    final elapsed = now.difference(_lastAccountedAt!).inSeconds;
    if (elapsed <= 0) {
      _currentAccumulationMode = shouldCountAsRunning ? 'running' : 'grace';
      return;
    }

    if (_currentAccumulationMode == 'running') {
      _displayValidOffset += elapsed;
    } else {
      _displayGraceOffset += elapsed;
    }

    _lastAccountedAt = now;
    _currentAccumulationMode = shouldCountAsRunning ? 'running' : 'grace';
  }

  void _updateViolationDebounce({
    required DateTime now,
    required bool rawAppAllowed,
    required bool rawLocationAllowed,
  }) {
    final rawAllowed = rawAppAllowed && rawLocationAllowed;

    if (rawAllowed) {
      _pendingViolationSince = null;
      _pendingViolationCommitted = false;
      _pendingViolationApp = false;
      _pendingViolationLocation = false;
      _pendingViolationReason = null;
      return;
    }

    if (_pendingViolationSince == null) {
      _pendingViolationSince = now;
      _pendingViolationCommitted = false;
      _pendingViolationApp = !rawAppAllowed;
      _pendingViolationLocation = !rawLocationAllowed;
      _pendingViolationReason = !rawAppAllowed
          ? 'You left the allowed app.'
          : 'You left the required location.';
      return;
    }

    _pendingViolationApp = _pendingViolationApp || !rawAppAllowed;
    _pendingViolationLocation = _pendingViolationLocation || !rawLocationAllowed;
    _pendingViolationReason = !rawAppAllowed
        ? 'You left the allowed app.'
        : 'You left the required location.';

    final elapsed = now.difference(_pendingViolationSince!);
    if (!_pendingViolationCommitted && elapsed >= _violationDebounce) {
      if (_pendingViolationApp) {
        _localAppViolationCount += 1;
      }
      if (_pendingViolationLocation) {
        _localLocationViolationCount += 1;
      }
      _pendingViolationCommitted = true;
    }
  }

  bool _isGraceCommitted(DateTime now) {
    if (_pendingViolationSince == null) return false;
    return now.difference(_pendingViolationSince!) >= _violationDebounce;
  }

  bool _shouldCountAsRunning(DateTime now) {
    return !_isGraceCommitted(now);
  }

  String _effectiveStatus(DateTime now) {
    return _shouldCountAsRunning(now) ? 'running' : 'grace';
  }

  String? _effectiveGraceReason(DateTime now) {
    if (_shouldCountAsRunning(now)) return null;
    return _pendingViolationReason;
  }

  void _rebuildStateFromSession({
    required DateTime now,
    Map<String, dynamic>? session,
    Map<String, dynamic>? habit,
    Map<String, dynamic>? policySnapshot,
    Map<String, dynamic>? locationConfig,
    Map<String, dynamic>? log,
    Position? latestPosition,
    String? error,
    String? syncWarning,
    bool? forcedRawAppAllowed,
    bool? forcedRawLocationAllowed,
  }) {
    final activeSession = session ?? _state.session;
    final resolvedHabit = habit ?? _state.habit;
    final resolvedPolicy = policySnapshot ?? _state.policySnapshot;
    final resolvedLocation = locationConfig ?? _state.locationConfig;
    final resolvedLog = log ?? _state.log;
    final resolvedPosition = latestPosition ?? _state.latestPosition;

    final rawAppAllowed = forcedRawAppAllowed ?? _computeAppAllowed();
    final rawLocationAllowed = forcedRawLocationAllowed ?? _computeLocationAllowed();

    final serverAppViolations = _coerceInt(activeSession?['app_violation_count']);
    final serverLocationViolations =
        _coerceInt(activeSession?['location_violation_count']);

    final effectiveAppViolations =
        _localAppViolationCount > serverAppViolations
            ? _localAppViolationCount
            : serverAppViolations;

    final effectiveLocationViolations =
        _localLocationViolationCount > serverLocationViolations
            ? _localLocationViolationCount
            : serverLocationViolations;

    _state = _state.copyWith(
      isInitialized: true,
      isLoading: false,
      hasLiveSession: _isLiveSession(activeSession),
      focusSessionId: activeSession?['focus_session_id']?.toString(),
      logId: resolvedLog?['log_id']?.toString(),
      habitId: _extractHabitIdFromLog(resolvedLog),
      status: _isLiveSession(activeSession)
          ? _effectiveStatus(now)
          : (activeSession?['status'] ?? '').toString(),
      validFocusSeconds: _effectiveValidSeconds(),
      graceSecondsUsed: _effectiveGraceSeconds(),
      graceSecondsAllowed: (() {
        final v = _coerceInt(resolvedPolicy?['leave_grace_seconds']);
        return v <= 0 ? 30 : v;
      })(),
      appViolationCount: effectiveAppViolations,
      locationViolationCount: effectiveLocationViolations,
      appAllowed: rawAppAllowed,
      locationAllowed: rawLocationAllowed,
      isScreenOff: _latestRuntimeSnapshot?.isScreenOff ?? false,
      usageAccessReady: _state.usageAccessReady,
      locationPermissionReady: _state.locationPermissionReady,
      foregroundAppIdentifier: _effectiveForegroundAppId(_latestRuntimeSnapshot),
      localGraceReason: _effectiveGraceReason(now),
      error: error ?? _state.error,
      syncWarning: syncWarning ?? _state.syncWarning,
      log: resolvedLog,
      session: activeSession,
      habit: resolvedHabit,
      policySnapshot: resolvedPolicy,
      locationConfig: resolvedLocation,
      latestPosition: resolvedPosition,
    );
  }

  bool isSameActiveLog(String? logId) {
    if (logId == null) return false;
    return _state.hasLiveSession && _state.logId == logId;
  }

  Future<void> initialize() async {
    if (_state.isInitialized) return;

    _lastLifecycleState = AppLifecycleState.resumed;
    _state = _state.copyWith(isInitialized: true);
    _startUiTicker();
    _emit();
  }

  Future<void> ensureMonitoringStarted() async {
    if (!_state.usageAccessReady) return;
    if (!_state.hasLiveSession) return;
    if (_state.focusSessionId == null || _state.habitId == null) return;

    final snapshot = _state.policySnapshot ??
        await _appPolicyService.buildFocusSessionPolicySnapshot(
          habitId: _state.habitId!,
        );

    final allowedApps =
        (snapshot['allowed_app_identifiers'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();

    await _deviceRuntimeService.startMonitoring(
      allowedAppIdentifiers: allowedApps,
      allowScreenOff: (snapshot['allow_screen_off'] as bool?) ?? true,
      pollIntervalMs: 1000,
      focusSessionId: _state.focusSessionId,
      habitId: _state.habitId,
      logId: _state.logId,
      graceSeconds: _coerceInt(snapshot['leave_grace_seconds']),
    );

    await _attachRuntimeListener();
  }

  Future<void> attachToLog(Map<String, dynamic> log) async {
    await initialize();

    final requestedLogId = log['log_id']?.toString();
    final currentLogId = _state.logId;
    final sameLogAsCurrent =
        requestedLogId != null && requestedLogId == currentLogId;

    if (sameLogAsCurrent && _state.hasLiveSession) {
      _state = _state.copyWith(
        log: Map<String, dynamic>.from(log),
        isLoading: false,
        error: null,
      );
      _emit();
      return;
    }

    _state = _state.copyWith(
      isLoading: true,
      error: null,
      syncWarning: null,
      log: Map<String, dynamic>.from(log),
      logId: requestedLogId,
      habitId: _extractHabitIdFromLog(log),
    );
    _emit();

    final habitId = _extractHabitIdFromLog(log);
    final logId = requestedLogId;

    if (habitId == null || logId == null) {
      _state = _state.copyWith(
        isLoading: false,
        error: 'This log is missing habit or log identifiers.',
      );
      _emit();
      return;
    }

    try {
      final habit = await _verificationService.fetchHabitById(habitId: habitId);
      final latestSession =
          await _focusRuntimeService.getLatestFocusSessionForLog(logId: logId);

      Map<String, dynamic>? policySnapshot;
      Map<String, dynamic>? locationConfig;

      try {
        policySnapshot =
            await _appPolicyService.buildFocusSessionPolicySnapshot(
          habitId: habitId,
        );
      } catch (_) {
        policySnapshot = null;
      }

      try {
        locationConfig =
            await _verificationService.fetchHabitLocationConfig(
          habitId: habitId,
        );
      } catch (_) {
        locationConfig = null;
      }

      _setMonotonicBasesFromSession(latestSession);

      await _prepareRuntimeRequirements();

      final now = DateTime.now();
      final rawAppAllowed = _computeAppAllowed();
      final rawLocationAllowed = _computeLocationAllowed();

      _pendingViolationSince = null;
      _pendingViolationCommitted = false;
      _pendingViolationApp = false;
      _pendingViolationLocation = false;
      _pendingViolationReason = null;

      _resetElapsedAnchors(
        now: now,
        shouldCountAsRunning: true,
      );

      _rebuildStateFromSession(
        now: now,
        session: latestSession,
        habit: habit,
        policySnapshot: policySnapshot,
        locationConfig: locationConfig,
        log: Map<String, dynamic>.from(log),
        error: null,
        syncWarning: null,
        forcedRawAppAllowed: rawAppAllowed,
        forcedRawLocationAllowed: rawLocationAllowed,
      );

      if (_state.hasLiveSession) {
        await ensureMonitoringStarted();
      }

      _emit();
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        error: 'Failed to load focus session.\n$e',
      );
      _emit();
    }
  }

  Future<void> _prepareRuntimeRequirements() async {
    try {
      final hasUsageAccess = await _deviceRuntimeService.hasUsageAccess();
      _state = _state.copyWith(usageAccessReady: hasUsageAccess);
    } catch (_) {
      _state = _state.copyWith(usageAccessReady: false);
    }

    if (_needsLocation(_state.habit)) {
      try {
        final enabled = await _locationRuntimeService.isServiceEnabled();
        if (!enabled) {
          _state = _state.copyWith(
            locationPermissionReady: false,
            error: 'Location services are disabled.',
          );
          return;
        }

        var permission = await _locationRuntimeService.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await _locationRuntimeService.requestPermission();
        }

        final allowed = permission != LocationPermission.denied &&
            permission != LocationPermission.deniedForever;

        Position? position;
        if (allowed) {
          try {
            position = await _locationRuntimeService.getCurrentPosition();
            _lastLocationRefreshAt = DateTime.now();
          } catch (_) {}
        }

        _state = _state.copyWith(
          locationPermissionReady: allowed,
          latestPosition: position ?? _state.latestPosition,
        );
      } catch (_) {
        _state = _state.copyWith(locationPermissionReady: false);
      }
    }
  }

  void _startUiTicker() {
    _uiTimer?.cancel();

    _uiTimer = Timer.periodic(_uiTickInterval, (_) {
      final now = DateTime.now();

      if (!_state.hasLiveSession) {
        _lastAccountedAt = now;
        _emit();
        return;
      }

      final rawAppAllowed = _computeAppAllowed();
      final rawLocationAllowed = _computeLocationAllowed();

      _updateViolationDebounce(
        now: now,
        rawAppAllowed: rawAppAllowed,
        rawLocationAllowed: rawLocationAllowed,
      );

      _applyElapsedAccounting(
        now: now,
        shouldCountAsRunning: _shouldCountAsRunning(now),
      );

      _state = _state.copyWith(
        status: _effectiveStatus(now),
        validFocusSeconds: _effectiveValidSeconds(),
        graceSecondsUsed: _effectiveGraceSeconds(),
        appAllowed: rawAppAllowed,
        locationAllowed: rawLocationAllowed,
        appViolationCount: _localAppViolationCount,
        locationViolationCount: _localLocationViolationCount,
        foregroundAppIdentifier:
            _effectiveForegroundAppId(_latestRuntimeSnapshot),
        isScreenOff: _latestRuntimeSnapshot?.isScreenOff ?? false,
        localGraceReason: _effectiveGraceReason(now),
      );

      _emit();
    });
  }

  Future<void> _attachRuntimeListener() async {
    await _runtimeSub?.cancel();

    _runtimeSub = _deviceRuntimeService.runtimeStream().listen((event) async {
      _latestRuntimeSnapshot = event;

      final now = DateTime.now();

      if (_needsLocation(_state.habit)) {
        final shouldRefreshLocation = _lastLocationRefreshAt == null ||
            now.difference(_lastLocationRefreshAt!) >=
                _locationRefreshInterval;

        if (shouldRefreshLocation) {
          try {
            final pos = await _locationRuntimeService.getCurrentPosition();
            _lastLocationRefreshAt = now;
            _state = _state.copyWith(latestPosition: pos);
          } catch (_) {}
        }
      }

      final rawAppAllowed = _computeAppAllowed();
      final rawLocationAllowed = _computeLocationAllowed();

      _updateViolationDebounce(
        now: now,
        rawAppAllowed: rawAppAllowed,
        rawLocationAllowed: rawLocationAllowed,
      );

      _state = _state.copyWith(
        status: _effectiveStatus(now),
        appAllowed: rawAppAllowed,
        locationAllowed: rawLocationAllowed,
        appViolationCount: _localAppViolationCount,
        locationViolationCount: _localLocationViolationCount,
        foregroundAppIdentifier: _effectiveForegroundAppId(event),
        isScreenOff: event.isScreenOff,
        localGraceReason: _effectiveGraceReason(now),
      );
      _emit();

      if (!_state.hasLiveSession || _state.focusSessionId == null) return;

      final shouldSyncNow = _lastBackendSyncAt == null ||
          now.difference(_lastBackendSyncAt!) >= _backendSyncInterval;

      if (!shouldSyncNow) return;

      final elapsed = _lastBackendSyncAt == null
          ? 1
          : now.difference(_lastBackendSyncAt!).inSeconds.clamp(1, 60);

      try {
        final updated = await _focusRuntimeService.tickFocusSession(
          focusSessionId: _state.focusSessionId!,
          foregroundAppIdentifier: _effectiveForegroundAppId(event),
          isScreenOff: event.isScreenOff,
          elapsedSinceLastTickSeconds: elapsed,
          currentLatitude: _state.latestPosition?.latitude,
          currentLongitude: _state.latestPosition?.longitude,
        );

        _lastBackendSyncAt = now;

        _setMonotonicBasesFromSession(updated);
        _rebuildStateFromSession(
          now: now,
          session: Map<String, dynamic>.from(updated!),
          syncWarning: null,
          error: null,
          forcedRawAppAllowed: rawAppAllowed,
          forcedRawLocationAllowed: rawLocationAllowed,
        );

        _resetElapsedAnchors(
          now: now,
          shouldCountAsRunning: _shouldCountAsRunning(now),
        );

        _emit();
      } catch (e) {
        _state = _state.copyWith(
          syncWarning: 'Temporary sync issue. Monitoring will retry.',
        );
        _emit();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastLifecycleState = state;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiTimer?.cancel();
    _runtimeSub?.cancel();
    super.dispose();
  }
}