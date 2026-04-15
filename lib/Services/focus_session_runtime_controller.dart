// ignore_for_file: unused_local_variable, unnecessary_import

import 'dart:async';

import 'package:achievr_app/Services/app_policy_service.dart';
import 'package:achievr_app/Services/device_runtime_service.dart';
import 'package:achievr_app/Services/focus_engine_models.dart';
import 'package:achievr_app/Services/focus_runtime_service.dart';
import 'package:achievr_app/Services/focus_session_engine.dart';
import 'package:achievr_app/Services/location_runtime_service.dart';
import 'package:achievr_app/Services/verification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

class FocusRuntimeViewState {
  final bool isInitialized;
  final bool isLoading;
  final String? error;
  final String? syncWarning;

  final Map<String, dynamic>? log;
  final Map<String, dynamic>? habit;
  final Map<String, dynamic>? session;
  final Map<String, dynamic>? policySnapshot;
  final Map<String, dynamic>? locationConfig;

  final FocusEngineState? engineState;

  final bool usageAccessReady;
  final bool locationPermissionReady;
  final bool monitoringActive;

  final String? focusSessionId;
  final String? logId;
  final String? habitId;

  const FocusRuntimeViewState({
    required this.isInitialized,
    required this.isLoading,
    required this.error,
    required this.syncWarning,
    required this.log,
    required this.habit,
    required this.session,
    required this.policySnapshot,
    required this.locationConfig,
    required this.engineState,
    required this.usageAccessReady,
    required this.locationPermissionReady,
    required this.monitoringActive,
    required this.focusSessionId,
    required this.logId,
    required this.habitId,
  });

  factory FocusRuntimeViewState.initial() {
    return const FocusRuntimeViewState(
      isInitialized: false,
      isLoading: false,
      error: null,
      syncWarning: null,
      log: null,
      habit: null,
      session: null,
      policySnapshot: null,
      locationConfig: null,
      engineState: null,
      usageAccessReady: false,
      locationPermissionReady: false,
      monitoringActive: false,
      focusSessionId: null,
      logId: null,
      habitId: null,
    );
  }

  bool get hasLiveSession {
    final phase = engineState?.phase;
    return phase == FocusSessionPhase.running ||
        phase == FocusSessionPhase.violationDebounce ||
        phase == FocusSessionPhase.grace;
  }

  String get phaseLabel {
    switch (engineState?.phase) {
      case FocusSessionPhase.running:
        return 'running';
      case FocusSessionPhase.violationDebounce:
        return 'debounce';
      case FocusSessionPhase.grace:
        return 'grace';
      case FocusSessionPhase.completed:
        return 'completed';
      case FocusSessionPhase.failed:
        return 'failed';
      case FocusSessionPhase.abandoned:
        return 'abandoned';
      case FocusSessionPhase.arming:
        return 'arming';
      case FocusSessionPhase.idle:
      case null:
        return 'idle';
    }
  }

  FocusRuntimeViewState copyWith({
    bool? isInitialized,
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? syncWarning,
    bool clearSyncWarning = false,
    Map<String, dynamic>? log,
    Map<String, dynamic>? habit,
    Map<String, dynamic>? session,
    Map<String, dynamic>? policySnapshot,
    Map<String, dynamic>? locationConfig,
    FocusEngineState? engineState,
    bool? usageAccessReady,
    bool? locationPermissionReady,
    bool? monitoringActive,
    String? focusSessionId,
    String? logId,
    String? habitId,
  }) {
    return FocusRuntimeViewState(
      isInitialized: isInitialized ?? this.isInitialized,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      syncWarning: clearSyncWarning ? null : (syncWarning ?? this.syncWarning),
      log: log ?? this.log,
      habit: habit ?? this.habit,
      session: session ?? this.session,
      policySnapshot: policySnapshot ?? this.policySnapshot,
      locationConfig: locationConfig ?? this.locationConfig,
      engineState: engineState ?? this.engineState,
      usageAccessReady: usageAccessReady ?? this.usageAccessReady,
      locationPermissionReady:
          locationPermissionReady ?? this.locationPermissionReady,
      monitoringActive: monitoringActive ?? this.monitoringActive,
      focusSessionId: focusSessionId ?? this.focusSessionId,
      logId: logId ?? this.logId,
      habitId: habitId ?? this.habitId,
    );
  }
}

class FocusSessionRuntimeController extends ChangeNotifier
    with WidgetsBindingObserver {
  FocusSessionRuntimeController({
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
    _lastLifecycleChangeAt = DateTime.now();
  }

  final FocusRuntimeService _focusRuntimeService;
  final VerificationService _verificationService;
  final AppPolicyService _appPolicyService;
  final DeviceRuntimeService _deviceRuntimeService;
  final LocationRuntimeService _locationRuntimeService;

  FocusRuntimeViewState _state = FocusRuntimeViewState.initial();
  FocusRuntimeViewState get state => _state;

  FocusSessionEngine? _engine;
  StreamSubscription<DeviceRuntimeSnapshot>? _runtimeSub;
  Timer? _syncTimer;

  DateTime? _lastLocationRefreshAt;
  DateTime? _lastBackendSyncAt;
  Position? _latestPosition;

  AppLifecycleState? _lastLifecycleState;
  DateTime? _lastLifecycleChangeAt;
  String? _lastStableForegroundAppId;

  static const Duration _foregroundStabilizationWindow =
      Duration(seconds: 3);

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

  void _emit() => notifyListeners();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastLifecycleState = state;
    _lastLifecycleChangeAt = DateTime.now();
  }

  bool get _isAchievrForeground {
    return _lastLifecycleState == null ||
        _lastLifecycleState == AppLifecycleState.resumed;
  }

  bool _isUnstableForegroundId(String? appId) {
    final normalized = FocusSessionEngine.normalizeAppId(appId);
    if (normalized == null) return true;

    return normalized == 'unknown' ||
        normalized == 'unknown_foreground_app' ||
        normalized == 'null';
  }

  String _resolveForegroundAppId({
    required String? rawForegroundAppId,
    required bool isScreenOff,
  }) {
    final normalized = FocusSessionEngine.normalizeAppId(rawForegroundAppId);
    final now = DateTime.now();

    if (_isAchievrForeground) {
      _lastStableForegroundAppId = 'com.example.achievr_app';
      return 'com.example.achievr_app';
    }

    if (isScreenOff) {
      return _lastStableForegroundAppId ?? 'com.example.achievr_app';
    }

    if (!_isUnstableForegroundId(normalized)) {
      _lastStableForegroundAppId = normalized;
      return normalized!;
    }

    final withinStabilizationWindow = _lastLifecycleChangeAt != null &&
        now.difference(_lastLifecycleChangeAt!) <=
            _foregroundStabilizationWindow;

    if (withinStabilizationWindow && _lastStableForegroundAppId != null) {
      return _lastStableForegroundAppId!;
    }

    return _lastStableForegroundAppId ?? 'com.example.achievr_app';
  }

  Future<void> initialize() async {
    if (_state.isInitialized) return;

    _state = _state.copyWith(isInitialized: true);
    _emit();
  }

  bool isSameActiveLog(String? logId) {
    if (logId == null) return false;
    return _state.hasLiveSession && _state.logId == logId;
  }

  Future<void> attachToLog(Map<String, dynamic> log) async {
    await initialize();

    final requestedLogId = log['log_id']?.toString();
    if (isSameActiveLog(requestedLogId)) {
      _state = _state.copyWith(
        log: Map<String, dynamic>.from(log),
        isLoading: false,
        clearError: true,
      );
      _emit();
      return;
    }

    _state = _state.copyWith(
      isLoading: true,
      clearError: true,
      clearSyncWarning: true,
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

      final usageAccessReady = await _safeUsageAccessCheck();
      final locationPermissionReady =
          await _safeLocationPreparation(habit: habit);

      final engine = _buildEngine(
        habit: habit,
        policySnapshot: policySnapshot,
        locationConfig: locationConfig,
      );

      final now = DateTime.now();
      final initialSnapshot = FocusRuntimeSnapshot(
        capturedAt: now,
        foregroundAppId: 'com.example.achievr_app',
        isScreenOff: false,
        latitude: _latestPosition?.latitude,
        longitude: _latestPosition?.longitude,
      );

      _lastStableForegroundAppId = 'com.example.achievr_app';

      if (latestSession != null) {
        final phase = engine.mapServerStatusToPhase(
          latestSession['status']?.toString(),
        );

        engine.hydrateFromServer(
          now: now,
          snapshot: initialSnapshot,
          phase: phase,
          validFocusSeconds: _coerceInt(latestSession['valid_focus_seconds']),
          graceSecondsUsed: _coerceInt(latestSession['grace_seconds_used']),
          appViolationCount: _coerceInt(latestSession['app_violation_count']),
          locationViolationCount:
              _coerceInt(latestSession['location_violation_count']),
        );

        _engine = engine;
      } else {
        _engine = engine;
      }

      _state = _state.copyWith(
        isLoading: false,
        habit: habit,
        session: latestSession,
        policySnapshot: policySnapshot,
        locationConfig: locationConfig,
        usageAccessReady: usageAccessReady,
        locationPermissionReady: locationPermissionReady,
        engineState: _engine?.state,
        focusSessionId: latestSession?['focus_session_id']?.toString(),
        logId: logId,
        habitId: habitId,
      );

      if (_state.hasLiveSession) {
        await ensureMonitoringStarted();
        _startSyncTimer();
      }

      _emit();
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        error: 'Failed to load focus runtime.\n$e',
      );
      _emit();
    }
  }

  Future<bool> _safeUsageAccessCheck() async {
    try {
      return await _deviceRuntimeService.hasUsageAccess();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _safeLocationPreparation({
    required Map<String, dynamic>? habit,
  }) async {
    final requiresLocation =
        ((habit?['verification_type'] ?? '').toString()).contains('location');

    if (!requiresLocation) {
      return true;
    }

    try {
      final enabled = await _locationRuntimeService.isServiceEnabled();
      if (!enabled) return false;

      var permission = await _locationRuntimeService.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _locationRuntimeService.requestPermission();
      }

      final allowed = permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever;

      if (allowed) {
        try {
          _latestPosition = await _locationRuntimeService.getCurrentPosition();
          _lastLocationRefreshAt = DateTime.now();
        } catch (_) {}
      }

      return allowed;
    } catch (_) {
      return false;
    }
  }

  FocusSessionEngine _buildEngine({
    required Map<String, dynamic>? habit,
    required Map<String, dynamic>? policySnapshot,
    required Map<String, dynamic>? locationConfig,
  }) {
    final verificationType = (habit?['verification_type'] ?? '').toString();

    final minValidMinutes = _coerceInt(habit?['min_valid_minutes']);
    final durationMinutes = _coerceInt(habit?['duration_minutes']);
    final requiredValidSeconds = minValidMinutes > 0
        ? minValidMinutes * 60
        : (durationMinutes > 0 ? durationMinutes * 60 : 0);

    final allowedApps =
        (policySnapshot?['allowed_app_identifiers'] as List<dynamic>? ?? [])
            .map((e) => FocusSessionEngine.normalizeAppId(e.toString()))
            .whereType<String>()
            .where((e) => e.isNotEmpty)
            .toSet();

    final allowScreenOff =
        (policySnapshot?['allow_screen_off'] as bool?) ?? true;

    final graceSeconds = maxOrDefault(
      _coerceInt(policySnapshot?['leave_grace_seconds']),
      30,
    );

    final policy = FocusPolicy(
      allowedAppIds: allowedApps,
      allowScreenOff: allowScreenOff,
      requiresLocation: verificationType.contains('location'),
      violationDebounceSeconds: 6,
      graceSeconds: graceSeconds,
      requiredValidSeconds: requiredValidSeconds,
    );

    FocusLocationTarget? locationTarget;
    if (verificationType.contains('location') && locationConfig != null) {
      final lat = _toDouble(locationConfig['latitude']);
      final lng = _toDouble(locationConfig['longitude']);
      final radius = _toDouble(locationConfig['radius_meters']);

      if (lat != null && lng != null && radius != null) {
        locationTarget = FocusLocationTarget(
          latitude: lat,
          longitude: lng,
          radiusMeters: radius,
        );
      }
    }

    return FocusSessionEngine(
      policy: policy,
      startedAt: DateTime.now(),
      locationTarget: locationTarget,
    );
  }

  double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse('${value ?? ''}');
  }

  Future<void> startSessionForAttachedLog() async {
    final logId = _state.logId;
    final habitId = _state.habitId;

    if (logId == null || habitId == null) {
      throw Exception('Missing log or habit id.');
    }

    final started = await _focusRuntimeService.startFocusSession(
      logId: logId,
      habitId: habitId,
      currentLatitude: _latestPosition?.latitude,
      currentLongitude: _latestPosition?.longitude,
      initialForegroundAppIdentifier: 'com.example.achievr_app',
      isScreenOff: false,
    );

    final snapshot = FocusRuntimeSnapshot(
      capturedAt: DateTime.now(),
      foregroundAppId: 'com.example.achievr_app',
      isScreenOff: false,
      latitude: _latestPosition?.latitude,
      longitude: _latestPosition?.longitude,
    );

    _engine ??= _buildEngine(
      habit: _state.habit,
      policySnapshot: _state.policySnapshot,
      locationConfig: _state.locationConfig,
    );

    final result = _engine!.start(snapshot);

    _lastStableForegroundAppId = 'com.example.achievr_app';

    _state = _state.copyWith(
      session: started,
      engineState: result.state,
      focusSessionId: started['focus_session_id']?.toString(),
      clearError: true,
      clearSyncWarning: true,
    );

    _lastBackendSyncAt = DateTime.now();

    await ensureMonitoringStarted();
    _startSyncTimer();
    _emit();
  }

  Future<void> ensureMonitoringStarted() async {
    if (!_state.usageAccessReady) return;
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

    await _runtimeSub?.cancel();
    _runtimeSub = _deviceRuntimeService.runtimeStream().listen(
      _handleRuntimeSnapshot,
      onError: (error) {
        _state = _state.copyWith(
          syncWarning: 'Runtime monitoring issue. Retrying.',
        );
        _emit();
      },
    );

    _state = _state.copyWith(monitoringActive: true);
    _emit();
  }

  Future<void> _handleRuntimeSnapshot(DeviceRuntimeSnapshot raw) async {
    if (_engine == null) return;

    await _maybeRefreshLocation();

    final resolvedForegroundAppId = _resolveForegroundAppId(
      rawForegroundAppId: raw.foregroundAppIdentifier,
      isScreenOff: raw.isScreenOff,
    );

    final snapshot = FocusRuntimeSnapshot(
      capturedAt: DateTime.now(),
      foregroundAppId: resolvedForegroundAppId,
      isScreenOff: raw.isScreenOff,
      latitude: _latestPosition?.latitude,
      longitude: _latestPosition?.longitude,
    );

    final result = _engine!.tick(snapshot);

    _state = _state.copyWith(
      engineState: result.state,
      clearSyncWarning: true,
    );
    _emit();
  }

  Future<void> _maybeRefreshLocation() async {
    final requiresLocation =
        ((_state.habit?['verification_type'] ?? '').toString())
            .contains('location');

    if (!requiresLocation) return;

    final now = DateTime.now();
    final shouldRefresh = _lastLocationRefreshAt == null ||
        now.difference(_lastLocationRefreshAt!) >=
            const Duration(minutes: 2);

    if (!shouldRefresh) return;

    try {
      _latestPosition = await _locationRuntimeService.getCurrentPosition();
      _lastLocationRefreshAt = now;
    } catch (_) {}
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 12), (_) async {
      await syncToBackend();
    });
  }

  Future<void> syncToBackend() async {
    if (_state.focusSessionId == null || _engine == null) return;
    if (!_state.hasLiveSession) return;

    try {
      final engineState = _engine!.state;
      final now = DateTime.now();

      final elapsed = _lastBackendSyncAt == null
          ? 1
          : now.difference(_lastBackendSyncAt!).inSeconds.clamp(1, 60);

      final updated = await _focusRuntimeService.tickFocusSession(
        focusSessionId: _state.focusSessionId!,
        foregroundAppIdentifier: _resolveForegroundAppId(
          rawForegroundAppId: engineState.foregroundAppId,
          isScreenOff: engineState.isScreenOff,
        ),
        isScreenOff: engineState.isScreenOff,
        elapsedSinceLastTickSeconds: elapsed,
        currentLatitude: _latestPosition?.latitude,
        currentLongitude: _latestPosition?.longitude,
      );

      _lastBackendSyncAt = now;

      _state = _state.copyWith(
        session: updated,
        clearSyncWarning: true,
      );
      _emit();
    } catch (_) {
      _state = _state.copyWith(
        syncWarning: 'Temporary sync issue. Monitoring will retry.',
      );
      _emit();
    }
  }

  Future<void> completeSession() async {
    if (_state.focusSessionId == null || _engine == null) return;

    final result = _engine!.complete(DateTime.now());
    final updated = await _focusRuntimeService.completeFocusSession(
      focusSessionId: _state.focusSessionId!,
    );

    await stopMonitoring();

    _state = _state.copyWith(
      engineState: result.state,
      session: updated,
      monitoringActive: false,
    );
    _emit();
  }

  Future<void> abandonSession() async {
    if (_state.focusSessionId == null || _engine == null) return;

    final result = _engine!.abandon(DateTime.now());
    await _focusRuntimeService.abandonFocusSession(
      focusSessionId: _state.focusSessionId!,
    );

    await stopMonitoring();

    _state = _state.copyWith(
      engineState: result.state,
      monitoringActive: false,
    );
    _emit();
  }

  Future<void> stopMonitoring() async {
    _syncTimer?.cancel();
    await _runtimeSub?.cancel();
    _runtimeSub = null;

    try {
      await _deviceRuntimeService.stopMonitoring();
    } catch (_) {}

    _state = _state.copyWith(monitoringActive: false);
    _emit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _runtimeSub?.cancel();
    super.dispose();
  }
}

int maxOrDefault(int value, int fallback) {
  return value > 0 ? value : fallback;
}