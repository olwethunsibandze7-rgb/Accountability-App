import 'package:achievr_app/Services/app_clock.dart';
import 'package:achievr_app/Services/app_policy_service.dart';
import 'package:achievr_app/Services/verification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FocusRuntimeService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final VerificationService _verificationService = VerificationService();
  final AppPolicyService _appPolicyService = AppPolicyService();

  String get _userId {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('No authenticated user found.');
    }
    return user.id;
  }

  Future<Map<String, dynamic>> startFocusSession({
    required String logId,
    required String habitId,
    required double? currentLatitude,
    required double? currentLongitude,
    String? initialForegroundAppIdentifier,
    bool isScreenOff = false,
  }) async {
    final userId = _userId;

    final habit = await _verificationService.fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    final log = await _fetchLog(logId);
    if (log == null) {
      throw Exception('Habit log not found.');
    }

    if ((log['user_id'] ?? '').toString() != userId) {
      throw Exception('You can only start focus for your own log.');
    }

    final logStatus = (log['status'] ?? '').toString();
    const closedLogStatuses = {
      'done',
      'failed',
      'missed',
      'rejected',
      'submitted',
    };

    if (closedLogStatuses.contains(logStatus)) {
      throw Exception(
        'This task is already closed and cannot start focus again.',
      );
    }

    final verificationType =
        (habit['verification_type'] ?? '').toString().trim();

    final supportsFocus = verificationType == 'focus_auto' ||
        verificationType == 'focus_partner' ||
        verificationType == 'location_focus' ||
        verificationType == 'location_focus_partner';

    if (!supportsFocus) {
      throw Exception('This habit does not use focus-based verification.');
    }

    _assertCanStartWithinWindow(log);

    if (verificationType.contains('location')) {
      if (currentLatitude == null || currentLongitude == null) {
        throw Exception(
          'Current location is required to start this focus session.',
        );
      }

      await _verificationService.assertCanStartFocusForHabit(
        habitId: habitId,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
      );
    }

    final latestSession = await getLatestFocusSessionForLog(logId: logId);
    if (latestSession != null) {
      final latestStatus = (latestSession['status'] ?? '').toString();

      if (latestStatus == 'running' ||
          latestStatus == 'paused' ||
          latestStatus == 'grace') {
        throw Exception(
          'A focus session for this task is already in progress.',
        );
      }

      throw Exception(
        'This task already has a closed focus session and cannot be started again.',
      );
    }

    final policySnapshot =
        await _appPolicyService.buildFocusSessionPolicySnapshot(
      habitId: habitId,
    );

    final effectiveInitialApp = (initialForegroundAppIdentifier ?? '').trim().isEmpty
        ? 'com.example.achievr_app'
        : initialForegroundAppIdentifier!.trim();

    final appCheck = await _appPolicyService.assertCanRunFocusWithApp(
      habitId: habitId,
      foregroundAppIdentifier: effectiveInitialApp,
      isScreenOff: isScreenOff,
    );

    if ((appCheck['allowed'] as bool?) != true) {
      throw Exception(
        (appCheck['reason'] ?? 'App policy blocked this session.').toString(),
      );
    }

    final plannedDurationSeconds =
        ((_coerceInt(habit['duration_minutes']) ?? 0) * 60);

    final sessionInsert = await _supabase.from('focus_sessions').insert({
      'user_id': userId,
      'habit_id': habitId,
      'log_id': logId,
      'started_at': AppClock.now().toIso8601String(),
      'status': 'running',
      'planned_duration_seconds':
          plannedDurationSeconds > 0 ? plannedDurationSeconds : null,
      'app_policy_mode': policySnapshot['app_policy_mode'],
      'screen_off_allowed': policySnapshot['allow_screen_off'] ?? true,
      'last_foreground_app': effectiveInitialApp,
      'valid_focus_seconds': 0,
      'paused_seconds': 0,
      'grace_seconds_used': 0,
      'interruption_count': 0,
      'exit_count': 0,
      'returned_within_grace_count': 0,
      'threshold_met': false,
      'app_violation_count': 0,
      'app_pause_seconds': 0,
      'location_violation_count': 0,
    }).select().single();

    await _appendFocusEvent(
      focusSessionId: sessionInsert['focus_session_id'].toString(),
      eventType: 'started',
      metadata: {
        'habit_id': habitId,
        'log_id': logId,
        'verification_type': verificationType,
        'location_required': verificationType.contains('location'),
        'allowed_app_identifiers':
            policySnapshot['allowed_app_identifiers'] ?? [],
        'policy_mode': policySnapshot['app_policy_mode'],
        'leave_grace_seconds': policySnapshot['leave_grace_seconds'],
      },
    );

    await _supabase.from('habit_logs').update({
      'status': 'in_progress',
      'started_at': AppClock.now().toIso8601String(),
    }).eq('log_id', logId);

    return Map<String, dynamic>.from(sessionInsert);
  }

  Future<Map<String, dynamic>?> getLatestFocusSessionForLog({
    required String logId,
  }) async {
    final response = await _supabase
        .from('focus_sessions')
        .select()
        .eq('log_id', logId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>?> tickFocusSession({
    required String focusSessionId,
    required String foregroundAppIdentifier,
    required bool isScreenOff,
    required int elapsedSinceLastTickSeconds,
    double? currentLatitude,
    double? currentLongitude,
  }) async {
    final session = await _fetchSession(focusSessionId);
    if (session == null) {
      throw Exception('Focus session not found.');
    }

    final status = (session['status'] ?? '').toString();
    if (!_isTickableStatus(status)) {
      return session;
    }

    final habitId = session['habit_id'].toString();
    final logId = session['log_id'].toString();
    final screenOffAllowed =
        (session['screen_off_allowed'] as bool?) ?? true;

    final log = await _fetchLog(logId);
    if (log == null) {
      throw Exception('Habit log not found for this focus session.');
    }

    final logStatus = (log['status'] ?? '').toString();
    const closedLogStatuses = {
      'done',
      'failed',
      'missed',
      'rejected',
      'submitted',
    };

    if (closedLogStatuses.contains(logStatus)) {
      final invalidated = await _supabase
          .from('focus_sessions')
          .update({
            'status': 'failed',
            'ended_at': AppClock.now().toIso8601String(),
            'invalidated_reason': 'Underlying task log is already closed.',
            'last_foreground_app': foregroundAppIdentifier,
          })
          .eq('focus_session_id', focusSessionId)
          .select()
          .single();

      return Map<String, dynamic>.from(invalidated);
    }

    if (_hasExecutionWindowExpired(log)) {
      final failed = await _supabase
          .from('focus_sessions')
          .update({
            'status': 'failed',
            'ended_at': AppClock.now().toIso8601String(),
            'invalidated_reason': 'Scheduled execution window ended.',
            'last_foreground_app': foregroundAppIdentifier,
          })
          .eq('focus_session_id', focusSessionId)
          .select()
          .single();

      await _appendFocusEvent(
        focusSessionId: focusSessionId,
        eventType: 'window_expired',
        metadata: {
          'log_id': logId,
          'scheduled_end': log['scheduled_end'],
        },
      );

      await _supabase.from('habit_logs').update({
        'status': 'failed',
        'failed_at': AppClock.now().toIso8601String(),
        'failure_reason': 'Scheduled execution window ended.',
      }).eq('log_id', logId);

      return Map<String, dynamic>.from(failed);
    }

    bool locationAllowed = true;
    String? locationFailureReason;

    final habit = await _verificationService.fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found for this session.');
    }

    final verificationType =
        (habit['verification_type'] ?? '').toString().trim();

    if (verificationType.contains('location')) {
      if (currentLatitude == null || currentLongitude == null) {
        locationAllowed = false;
        locationFailureReason = 'Location is required for this session.';
      } else {
        try {
          await _verificationService.assertLocationEligible(
            habitId: habitId,
            currentLatitude: currentLatitude,
            currentLongitude: currentLongitude,
          );
        } catch (e) {
          locationAllowed = false;
          locationFailureReason = e.toString();
        }
      }
    }

    bool appAllowed = true;
    String? appFailureReason;

    final effectiveForegroundApp =
        foregroundAppIdentifier.trim().isEmpty
            ? 'com.example.achievr_app'
            : foregroundAppIdentifier.trim();

    final appCheck = await _appPolicyService.assertCanRunFocusWithApp(
      habitId: habitId,
      foregroundAppIdentifier: effectiveForegroundApp,
      isScreenOff: isScreenOff,
    );

    appAllowed = (appCheck['allowed'] as bool?) ?? false;
    appFailureReason = appCheck['reason']?.toString();

    if (isScreenOff && screenOffAllowed) {
      appAllowed = true;
    }

    final violationReason = !locationAllowed
        ? (locationFailureReason ?? 'Location requirement failed.')
        : !appAllowed
            ? (appFailureReason ?? 'App policy requirement failed.')
            : null;

    if (violationReason == null) {
      return _handleCompliantTick(
        session: session,
        logId: logId,
        focusSessionId: focusSessionId,
        foregroundAppIdentifier: effectiveForegroundApp,
        elapsedSinceLastTickSeconds: elapsedSinceLastTickSeconds,
      );
    }

    return _handleViolationTick(
      session: session,
      logId: logId,
      focusSessionId: focusSessionId,
      foregroundAppIdentifier: effectiveForegroundApp,
      elapsedSinceLastTickSeconds: elapsedSinceLastTickSeconds,
      locationViolation: !locationAllowed,
      reason: violationReason,
    );
  }

  Future<Map<String, dynamic>> completeFocusSession({
    required String focusSessionId,
  }) async {
    final session = await _fetchSession(focusSessionId);
    if (session == null) {
      throw Exception('Focus session not found.');
    }

    final status = (session['status'] ?? '').toString();
    if (status == 'failed' ||
        status == 'abandoned' ||
        status == 'invalidated' ||
        status == 'completed') {
      throw Exception('This focus session is already closed.');
    }

    final habitId = session['habit_id'].toString();
    final logId = session['log_id'].toString();

    final habit = await _verificationService.fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    final log = await _fetchLog(logId);
    if (log == null) {
      throw Exception('Habit log not found.');
    }

    if (_hasExecutionWindowExpired(log)) {
      throw Exception('The execution window has already ended.');
    }

    final logStatus = (log['status'] ?? '').toString();
    const closedLogStatuses = {
      'done',
      'failed',
      'missed',
      'rejected',
      'submitted',
    };

    if (closedLogStatuses.contains(logStatus)) {
      throw Exception('This task is already closed.');
    }

    final validFocusSeconds = _coerceInt(session['valid_focus_seconds']) ?? 0;
    final plannedDurationSeconds =
        _coerceInt(session['planned_duration_seconds']);
    final minValidMinutes = _coerceInt(habit['min_valid_minutes']);
    final minCompletionRatio = _coerceDouble(habit['min_completion_ratio']);

    bool thresholdMet = false;

    if (minValidMinutes != null && minValidMinutes > 0) {
      thresholdMet = validFocusSeconds >= (minValidMinutes * 60);
    } else if (plannedDurationSeconds != null &&
        plannedDurationSeconds > 0 &&
        minCompletionRatio != null &&
        minCompletionRatio > 0) {
      thresholdMet =
          validFocusSeconds >= (plannedDurationSeconds * minCompletionRatio);
    } else if (plannedDurationSeconds != null && plannedDurationSeconds > 0) {
      thresholdMet = validFocusSeconds >= plannedDurationSeconds;
    }

    final updated = await _supabase
        .from('focus_sessions')
        .update({
          'status': thresholdMet ? 'completed' : 'failed',
          'ended_at': AppClock.now().toIso8601String(),
          'threshold_met': thresholdMet,
          'invalidated_reason':
              thresholdMet ? null : 'Focus threshold not met',
        })
        .eq('focus_session_id', focusSessionId)
        .select()
        .single();

    await _appendFocusEvent(
      focusSessionId: focusSessionId,
      eventType: thresholdMet ? 'completed' : 'failed_threshold',
      metadata: {
        'valid_focus_seconds': validFocusSeconds,
        'planned_duration_seconds': plannedDurationSeconds,
        'min_valid_minutes': minValidMinutes,
        'min_completion_ratio': minCompletionRatio,
        'threshold_met': thresholdMet,
      },
    );

    final verificationType =
        (habit['verification_type'] ?? '').toString().trim();

    if (verificationType == 'focus_auto' ||
        verificationType == 'location_focus') {
      await _supabase.from('habit_logs').update({
        'status': thresholdMet ? 'done' : 'failed',
        'closed_at': AppClock.now().toIso8601String(),
        'failed_at': thresholdMet ? null : AppClock.now().toIso8601String(),
        'failure_reason': thresholdMet ? null : 'Focus threshold not met',
      }).eq('log_id', logId);
    } else {
      await _supabase.from('habit_logs').update({
        'status': thresholdMet ? 'submitted' : 'failed',
        'closed_at': thresholdMet ? null : AppClock.now().toIso8601String(),
        'failed_at': thresholdMet ? null : AppClock.now().toIso8601String(),
        'failure_reason': thresholdMet ? null : 'Focus threshold not met',
      }).eq('log_id', logId);
    }

    return Map<String, dynamic>.from(updated);
  }

  Future<void> abandonFocusSession({
    required String focusSessionId,
    String reason = 'User abandoned session',
  }) async {
    final session = await _fetchSession(focusSessionId);
    if (session == null) {
      throw Exception('Focus session not found.');
    }

    final status = (session['status'] ?? '').toString();
    if (status == 'completed' ||
        status == 'failed' ||
        status == 'abandoned' ||
        status == 'invalidated') {
      return;
    }

    await _supabase.from('focus_sessions').update({
      'status': 'abandoned',
      'ended_at': AppClock.now().toIso8601String(),
      'invalidated_reason': reason,
    }).eq('focus_session_id', focusSessionId);

    await _appendFocusEvent(
      focusSessionId: focusSessionId,
      eventType: 'abandoned',
      metadata: {'reason': reason},
    );

    await _supabase.from('habit_logs').update({
      'status': 'failed',
      'failed_at': AppClock.now().toIso8601String(),
      'failure_reason': reason,
    }).eq('log_id', session['log_id']);
  }

  Future<Map<String, dynamic>?> _fetchLog(String logId) async {
    final response = await _supabase
        .from('habit_logs')
        .select('''
          log_id,
          habit_id,
          user_id,
          status,
          log_date,
          scheduled_start,
          scheduled_end,
          required_valid_minutes
        ''')
        .eq('log_id', logId)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>?> _fetchSession(String focusSessionId) async {
    final response = await _supabase
        .from('focus_sessions')
        .select()
        .eq('focus_session_id', focusSessionId)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<void> _appendFocusEvent({
    required String focusSessionId,
    required String eventType,
    Map<String, dynamic>? metadata,
  }) async {
    await _supabase.from('focus_session_events').insert({
      'focus_session_id': focusSessionId,
      'event_type': eventType,
      'occurred_at': AppClock.now().toIso8601String(),
      'metadata': metadata ?? {},
    });
  }

  Future<Map<String, dynamic>> _handleCompliantTick({
    required Map<String, dynamic> session,
    required String logId,
    required String focusSessionId,
    required String foregroundAppIdentifier,
    required int elapsedSinceLastTickSeconds,
  }) async {
    final currentStatus = (session['status'] ?? '').toString();
    final validFocusSeconds = _coerceInt(session['valid_focus_seconds']) ?? 0;
    final updatedValidFocusSeconds = validFocusSeconds +
        (elapsedSinceLastTickSeconds < 0 ? 0 : elapsedSinceLastTickSeconds);

    final currentReturnedWithinGraceCount =
        _coerceInt(session['returned_within_grace_count']) ?? 0;

    final updated = await _supabase
        .from('focus_sessions')
        .update({
          'status': 'running',
          'valid_focus_seconds': updatedValidFocusSeconds,
          'last_foreground_app': foregroundAppIdentifier,
          'returned_within_grace_count': currentStatus == 'grace'
              ? currentReturnedWithinGraceCount + 1
              : currentReturnedWithinGraceCount,
        })
        .eq('focus_session_id', focusSessionId)
        .select()
        .single();

    if (currentStatus == 'grace' || currentStatus == 'paused') {
      await _appendFocusEvent(
        focusSessionId: focusSessionId,
        eventType: 'resumed',
        metadata: {
          'foreground_app': foregroundAppIdentifier,
        },
      );
    }

    await _supabase.from('habit_logs').update({
      'status': 'in_progress',
    }).eq('log_id', logId);

    return Map<String, dynamic>.from(updated);
  }

  Future<Map<String, dynamic>> _handleViolationTick({
    required Map<String, dynamic> session,
    required String logId,
    required String focusSessionId,
    required String foregroundAppIdentifier,
    required int elapsedSinceLastTickSeconds,
    required bool locationViolation,
    required String reason,
  }) async {
    final currentStatus = (session['status'] ?? '').toString();
    final graceSecondsUsed = _coerceInt(session['grace_seconds_used']) ?? 0;
    final interruptionCount = _coerceInt(session['interruption_count']) ?? 0;
    final exitCount = _coerceInt(session['exit_count']) ?? 0;
    final appPauseSeconds = _coerceInt(session['app_pause_seconds']) ?? 0;
    final appViolationCount = _coerceInt(session['app_violation_count']) ?? 0;
    final locationViolationCount =
        _coerceInt(session['location_violation_count']) ?? 0;

    final leaveGraceSeconds =
        await _resolveLeaveGraceSeconds(session['habit_id'].toString());

    final tickSeconds = elapsedSinceLastTickSeconds < 0
        ? 0
        : elapsedSinceLastTickSeconds;

    final nextGraceUsed = graceSecondsUsed + tickSeconds;
    final graceExpired =
        leaveGraceSeconds >= 0 && nextGraceUsed > leaveGraceSeconds;

    if (graceExpired) {
      final failed = await _supabase
          .from('focus_sessions')
          .update({
            'status': 'failed',
            'ended_at': AppClock.now().toIso8601String(),
            'grace_seconds_used': nextGraceUsed,
            'interruption_count':
                interruptionCount + (currentStatus == 'grace' ? 0 : 1),
            'exit_count': exitCount + 1,
            'app_pause_seconds': locationViolation
                ? appPauseSeconds
                : appPauseSeconds + tickSeconds,
            'app_violation_count': locationViolation
                ? appViolationCount
                : appViolationCount + 1,
            'location_violation_count': locationViolation
                ? locationViolationCount + 1
                : locationViolationCount,
            'last_foreground_app': foregroundAppIdentifier,
            'invalidated_reason': reason,
          })
          .eq('focus_session_id', focusSessionId)
          .select()
          .single();

      await _appendFocusEvent(
        focusSessionId: focusSessionId,
        eventType: 'grace_expired',
        metadata: {
          'reason': reason,
          'foreground_app': foregroundAppIdentifier,
          'location_violation': locationViolation,
          'grace_seconds_used': nextGraceUsed,
          'grace_seconds_allowed': leaveGraceSeconds,
        },
      );

      await _supabase.from('habit_logs').update({
        'status': 'failed',
        'failed_at': AppClock.now().toIso8601String(),
        'failure_reason': reason,
      }).eq('log_id', logId);

      return Map<String, dynamic>.from(failed);
    }

    final updated = await _supabase
        .from('focus_sessions')
        .update({
          'status': 'grace',
          'grace_seconds_used': nextGraceUsed,
          'interruption_count':
              interruptionCount + (currentStatus == 'grace' ? 0 : 1),
          'exit_count': exitCount + (currentStatus == 'grace' ? 0 : 1),
          'app_pause_seconds': locationViolation
              ? appPauseSeconds
              : appPauseSeconds + tickSeconds,
          'app_violation_count': locationViolation
              ? appViolationCount
              : appViolationCount + (currentStatus == 'grace' ? 0 : 1),
          'location_violation_count': locationViolation
              ? locationViolationCount + (currentStatus == 'grace' ? 0 : 1)
              : locationViolationCount,
          'last_foreground_app': foregroundAppIdentifier,
        })
        .eq('focus_session_id', focusSessionId)
        .select()
        .single();

    if (currentStatus != 'grace') {
      await _appendFocusEvent(
        focusSessionId: focusSessionId,
        eventType: locationViolation ? 'location_violation' : 'app_violation',
        metadata: {
          'reason': reason,
          'foreground_app': foregroundAppIdentifier,
          'grace_seconds_allowed': leaveGraceSeconds,
        },
      );
    }

    await _supabase.from('habit_logs').update({
      'status': 'in_progress',
    }).eq('log_id', logId);

    return Map<String, dynamic>.from(updated);
  }

  Future<int> _resolveLeaveGraceSeconds(String habitId) async {
    final snapshot =
        await _appPolicyService.buildFocusSessionPolicySnapshot(habitId: habitId);
    return _coerceInt(snapshot['leave_grace_seconds']) ?? 60;
  }

  void _assertCanStartWithinWindow(Map<String, dynamic> log) {
    final now = AppClock.now();
    final start = _combineLogDateAndTime(log['log_date'], log['scheduled_start']);
    final end = _combineLogDateAndTime(log['log_date'], log['scheduled_end']);

    if (start != null && now.isBefore(start)) {
      throw Exception('This focus task cannot start before its scheduled time.');
    }

    if (end != null && now.isAfter(end)) {
      throw Exception(
        'This focus task can no longer start because its execution window already ended.',
      );
    }
  }

  bool _hasExecutionWindowExpired(Map<String, dynamic> log) {
    final now = AppClock.now();
    final end = _combineLogDateAndTime(log['log_date'], log['scheduled_end']);
    if (end == null) return false;
    return now.isAfter(end);
  }

  DateTime? _combineLogDateAndTime(dynamic logDateValue, dynamic timeValue) {
    if (logDateValue == null || timeValue == null) return null;

    final parsedDate = DateTime.tryParse(logDateValue.toString());
    if (parsedDate == null) return null;

    final rawTime = timeValue.toString();
    final parts = rawTime.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    final second = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;

    if (hour == null || minute == null) return null;

    return DateTime(
      parsedDate.year,
      parsedDate.month,
      parsedDate.day,
      hour,
      minute,
      second,
    );
  }

  bool _isTickableStatus(String status) {
    return status == 'running' || status == 'paused' || status == 'grace';
  }

  int? _coerceInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString());
  }

  double? _coerceDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}