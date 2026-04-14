// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:achievr_app/Providers/focus_session_provider.dart';
import 'package:achievr_app/Screens/Social/verification_settings_screen.dart';
import 'package:achievr_app/Services/app_clock.dart';
import 'package:achievr_app/Services/device_runtime_service.dart';
import 'package:achievr_app/Services/focus_runtime_service.dart';
import 'package:achievr_app/Services/habit_location_service.dart';
import 'package:achievr_app/Services/location_runtime_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class FocusModeScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> log;

  const FocusModeScreen({
    super.key,
    required this.log,
  });

  @override
  ConsumerState<FocusModeScreen> createState() => _FocusModeScreenState();
}

class _FocusModeScreenState extends ConsumerState<FocusModeScreen> {
  final FocusRuntimeService _focusRuntimeService = FocusRuntimeService();
  final HabitLocationService _habitLocationService = HabitLocationService();
  final DeviceRuntimeService _deviceRuntimeService = DeviceRuntimeService();
  final LocationRuntimeService _locationRuntimeService =
      LocationRuntimeService();

  bool _isStarting = false;
  bool _isCompleting = false;
  bool _isAbandoning = false;
  bool _isPreparingRuntime = false;
  bool _isPreparingLocation = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final coordinator = ref.read(focusSessionCoordinatorProvider);
      final requestedLogId = widget.log['log_id']?.toString();

      if (coordinator.isSameActiveLog(requestedLogId)) {
        return;
      }

      await coordinator.attachToLog(widget.log);
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
    final now = AppClock.now();

    if (start == null || end == null) return true;
    return !now.isBefore(start) && !now.isAfter(end);
  }

  String get _executionWindowMessage {
    final start = _windowStart;
    final end = _windowEnd;
    final now = AppClock.now();

    if (start != null && now.isBefore(start)) {
      return 'This task cannot start until ${_formatClockTime(start)}.';
    }

    if (end != null && now.isAfter(end)) {
      return 'This task is already outside its execution window.';
    }

    return 'This task is outside its execution window.';
  }

  Future<void> _refreshCoordinator() async {
    final coordinator = ref.read(focusSessionCoordinatorProvider);
    final requestedLogId = widget.log['log_id']?.toString();

    if (coordinator.isSameActiveLog(requestedLogId)) {
      return;
    }

    await coordinator.attachToLog(widget.log);
  }

  Future<void> _requestUsageAccess() async {
    try {
      setState(() {
        _isPreparingRuntime = true;
      });

      await _deviceRuntimeService.openUsageAccessSettings();
      await Future.delayed(const Duration(seconds: 1));
      await _refreshCoordinator();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open usage access settings: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingRuntime = false;
        });
      }
    }
  }

  Future<void> _requestLocationAccess() async {
    try {
      setState(() {
        _isPreparingLocation = true;
      });

      final enabled = await _locationRuntimeService.isServiceEnabled();
      if (!enabled) {
        throw Exception('Location services are disabled.');
      }

      var permission = await _locationRuntimeService.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _locationRuntimeService.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied forever. Open app settings.');
      }

      await _refreshCoordinator();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not prepare location: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingLocation = false;
        });
      }
    }
  }

  Future<void> _openVerificationSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const VerificationSettingsScreen(),
      ),
    );

    if (!mounted) return;
    await _refreshCoordinator();
  }

  Future<bool> _ensureLocationConfigExists(bool needsLocation) async {
    final habitId = _habitId;
    if (!needsLocation) return true;
    if (habitId == null) return false;

    final config = await _habitLocationService.fetchHabitLocationConfig(
      habitId: habitId,
    );

    if (config != null) {
      return true;
    }

    if (!mounted) return false;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This habit needs location setup before focus can start.'),
      ),
    );

    return false;
  }

  Future<Position?> _maybeGetCurrentPosition(bool needsLocation) async {
    if (!needsLocation) return null;

    final enabled = await _locationRuntimeService.isServiceEnabled();
    if (!enabled) {
      throw Exception('Location services are disabled.');
    }

    var permission = await _locationRuntimeService.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _locationRuntimeService.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception('Location permission denied.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied forever. Open app settings.');
    }

    return _locationRuntimeService.getCurrentPosition();
  }

  Future<void> _startFocus() async {
    final habitId = _habitId;
    final logId = _logId;
    final coordinator = ref.read(focusSessionCoordinatorProvider);
    final focusState = coordinator.state;

    if (habitId == null || logId == null) return;

    try {
      setState(() {
        _isStarting = true;
      });

      if (focusState.session != null && focusState.hasLiveSession) {
        throw Exception('This task already has an active focus session.');
      }

      if (!_isWithinExecutionWindow) {
        throw Exception(_executionWindowMessage);
      }

      final verificationType =
          (focusState.habit?['verification_type'] ?? '').toString();
      final supportsFocus = verificationType == 'focus_auto' ||
          verificationType == 'focus_partner' ||
          verificationType == 'location_focus' ||
          verificationType == 'location_focus_partner';
      final needsLocation = verificationType.contains('location');

      final hasPinnedLocation =
          await _ensureLocationConfigExists(needsLocation);
      if (!hasPinnedLocation) {
        throw Exception('This habit needs location setup first.');
      }

      if (supportsFocus && !focusState.usageAccessReady) {
        throw Exception('Usage access is required for focus mode.');
      }

      final position = await _maybeGetCurrentPosition(needsLocation);

      await _focusRuntimeService.startFocusSession(
        logId: logId,
        habitId: habitId,
        currentLatitude: position?.latitude,
        currentLongitude: position?.longitude,
        initialForegroundAppIdentifier: 'com.example.achievr_app',
        isScreenOff: false,
      );

      await coordinator.attachToLog(widget.log);
      await coordinator.ensureMonitoringStarted();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Focus session started.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start focus: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Future<void> _completeFocus() async {
    final coordinator = ref.read(focusSessionCoordinatorProvider);
    final sessionId = coordinator.state.focusSessionId;
    if (sessionId == null) return;

    try {
      setState(() {
        _isCompleting = true;
      });

      final completed = await _focusRuntimeService.completeFocusSession(
        focusSessionId: sessionId,
      );

      await _deviceRuntimeService.stopMonitoring();
      await coordinator.attachToLog(widget.log);

      if (!mounted) return;

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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not complete focus: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCompleting = false;
        });
      }
    }
  }

  Future<void> _abandonFocus() async {
    final coordinator = ref.read(focusSessionCoordinatorProvider);
    final sessionId = coordinator.state.focusSessionId;
    if (sessionId == null) return;

    try {
      setState(() {
        _isAbandoning = true;
      });

      await _focusRuntimeService.abandonFocusSession(
        focusSessionId: sessionId,
      );

      await _deviceRuntimeService.stopMonitoring();
      await coordinator.attachToLog(widget.log);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Focus session abandoned.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not abandon focus: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAbandoning = false;
        });
      }
    }
  }

  String _formatClockTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : hour > 12 ? hour - 12 : hour;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
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

  Widget _buildSimpleInfoCard({
    required String title,
    required String text,
    Widget? action,
  }) {
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
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              height: 1.4,
              fontSize: 12,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            action,
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final focusState = ref.watch(focusSessionCoordinatorProvider).state;

    if (focusState.isLoading && focusState.session == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0B0C),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFF5F5F5)),
        ),
      );
    }

    if (focusState.error != null && focusState.session == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0B0C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0B0C),
          title: const Text('Focus Mode'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              focusState.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFB3B3BB)),
            ),
          ),
        ),
      );
    }

    final status = focusState.status;
    final hasLiveSession = focusState.hasLiveSession;
    final isTerminal = status == 'completed' ||
        status == 'failed' ||
        status == 'abandoned' ||
        status == 'invalidated';
    final canStart = focusState.session == null && _isWithinExecutionWindow;

    final verificationType =
        (focusState.habit?['verification_type'] ?? '').toString();
    final needsLocation = verificationType.contains('location');

    final plannedDurationSeconds = (() {
      final value = focusState.session?['planned_duration_seconds'];
      if (value is int) return value;
      if (value is double) return value.round();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    })();

    final minValidMinutes = (() {
      final value = focusState.habit?['min_valid_minutes'];
      if (value is int) return value;
      if (value is double) return value.round();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    })();

    final durationMinutes = (() {
      final value = focusState.habit?['duration_minutes'];
      if (value is int) return value;
      if (value is double) return value.round();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    })();

    final requiredValidSeconds = minValidMinutes > 0
        ? minValidMinutes * 60
        : (plannedDurationSeconds > 0
            ? plannedDurationSeconds
            : (durationMinutes > 0 ? durationMinutes * 60 : 0));

    final remainingRequiredSeconds =
        (requiredValidSeconds - focusState.validFocusSeconds).clamp(0, 1 << 30);

    final graceRemaining = (focusState.graceSecondsAllowed -
            focusState.graceSecondsUsed)
        .clamp(0, 1 << 30);

    final secondsUntilWindowCloses = (() {
      final end = _windowEnd;
      if (end == null) return null;
      final diff = end.difference(AppClock.now()).inSeconds;
      return diff <= 0 ? 0 : diff;
    })();

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0C),
        title: const Text('Focus Mode'),
      ),
      body: ListView(
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
                if (focusState.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    focusState.error!,
                    style: const TextStyle(
                      color: Color(0xFFFF8A80),
                      height: 1.35,
                    ),
                  ),
                ],
                if (focusState.syncWarning != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    focusState.syncWarning!,
                    style: const TextStyle(
                      color: Color(0xFFFFB74D),
                      height: 1.35,
                    ),
                  ),
                ],
                if (focusState.localGraceReason != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    focusState.localGraceReason!,
                    style: const TextStyle(
                      color: Color(0xFFFFB300),
                      height: 1.35,
                      fontWeight: FontWeight.w700,
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
                value: _formatSeconds(focusState.validFocusSeconds),
              ),
              const SizedBox(width: 10),
              _buildMetricCard(
                label: 'Remaining target',
                value: _formatSeconds(remainingRequiredSeconds),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildMetricCard(
                label: 'Grace remaining',
                value: _formatSeconds(graceRemaining),
              ),
              const SizedBox(width: 10),
              _buildMetricCard(
                label: 'Window left',
                value: secondsUntilWindowCloses != null
                    ? _formatSeconds(secondsUntilWindowCloses)
                    : '--',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildMetricCard(
                label: 'App violations',
                value: '${focusState.appViolationCount}',
              ),
              const SizedBox(width: 10),
              _buildMetricCard(
                label: 'Location violations',
                value: '${focusState.locationViolationCount}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSimpleInfoCard(
            title: 'Focus rules',
            text: needsLocation
                ? 'Achievr is always allowed. Counting continues while you stay in Achievr or an allowed app. Location setup and permissions are managed from Verification.'
                : 'Achievr is always allowed. Counting continues while you stay in Achievr or an allowed app. Grace starts only when you leave the allowed context.',
            action: (needsLocation &&
                    (!focusState.locationPermissionReady ||
                        focusState.locationConfig == null))
                ? SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _openVerificationSettings,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF5F5F5),
                        side: const BorderSide(color: Color(0xFF3A3A42)),
                      ),
                      child: const Text('Open Verification'),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 18),
          if (!focusState.usageAccessReady)
            SizedBox(
              height: 48,
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
          if (needsLocation && !focusState.locationPermissionReady) ...[
            if (!focusState.usageAccessReady) const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _isPreparingLocation ? null : _requestLocationAccess,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF5F5F5),
                  side: const BorderSide(color: Color(0xFF3A3A42)),
                ),
                child: Text(
                  _isPreparingLocation ? 'Checking...' : 'Refresh Location Access',
                ),
              ),
            ),
          ],
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
          if (!canStart && !hasLiveSession)
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
      ),
    );
  }
}