// ignore_for_file: unused_element

import 'package:supabase_flutter/supabase_flutter.dart';

class BadgeService {
  final SupabaseClient _supabase = Supabase.instance.client;

  int _coerceInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  double _coerceDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  Future<Map<String, dynamic>?> _fetchBadgeDefinitionByCode(
    String code,
  ) async {
    final row = await _supabase
        .from('badge_definitions')
        .select('badge_id, code, title, active')
        .eq('code', code)
        .eq('active', true)
        .maybeSingle();

    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  Future<bool> userHasBadge({
    required String userId,
    required String badgeCode,
  }) async {
    final badge = await _fetchBadgeDefinitionByCode(badgeCode);
    if (badge == null) return false;

    final row = await _supabase
        .from('user_badges')
        .select('user_badge_id')
        .eq('user_id', userId)
        .eq('badge_id', badge['badge_id'])
        .maybeSingle();

    return row != null;
  }

  Future<void> awardBadgeByCode({
    required String userId,
    required String badgeCode,
    String? sourceEvent,
    Map<String, dynamic>? metadata,
  }) async {
    final badge = await _fetchBadgeDefinitionByCode(badgeCode);
    if (badge == null) return;

    await _supabase.from('user_badges').upsert({
      'user_id': userId,
      'badge_id': badge['badge_id'],
      'source_event': sourceEvent,
      'metadata': metadata,
    });
  }

  String titleForExecutionPoints(int executionPoints) {
    if (executionPoints >= 1200) return 'Apex';
    if (executionPoints >= 700) return 'Vanguard';
    if (executionPoints >= 350) return 'Executor';
    if (executionPoints >= 150) return 'Operator';
    if (executionPoints >= 50) return 'Builder';
    return 'Starter';
  }

  Future<void> refreshUserTitle({
    required String userId,
  }) async {
    final stats = await _supabase
        .from('user_discipline_stats')
        .select('execution_points')
        .eq('user_id', userId)
        .maybeSingle();

    final executionPoints = _coerceInt(stats?['execution_points']);
    final title = titleForExecutionPoints(executionPoints);

    await _supabase.from('profiles').update({
      'current_title': title,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  Future<void> evaluateAndAwardCoreBadges({
    required String userId,
  }) async {
    await _checkFirstCompletion(userId: userId);
    await _checkSevenDayStreak(userId: userId);
    await _checkFocusTenHours(userId: userId);
    await _checkCleanWeek(userId: userId);
    await _checkTrustedByPeers(userId: userId);
    await _checkComebackThree(userId: userId);
    await refreshUserTitle(userId: userId);
  }

  Future<void> _checkFirstCompletion({
    required String userId,
  }) async {
    final stats = await _supabase
        .from('user_discipline_stats')
        .select('total_completed')
        .eq('user_id', userId)
        .maybeSingle();

    final totalCompleted = _coerceInt(stats?['total_completed']);

    if (totalCompleted >= 1) {
      await awardBadgeByCode(
        userId: userId,
        badgeCode: 'first_completion',
        sourceEvent: 'stats_check',
      );
    }
  }

  Future<void> _checkSevenDayStreak({
    required String userId,
  }) async {
    final stats = await _supabase
        .from('user_discipline_stats')
        .select('current_streak')
        .eq('user_id', userId)
        .maybeSingle();

    final currentStreak = _coerceInt(stats?['current_streak']);

    if (currentStreak >= 7) {
      await awardBadgeByCode(
        userId: userId,
        badgeCode: 'streak_7',
        sourceEvent: 'stats_check',
        metadata: {'current_streak': currentStreak},
      );
    }
  }

  Future<void> _checkFocusTenHours({
    required String userId,
  }) async {
    final rows = await _supabase
        .from('focus_sessions')
        .select('valid_focus_seconds, user_id, threshold_met')
        .eq('user_id', userId)
        .eq('threshold_met', true);

    final sessions = List<Map<String, dynamic>>.from(rows);
    final totalSeconds = sessions.fold<int>(
      0,
      (sum, row) => sum + _coerceInt(row['valid_focus_seconds']),
    );

    if (totalSeconds >= 36000) {
      await awardBadgeByCode(
        userId: userId,
        badgeCode: 'focus_10_hours',
        sourceEvent: 'focus_sessions_check',
        metadata: {'valid_focus_seconds': totalSeconds},
      );
    }
  }

  Future<void> _checkCleanWeek({
    required String userId,
  }) async {
    final now = DateTime.now().toUtc();
    final start = now.subtract(const Duration(days: 7)).toIso8601String();

    final rows = await _supabase
        .from('habit_logs')
        .select('status, user_id, submitted_at, failed_at, missed_at')
        .eq('user_id', userId)
        .gte('available_at', start);

    final logs = List<Map<String, dynamic>>.from(rows);
    if (logs.isEmpty) return;

    final hasBadOutcome = logs.any((row) {
      final status = (row['status'] ?? '').toString();
      return status == 'failed' ||
          status == 'missed' ||
          status == 'rejected';
    });

    if (!hasBadOutcome) {
      await awardBadgeByCode(
        userId: userId,
        badgeCode: 'clean_week',
        sourceEvent: 'weekly_log_check',
      );
    }
  }

  Future<void> _checkTrustedByPeers({
    required String userId,
  }) async {
    final rows = await _supabase
        .from('log_verification_requests')
        .select('status, requester_user_id')
        .eq('requester_user_id', userId)
        .eq('status', 'approved');

    final approvedCount = List<Map<String, dynamic>>.from(rows).length;

    if (approvedCount >= 10) {
      await awardBadgeByCode(
        userId: userId,
        badgeCode: 'trusted_by_peers',
        sourceEvent: 'verification_check',
        metadata: {'approved_partner_verifications': approvedCount},
      );
    }
  }

  Future<void> _checkComebackThree({
    required String userId,
  }) async {
    final rows = await _supabase
        .from('habit_logs')
        .select('status, closed_at, failed_at, missed_at, submitted_at')
        .eq('user_id', userId)
        .order('log_date', ascending: false)
        .limit(10);

    final logs = List<Map<String, dynamic>>.from(rows);
    if (logs.length < 4) return;

    bool foundSetback = false;
    int successCountAfterSetback = 0;

    for (final row in logs.reversed) {
      final status = (row['status'] ?? '').toString();

      if (status == 'failed' || status == 'missed' || status == 'rejected') {
        foundSetback = true;
        successCountAfterSetback = 0;
        continue;
      }

      if (foundSetback && status == 'done') {
        successCountAfterSetback += 1;
      }
    }

    if (foundSetback && successCountAfterSetback >= 3) {
      await awardBadgeByCode(
        userId: userId,
        badgeCode: 'comeback_3',
        sourceEvent: 'recovery_check',
        metadata: {'successful_completions_after_setback': successCountAfterSetback},
      );
    }
  }

  Future<List<Map<String, dynamic>>> fetchUserBadges({
    required String userId,
  }) async {
    final rows = await _supabase
        .from('user_badges')
        .select('''
          user_badge_id,
          awarded_at,
          source_event,
          metadata,
          badge_definitions (
            badge_id,
            code,
            title,
            description,
            icon,
            category,
            rarity
          )
        ''')
        .eq('user_id', userId)
        .order('awarded_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows);
  }
}