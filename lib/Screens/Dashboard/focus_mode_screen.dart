// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:async';

import 'package:achievr_app/Services/app_clock.dart';
import 'package:achievr_app/Services/app_policy_service.dart';
import 'package:achievr_app/Services/device_runtime_service.dart';
import 'package:achievr_app/Services/focus_runtime_service.dart';
import 'package:achievr_app/Services/location_runtime_service.dart';
import 'package:achievr_app/Services/verification_service.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class FocusModeScreen extends StatefulWidget {
  final Map<String, dynamic> log;

  const FocusModeScreen({
    super.key,
    required this.log,
  });

  @override
  State<FocusModeScreen> createState() => _FocusModeScreenState();
}

class _FocusModeScreenState extends State<FocusModeScreen>
    with WidgetsBindingObserver {
  final FocusRuntimeService _focusRuntimeService = FocusRuntimeService();
  final VerificationService _verificationService = VerificationService();
  final AppPolicyService _appPolicyService = AppPolicyService();
  final DeviceRuntimeService _deviceRuntimeService = DeviceRuntimeService();
  final LocationRuntimeService _locationRuntimeService =
      LocationRuntimeService();

  StreamSubscription<DeviceRuntimeSnapshot>? _runtimeSub;
  StreamSubscription<Position>? _positionSub;
  Timer? _uiTimer;

  DeviceRuntimeSnapshot? _latestRuntimeSnapshot;
  Position? _latestPosition;
  DateTime _now = AppClock.now();

  bool _isLoading = true;
  bool _isStarting = false;
  bool _isCompleting = false;
  bool _isAbandoning = false;
  bool _isPreparingRuntime = false;
  bool _isPreparingLocation = false;

  bool _usageAccessReady = false;
  bool _locationPermissionReady = false;
  bool _deviceMonitoringStarted = false;

  String? _error;
  Map<String, dynamic>? _session;
  Map<String, dynamic>? _habit;
  Map<String, dynamic>? _appPolicySnapshot;
  Map<String, dynamic>? _locationConfig;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startUiTimer();
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiTimer?.cancel();
    _runtimeSub?.cancel();
    _positionSub?.cancel();

    // Important:
    // Do not stop background monitoring here if a live session exists.
    // The monitor must continue even when this screen is closed.
    if (!_isLiveSession(_session)) {
      _deviceRuntimeService.stopMonitoring();
      _locationRuntimeService.stop();
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleResume();
    }
  }

  Future<void> _handleResume() async {
    await _refreshRuntimeRequirements();
    await _reattachToActiveMonitoringIfNeeded();
  }

  Future<void> _refreshRuntimeRequirements() async {
    await _prepareDeviceMonitoring();

    if (_needsLocation) {
      await _prepareLocationTracking();
    }

    if (!mounted) return;
    setState(() {});
  }

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _now = AppClock.now();
      });
    });
  }

  String? get _logId => widget.log['log_id']?.toString();

  String? get _habitId {
    final nestedHabit = widget.log['habits'];
    if (nestedHabit is Map<String, dynamic>) {
      return nestedHabit['habit_id']?.toString();
    }
    if (nestedHabit is Map) {
      return nestedHabit['habit_id']?.toString();
    }
    return widget.log['habit_id']?.toString();
  }

  String get _habitTitle {
    final nestedHabit = widget.log['habits'];
    if (nestedHabit is Map<String, dynamic>) {
      return (nestedHabit['title'] ?? 'Focus task').toString();
    }
    if (nestedHabit is Map) {
      return (nestedHabit['title'] ?? 'Focus task').toString();
    }
    return (widget.log['habit_title'] ?? 'Focus task').toString();
  }

  String get _goalTitle {
    final nestedHabit = widget.log['habits'];
    if (nestedHabit is Map<String, dynamic>) {
      final nestedGoal = nestedHabit['goals'];
      if (nestedGoal is Map<String, dynamic>) {
        return (nestedGoal['title'] ?? 'Goal').toString();
      }
      if (nestedGoal is Map) {
        return (nestedGoal['title'] ?? 'Goal').toString();
      }
    }
    return (widget.log['goal_title'] ?? 'Goal').toString();
  }

  bool get _needsLocation =>
      ((_habit?['verification_type'] ?? '').toString()).contains('location');

  bool get _supportsFocus {
    final type = (_habit?['verification_type'] ?? '').toString();
    return type == 'focus_auto' ||
        type == 'focus_partner' ||
        type == 'location_focus' ||
        type == 'location_focus_partner';
  }

  bool _isLiveSession(Map<String, dynamic>? session) {
    if (session == null) return false;
    final status = (session['status'] ?? '').toString();
    return status == 'running' || status == 'paused' || status == 'grace';
  }

  bool _isTerminalSession(Map<String, dynamic>? session) {
    if (session == null) return false;
    final status = (session['status'] ?? '').toString();
    return status == 'completed' ||
        status == 'failed' ||
        status == 'abandoned' ||
        status == 'invalidated';
  }

  String _effectiveForegroundAppId(DeviceRuntimeSnapshot event) {
    final raw = event.foregroundAppIdentifier?.trim();
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
    return 'unknown_foreground_app';
  }

  Future<void> _boot() async {
    final habitId = _habitId;
    final logId = _logId;

    if (habitId == null || logId == null) {
      setState(() {
        _error = 'This log is missing habit or log identifiers.';
        _isLoading = false;
      });
      return;
    }

    try {
      final habit = await _verificationService.fetchHabitById(habitId: habitId);
      final latestSession =
          await _focusRuntimeService.getLatestFocusSessionForLog(logId: logId);

      Map<String, dynamic>? appPolicySnapshot;
      Map<String, dynamic>? locationConfig;

      try {
        appPolicySnapshot =
            await _appPolicyService.buildFocusSessionPolicySnapshot(
          habitId: habitId,
        );
      } catch (_) {
        appPolicySnapshot = null;
      }

      try {
        locationConfig =
            await _verificationService.fetchHabitLocationConfig(habitId: habitId);
      } catch (_) {
        locationConfig = null;
      }

      if (!mounted) return;

      setState(() {
        _habit = habit;
        _session = latestSession;
        _appPolicySnapshot = appPolicySnapshot;
        _locationConfig = locationConfig;
        _isLoading = false;
      });

      await _prepareDeviceMonitoring();
      await _prepareLocationTracking();

      // Important:
      // Do not start focus mode automatically just by opening this screen.
      // Only reattach if there is already a live session running.
      await _reattachToActiveMonitoringIfNeeded();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Failed to load focus mode.\n$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _reattachToActiveMonitoringIfNeeded() async {
    if (!_usageAccessReady) return;
    if (!_isLiveSession(_session)) return;
    if (_deviceMonitoringStarted) return;

    await _attachRuntimeListenerOnly();
  }

  Future<void> _prepareDeviceMonitoring() async {
    if (!_supportsFocus) return;

    try {
      setState(() {
        _isPreparingRuntime = true;
      });

      final hasAccess = await _deviceRuntimeService.hasUsageAccess();

      if (!mounted) return;

      setState(() {
        _usageAccessReady = hasAccess;
        _isPreparingRuntime = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _usageAccessReady = false;
        _isPreparingRuntime = false;
      });
    }
  }

  Future<void> _prepareLocationTracking() async {
    if (!_needsLocation) return;

    try {
      setState(() {
        _isPreparingLocation = true;
      });

      final enabled = await _locationRuntimeService.isServiceEnabled();
      if (!enabled) {
        if (!mounted) return;
        setState(() {
          _locationPermissionReady = false;
          _isPreparingLocation = false;
          _error = 'Location services are disabled.';
        });
        return;
      }

      var permission = await _locationRuntimeService.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _locationRuntimeService.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _locationPermissionReady = false;
          _isPreparingLocation = false;
          _error = permission == LocationPermission.deniedForever
              ? 'Location permission denied forever. Open app settings.'
              : 'Location permission denied.';
        });
        return;
      }

      final current = await _locationRuntimeService.getCurrentPosition();

      await _positionSub?.cancel();
      _positionSub = _locationRuntimeService.positionStream().listen((position) {
        if (!mounted) return;
        setState(() {
          _latestPosition = position;
        });
      });

      if (!mounted) return;
      setState(() {
        _latestPosition = current;
        _locationPermissionReady = true;
        _isPreparingLocation = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationPermissionReady = false;
        _isPreparingLocation = false;
        _error = 'Could not prepare GPS.\n$e';
      });
    }
  }

  Future<void> _requestUsageAccess() async {
    try {
      await _deviceRuntimeService.openUsageAccessSettings();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open usage access settings: $e')),
      );
    }
  }

  Future<void> _requestLocationAccess() async {
    try {
      await _prepareLocationTracking();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not prepare GPS: $e')),
      );
    }
  }

  Future<void> _openLocationSettings() async {
    try {
      await _locationRuntimeService.openLocationSettings();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open location settings: $e')),
      );
    }
  }

  Future<void> _openAppSettings() async {
    try {
      await _locationRuntimeService.openAppSettings();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open app settings: $e')),
      );
    }
  }

  Future<void> _attachRuntimeListenerOnly() async {
    _runtimeSub?.cancel();

    _runtimeSub = _deviceRuntimeService.runtimeStream().listen(
      (event) async {
        _latestRuntimeSnapshot = event;

        if (!mounted) return;
        setState(() {});

        final sessionId = _session?['focus_session_id']?.toString();
        if (sessionId == null || !_isLiveSession(_session)) {
          return;
        }

        try {
          final updated = await _focusRuntimeService.tickFocusSession(
            focusSessionId: sessionId,
            foregroundAppIdentifier: _effectiveForegroundAppId(event),
            isScreenOff: event.isScreenOff,
            elapsedSinceLastTickSeconds: 1,
            currentLatitude: _latestPosition?.latitude,
            currentLongitude: _latestPosition?.longitude,
          );

          if (!mounted) return;

          setState(() {
            _session = updated;
          });

          if (!_isLiveSession(updated)) {
            _deviceMonitoringStarted = false;

            final status = (updated?['status'] ?? '').toString();
            if (status == 'failed') {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Focus session failed. Grace expired, the window ended, or a rule was broken.',
                  ),
                ),
              );
            }
          }
        } catch (e) {
          if (!mounted) return;

          setState(() {
            _error = 'Runtime monitoring failed.\n$e';
          });
        }
      },
    );

    _deviceMonitoringStarted = true;
  }

  Future<void> _startRuntimeStream() async {
    if (!_usageAccessReady || _deviceMonitoringStarted) return;

    final habitId = _habitId;
    if (habitId == null) return;

    try {
      final snapshot = _appPolicySnapshot ??
          await _appPolicyService.buildFocusSessionPolicySnapshot(
            habitId: habitId,
          );

      final allowedApps =
          (snapshot['allowed_app_identifiers'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList();

      // This should start the real background monitor.
      // DeviceRuntimeService must keep running even when this screen is gone.
      await _deviceRuntimeService.startMonitoring(
        allowedAppIdentifiers: allowedApps,
        allowScreenOff: (snapshot['allow_screen_off'] as bool?) ?? true,
        pollIntervalMs: 1000,
      );

      await _attachRuntimeListenerOnly();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not start device monitoring.\n$e';
      });
    }
  }

  Future<void> _startFocus() async {
    final habitId = _habitId;
    final logId = _logId;

    if (habitId == null || logId == null) return;

    try {
      setState(() {
        _isStarting = true;
        _error = null;
      });

      if (_session != null) {
        throw Exception(
          'This task already has a focus session and cannot be started again.',
        );
      }

      if (!_isWithinExecutionWindow) {
        throw Exception(_executionWindowMessage);
      }

      if (_supportsFocus && !_usageAccessReady) {
        throw Exception(
          'Usage access is required for strict focus mode. Open settings and enable Achievr, then return to this screen.',
        );
      }

      if (_needsLocation) {
        await _prepareLocationTracking();
        if (!_locationPermissionReady || _latestPosition == null) {
          throw Exception('Live GPS is required for this focus session.');
        }
      }

      final started = await _focusRuntimeService.startFocusSession(
        logId: logId,
        habitId: habitId,
        currentLatitude: _latestPosition?.latitude,
        currentLongitude: _latestPosition?.longitude,
        initialForegroundAppIdentifier:
            _latestRuntimeSnapshot?.foregroundAppIdentifier?.trim().isNotEmpty ==
                    true
                ? _latestRuntimeSnapshot!.foregroundAppIdentifier!
                : 'com.example.achievr_app',
        isScreenOff: _latestRuntimeSnapshot?.isScreenOff ?? false,
      );

      if (!mounted) return;

      setState(() {
        _session = started;
        _isStarting = false;
      });

      if (_supportsFocus && _usageAccessReady) {
        await _startRuntimeStream();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Focus session started.')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isStarting = false;
        _error = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start focus: $e')),
      );
    }
  }

  Future<void> _completeFocus() async {
    final sessionId = _session?['focus_session_id']?.toString();
    if (sessionId == null) return;

    try {
      setState(() {
        _isCompleting = true;
        _error = null;
      });

      final completed = await _focusRuntimeService.completeFocusSession(
        focusSessionId: sessionId,
      );

      await _deviceRuntimeService.stopMonitoring();
      _deviceMonitoringStarted = false;

      if (!mounted) return;

      setState(() {
        _session = completed;
        _isCompleting = false;
      });

      final thresholdMet = (completed['threshold_met'] as bool?) ?? false;
      final status = (completed['status'] ?? '').toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            thresholdMet
                ? 'Focus session completed.'
                : 'Focus session ended, but threshold was not met ($status).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isCompleting = false;
        _error = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not complete focus: $e')),
      );
    }
  }

  Future<void> _abandonFocus() async {
    final sessionId = _session?['focus_session_id']?.toString();
    if (sessionId == null) return;

    try {
      setState(() {
        _isAbandoning = true;
        _error = null;
      });

      await _focusRuntimeService.abandonFocusSession(
        focusSessionId: sessionId,
      );

      await _deviceRuntimeService.stopMonitoring();
      _deviceMonitoringStarted = false;

      await _boot();

      if (!mounted) return;

      setState(() {
        _isAbandoning = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Focus session abandoned.')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isAbandoning = false;
        _error = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not abandon focus: $e')),
      );
    }
  }

  DateTime? get _windowStart {
    final logDate = DateTime.tryParse(widget.log['log_date']?.toString() ?? '');
    final rawTime = widget.log['scheduled_start']?.toString();

    if (logDate == null || rawTime == null || rawTime.isEmpty) return null;

    final parts = rawTime.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    final second = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;

    if (hour == null || minute == null) return null;

    return DateTime(
      logDate.year,
      logDate.month,
      logDate.day,
      hour,
      minute,
      second,
    );
  }

  DateTime? get _windowEnd {
    final logDate = DateTime.tryParse(widget.log['log_date']?.toString() ?? '');
    final rawTime = widget.log['scheduled_end']?.toString();

    if (logDate == null || rawTime == null || rawTime.isEmpty) return null;

    final parts = rawTime.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    final second = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;

    if (hour == null || minute == null) return null;

    return DateTime(
      logDate.year,
      logDate.month,
      logDate.day,
      hour,
      minute,
      second,
    );
  }

  bool get _isWithinExecutionWindow {
    final start = _windowStart;
    final end = _windowEnd;
    if (start == null || end == null) return true;
    return !_now.isBefore(start) && !_now.isAfter(end);
  }

  String get _executionWindowMessage {
    final start = _windowStart;
    final end = _windowEnd;

    if (start != null && _now.isBefore(start)) {
      return 'This task cannot start until ${_formatClockTime(start)}.';
    }

    if (end != null && _now.isAfter(end)) {
      return 'This task is already outside its execution window.';
    }

    return 'This task is outside its execution window.';
  }

  int _coerceInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int get _validFocusSeconds => _coerceInt(_session?['valid_focus_seconds']);
  int get _graceSecondsUsed => _coerceInt(_session?['grace_seconds_used']);
  int get _plannedDurationSeconds =>
      _coerceInt(_session?['planned_duration_seconds']);
  int get _leaveGraceSeconds =>
      _coerceInt(_appPolicySnapshot?['leave_grace_seconds']);

  int get _remainingGraceSeconds {
    final remaining = _leaveGraceSeconds - _graceSecondsUsed;
    return remaining < 0 ? 0 : remaining;
  }

  int get _requiredValidSeconds {
    final minValidMinutes = _coerceInt(_habit?['min_valid_minutes']);
    if (minValidMinutes > 0) return minValidMinutes * 60;

    if (_plannedDurationSeconds > 0) return _plannedDurationSeconds;

    final durationMinutes = _coerceInt(_habit?['duration_minutes']);
    if (durationMinutes > 0) return durationMinutes * 60;

    return 0;
  }

  int get _remainingRequiredSeconds {
    final remaining = _requiredValidSeconds - _validFocusSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  int? get _secondsUntilWindowOpens {
    final start = _windowStart;
    if (start == null) return null;
    final diff = start.difference(_now).inSeconds;
    return diff <= 0 ? 0 : diff;
  }

  int? get _secondsUntilWindowCloses {
    final end = _windowEnd;
    if (end == null) return null;
    final diff = end.difference(_now).inSeconds;
    return diff <= 0 ? 0 : diff;
  }

  String _formatClockTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : hour > 12 ? hour - 12 : hour;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
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

  String _formatSeconds(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    final hours = safe ~/ 3600;
    final minutes = (safe % 3600) ~/ 60;
    final seconds = safe % 60;

    final hh = hours.toString().padLeft(2, '0');
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');

    if (hours > 0) return '$hh:$mm:$ss';
    return '$mm:$ss';
  }

  String _statusLabel(String raw) {
    switch (raw) {
      case 'running':
        return 'Running';
      case 'grace':
        return 'Grace';
      case 'paused':
        return 'Paused';
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      case 'abandoned':
        return 'Abandoned';
      case 'invalidated':
        return 'Invalidated';
      default:
        return raw.isEmpty ? 'Not started' : raw;
    }
  }

  Color _statusColor(String raw) {
    switch (raw) {
      case 'running':
        return const Color(0xFF4CAF50);
      case 'grace':
        return const Color(0xFFFFB300);
      case 'paused':
        return const Color(0xFF90A4AE);
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'failed':
      case 'abandoned':
      case 'invalidated':
        return const Color(0xFFE57373);
      default:
        return const Color(0xFFB3B3BB);
    }
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF17171A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF232329)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFFF5F5F5),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuntimeCard() {
    final latestApp =
        _latestRuntimeSnapshot?.foregroundAppIdentifier ?? 'Unknown';
    final isScreenOff = _latestRuntimeSnapshot?.isScreenOff ?? false;

    final allowedLabels =
        (_appPolicySnapshot?['allowed_app_labels'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();

    final appPolicyMode =
        (_appPolicySnapshot?['app_policy_mode'] ?? 'achievr_only').toString();
    final allowScreenOff =
        (_appPolicySnapshot?['allow_screen_off'] as bool?) ?? true;
    final leaveGraceSeconds = _leaveGraceSeconds.toString();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Runtime monitoring',
            style: TextStyle(
              color: Color(0xFFF5F5F5),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _usageAccessReady
                ? 'Strict monitoring is active after you start focus. Achievr is always allowed. Leaving the allowed app context enters grace.'
                : 'Usage access is required for strict focus monitoring.',
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              height: 1.4,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          _ruleLine('Policy mode', appPolicyMode),
          _ruleLine('Screen off allowed', allowScreenOff ? 'Yes' : 'No'),
          _ruleLine('Grace seconds', leaveGraceSeconds),
          _ruleLine('Foreground app', latestApp),
          _ruleLine('Screen state', isScreenOff ? 'Off' : 'On'),
          if (allowedLabels.isNotEmpty)
            _ruleLine('Exception apps', allowedLabels.join(', ')),
          if (allowedLabels.isEmpty && appPolicyMode == 'allow_list')
            _ruleLine('Exception apps', 'None configured'),
          if (!_usageAccessReady) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isPreparingRuntime ? null : _requestUsageAccess,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF5F5F5),
                  side: const BorderSide(color: Color(0xFF3A3A42)),
                ),
                child: Text(
                  _isPreparingRuntime ? 'Checking...' : 'Enable Usage Access',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExecutionWindowCard() {
    final openIn = _secondsUntilWindowOpens;
    final closeIn = _secondsUntilWindowCloses;

    String statusText;
    if (_windowStart == null || _windowEnd == null) {
      statusText = 'No explicit execution window';
    } else if (_now.isBefore(_windowStart!)) {
      statusText = 'Not open yet';
    } else if (_now.isAfter(_windowEnd!)) {
      statusText = 'Window closed';
    } else {
      statusText = 'Window active';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Execution window',
            style: TextStyle(
              color: Color(0xFFF5F5F5),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          _ruleLine('Now', _formatClockTime(_now)),
          _ruleLine(
            'Start',
            _windowStart != null ? _formatClockTime(_windowStart!) : 'Not set',
          ),
          _ruleLine(
            'End',
            _windowEnd != null ? _formatClockTime(_windowEnd!) : 'Not set',
          ),
          _ruleLine('Status', statusText),
          if (openIn != null && openIn > 0)
            _ruleLine('Opens in', _formatSeconds(openIn)),
          if (closeIn != null && _isWithinExecutionWindow)
            _ruleLine('Closes in', _formatSeconds(closeIn)),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    final label = (_locationConfig?['label'] ?? 'Pinned location').toString();
    final radius = _locationConfig?['radius_meters']?.toString() ?? 'Unknown';
    final lat = _latestPosition?.latitude;
    final lng = _latestPosition?.longitude;
    final acc = _latestPosition?.accuracy;
    final distance = _distanceToTargetMeters;
    final insideRadius = _insidePinnedRadius;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: insideRadius == null
              ? const Color(0xFF232329)
              : insideRadius
                  ? const Color(0xFF2E7D32)
                  : const Color(0xFFE57373),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GPS status',
            style: TextStyle(
              color: Color(0xFFF5F5F5),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _locationPermissionReady
                ? 'Live GPS is active for this location-gated habit.'
                : 'GPS is required for this location-gated habit.',
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              height: 1.4,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          _ruleLine('Pinned place', label),
          _ruleLine('Radius', '$radius m'),
          _ruleLine('Permission', _locationPermissionReady ? 'Ready' : 'Not ready'),
          _ruleLine('Latitude', lat?.toString() ?? 'Unknown'),
          _ruleLine('Longitude', lng?.toString() ?? 'Unknown'),
          _ruleLine(
            'Accuracy',
            acc != null ? '${acc.toStringAsFixed(1)} m' : 'Unknown',
          ),
          _ruleLine(
            'Distance to target',
            distance != null ? '${distance.toStringAsFixed(1)} m' : 'Unknown',
          ),
          _ruleLine(
            'Inside radius',
            insideRadius == null
                ? 'Unknown'
                : insideRadius
                    ? 'Yes'
                    : 'No',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isPreparingLocation ? null : _requestLocationAccess,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF5F5F5),
                    side: const BorderSide(color: Color(0xFF3A3A42)),
                  ),
                  child: Text(
                    _isPreparingLocation ? 'Checking...' : 'Refresh GPS',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _openLocationSettings,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF5F5F5),
                    side: const BorderSide(color: Color(0xFF3A3A42)),
                  ),
                  child: const Text('Location Settings'),
                ),
              ),
            ],
          ),
          if (!_locationPermissionReady) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _openAppSettings,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF5F5F5),
                  side: const BorderSide(color: Color(0xFF3A3A42)),
                ),
                child: const Text('App Settings'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF5F5F5)),
      );
    }

    if (_error != null && _session == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFB3B3BB)),
          ),
        ),
      );
    }

    final session = _session;
    final status = (session?['status'] ?? '').toString();
    final appViolations = _coerceInt(session?['app_violation_count']);
    final locationViolations =
        _coerceInt(session?['location_violation_count']);
    final thresholdMet = (session?['threshold_met'] as bool?) ?? false;

    final hasLiveSession = _isLiveSession(session);
    final isTerminal = _isTerminalSession(session);
    final canStart = session == null && _isWithinExecutionWindow;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF17171A),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF232329)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _habitTitle,
                style: const TextStyle(
                  color: Color(0xFFF5F5F5),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _goalTitle,
                style: const TextStyle(
                  color: Color(0xFF9A9AA3),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _statusColor(status)),
                ),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                    color: _statusColor(status),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFFF8A80),
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (isTerminal) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF17171A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF232329)),
            ),
            child: const Text(
              'This focus session is closed. You cannot restart or re-enter it.',
              style: TextStyle(
                color: Color(0xFFB3B3BB),
                height: 1.35,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            _buildMetricCard(
              label: 'Valid focus',
              value: _formatSeconds(_validFocusSeconds),
            ),
            const SizedBox(width: 10),
            _buildMetricCard(
              label: 'Remaining target',
              value: _formatSeconds(_remainingRequiredSeconds),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildMetricCard(
              label: 'Grace remaining',
              value: _formatSeconds(_remainingGraceSeconds),
            ),
            const SizedBox(width: 10),
            _buildMetricCard(
              label: 'Window left',
              value: _secondsUntilWindowCloses != null
                  ? _formatSeconds(_secondsUntilWindowCloses!)
                  : '--',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildMetricCard(
              label: 'App violations',
              value: '$appViolations',
            ),
            const SizedBox(width: 10),
            _buildMetricCard(
              label: 'Location violations',
              value: '$locationViolations',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildExecutionWindowCard(),
        const SizedBox(height: 16),
        _buildRuntimeCard(),
        const SizedBox(height: 16),
        if (_needsLocation) ...[
          _buildLocationCard(),
          const SizedBox(height: 16),
        ],
        if (_habit != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF17171A),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF232329)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Session rules',
                  style: TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                _ruleLine(
                  'Verification',
                  (_habit?['verification_type'] ?? 'unknown').toString(),
                ),
                _ruleLine(
                  'Evidence',
                  (_habit?['evidence_type'] ?? 'none').toString(),
                ),
                _ruleLine(
                  'Duration',
                  _habit?['duration_minutes'] != null
                      ? '${_habit!['duration_minutes']} min'
                      : 'Not set',
                ),
                _ruleLine(
                  'Min valid time',
                  _habit?['min_valid_minutes'] != null
                      ? '${_habit!['min_valid_minutes']} min'
                      : 'Derived from ratio / duration',
                ),
                _ruleLine(
                  'Threshold met',
                  thresholdMet ? 'Yes' : 'Not yet',
                ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        if (canStart)
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isStarting ? null : _startFocus,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5F5F5),
                foregroundColor: Colors.black,
              ),
              icon: _isStarting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text(
                'Start Focus',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        if (!canStart && !hasLiveSession) ...[
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                disabledBackgroundColor: const Color(0xFF2A2A2F),
                disabledForegroundColor: const Color(0xFF6F6F76),
              ),
              icon: const Icon(Icons.lock_outline),
              label: Text(
                _isWithinExecutionWindow
                    ? 'Focus unavailable'
                    : 'Outside execution window',
              ),
            ),
          ),
        ],
        if (hasLiveSession) ...[
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isCompleting ? null : _completeFocus,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
              ),
              icon: _isCompleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: const Text(
                'Complete Focus',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isAbandoning ? null : _abandonFocus,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF8A80),
                side: const BorderSide(color: Color(0xFFFF8A80)),
              ),
              icon: _isAbandoning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.stop_circle_outlined),
              label: const Text(
                'Abandon Session',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _ruleLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.replaceAll('_', ' '),
              style: const TextStyle(
                color: Color(0xFFF5F5F5),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0C),
        title: const Text('Focus Mode'),
      ),
      body: _buildBody(),
    );
  }
}