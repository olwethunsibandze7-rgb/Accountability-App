import 'package:achievr_app/Services/app_clock.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HabitLogService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? get _userId => _supabase.auth.currentUser?.id;

  Future<void> generateTodayLogs() async {
    final userId = _userId;
    if (userId == null) return;

    final today = AppClock.today();
    final dateString =
        "${today.year.toString().padLeft(4, '0')}-"
        "${today.month.toString().padLeft(2, '0')}-"
        "${today.day.toString().padLeft(2, '0')}";

    await _supabase.rpc(
      'generate_daily_habit_logs',
      params: {
        'p_user_id': userId,
        'p_date': dateString,
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchTodayLogs() async {
    final userId = _userId;
    if (userId == null) return [];

    final today = AppClock.today();
    final dateString =
        "${today.year.toString().padLeft(4, '0')}-"
        "${today.month.toString().padLeft(2, '0')}-"
        "${today.day.toString().padLeft(2, '0')}";

    final response = await _supabase
        .from('habit_logs')
        .select('''
          log_id,
          habit_id,
          log_date,
          status,
          user_id,
          schedule_id,
          scheduled_start,
          scheduled_end,
          verification_type,
          available_at,
          started_at,
          submitted_at,
          closed_at,
          failed_at,
          missed_at,
          failure_reason,
          evidence_type,
          required_valid_minutes,
          earned_points,
          points_applied,
          habits (
            habit_id,
            habit_template_id,
            goal_id,
            title,
            description,
            target_frequency,
            duration_minutes,
            verification_type,
            verification_locked,
            requires_verifier,
            evidence_type,
            min_valid_minutes,
            min_completion_ratio,
            max_interruptions,
            grace_seconds,
            strict_fail_on_exit,
            base_points,
            penalty_points,
            tier_weight,
            goals (
              goal_id,
              goal_template_id,
              title,
              category
            )
          )
        ''')
        .eq('user_id', userId)
        .eq('log_date', dateString)
        .order('scheduled_start', ascending: true);

    final logs = List<Map<String, dynamic>>.from(response);

    return logs.map((log) {
      final normalized = Map<String, dynamic>.from(log);

      final habitRaw = normalized['habits'];
      if (habitRaw is Map) {
        final habit = Map<String, dynamic>.from(habitRaw);

        final goalRaw = habit['goals'];
        if (goalRaw is Map) {
          habit['goals'] = Map<String, dynamic>.from(goalRaw);
        }

        normalized['habits'] = habit;

        normalized['habit_id'] ??= habit['habit_id'];
        normalized['habit_title'] ??= habit['title'];
        normalized['duration_minutes'] ??= habit['duration_minutes'];
        normalized['evidence_type'] ??= habit['evidence_type'];
        normalized['requires_verifier'] ??= habit['requires_verifier'];

        if (normalized['verification_type'] == null) {
          normalized['verification_type'] = habit['verification_type'];
        }

        final goal = habit['goals'];
        if (goal is Map) {
          normalized['goal_title'] ??= goal['title'];
        }
      }

      return normalized;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> fetchLogsForDate(DateTime date) async {
    final userId = _userId;
    if (userId == null) return [];

    final dateString =
        "${date.year.toString().padLeft(4, '0')}-"
        "${date.month.toString().padLeft(2, '0')}-"
        "${date.day.toString().padLeft(2, '0')}";

    final response = await _supabase
        .from('habit_logs')
        .select('''
          log_id,
          habit_id,
          log_date,
          status,
          user_id,
          schedule_id,
          scheduled_start,
          scheduled_end,
          verification_type,
          available_at,
          started_at,
          submitted_at,
          closed_at,
          failed_at,
          missed_at,
          failure_reason,
          evidence_type,
          required_valid_minutes,
          earned_points,
          points_applied,
          habits (
            habit_id,
            habit_template_id,
            goal_id,
            title,
            description,
            target_frequency,
            duration_minutes,
            verification_type,
            verification_locked,
            requires_verifier,
            evidence_type,
            min_valid_minutes,
            min_completion_ratio,
            max_interruptions,
            grace_seconds,
            strict_fail_on_exit,
            base_points,
            penalty_points,
            tier_weight,
            goals (
              goal_id,
              goal_template_id,
              title,
              category
            )
          )
        ''')
        .eq('user_id', userId)
        .eq('log_date', dateString)
        .order('scheduled_start', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>?> fetchLogById({
    required String logId,
  }) async {
    final response = await _supabase
        .from('habit_logs')
        .select('''
          log_id,
          habit_id,
          log_date,
          status,
          user_id,
          schedule_id,
          scheduled_start,
          scheduled_end,
          verification_type,
          available_at,
          started_at,
          submitted_at,
          closed_at,
          failed_at,
          missed_at,
          failure_reason,
          evidence_type,
          required_valid_minutes,
          earned_points,
          points_applied,
          habits (
            habit_id,
            habit_template_id,
            goal_id,
            title,
            description,
            target_frequency,
            duration_minutes,
            verification_type,
            verification_locked,
            requires_verifier,
            evidence_type,
            min_valid_minutes,
            min_completion_ratio,
            max_interruptions,
            grace_seconds,
            strict_fail_on_exit,
            base_points,
            penalty_points,
            tier_weight,
            goals (
              goal_id,
              goal_template_id,
              title,
              category
            )
          )
        ''')
        .eq('log_id', logId)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<void> markLogDone({
    required String logId,
  }) async {
    await _supabase
        .from('habit_logs')
        .update({
          'status': 'done',
          'closed_at': AppClock.now().toIso8601String(),
          'failed_at': null,
          'missed_at': null,
          'failure_reason': null,
        })
        .eq('log_id', logId);
  }

  Future<void> markLogFailed({
    required String logId,
    required String reason,
  }) async {
    await _supabase
        .from('habit_logs')
        .update({
          'status': 'failed',
          'failed_at': AppClock.now().toIso8601String(),
          'failure_reason': reason,
        })
        .eq('log_id', logId);
  }

  Future<void> markLogMissed({
    required String logId,
    String reason = 'Execution window expired',
  }) async {
    await _supabase
        .from('habit_logs')
        .update({
          'status': 'missed',
          'missed_at': AppClock.now().toIso8601String(),
          'failure_reason': reason,
        })
        .eq('log_id', logId);
  }

  Future<void> markLogAvailable({
    required String logId,
  }) async {
    await _supabase
        .from('habit_logs')
        .update({
          'status': 'available',
          'available_at': AppClock.now().toIso8601String(),
        })
        .eq('log_id', logId);
  }

  Future<void> markLogInProgress({
    required String logId,
  }) async {
    await _supabase
        .from('habit_logs')
        .update({
          'status': 'in_progress',
          'started_at': AppClock.now().toIso8601String(),
        })
        .eq('log_id', logId);
  }

  Future<void> markLogSubmitted({
    required String logId,
  }) async {
    await _supabase
        .from('habit_logs')
        .update({
          'status': 'submitted',
          'submitted_at': AppClock.now().toIso8601String(),
        })
        .eq('log_id', logId);
  }

  Future<void> markLogPendingVerification({
    required String logId,
  }) async {
    await _supabase
        .from('habit_logs')
        .update({
          'status': 'pending_verification',
          'submitted_at': AppClock.now().toIso8601String(),
        })
        .eq('log_id', logId);
  }

  Future<void> expireOverdueTodayLogs() async {
    final userId = _userId;
    if (userId == null) return;

    final logs = await fetchTodayLogs();
    final now = AppClock.now();

    for (final log in logs) {
      final currentStatus = (log['status'] ?? '').toString();

      if (currentStatus == 'done' ||
          currentStatus == 'missed' ||
          currentStatus == 'failed' ||
          currentStatus == 'rejected' ||
          currentStatus == 'pending_verification' ||
          currentStatus == 'submitted') {
        continue;
      }

      final scheduledEnd = log['scheduled_end']?.toString();
      if (scheduledEnd == null || scheduledEnd.isEmpty) continue;

      final endDateTime = _combineTodayWithTimeString(scheduledEnd);
      if (endDateTime == null) continue;

      final latestAllowed = endDateTime.add(const Duration(minutes: 30));

      if (now.isAfter(latestAllowed)) {
        await markLogMissed(
          logId: log['log_id'].toString(),
          reason: 'Execution window expired',
        );
      }
    }
  }

  DateTime? _combineTodayWithTimeString(String hhmmss) {
    final parts = hhmmss.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;

    final today = AppClock.today();
    return DateTime(
      today.year,
      today.month,
      today.day,
      hour,
      minute,
    );
  }
}