import 'package:supabase_flutter/supabase_flutter.dart';

class PointsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  int _coerceInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse('${value ?? ''}') ?? fallback;
  }

  bool _isPartnerVerification(String verificationType) {
    return verificationType == 'partner' ||
        verificationType == 'focus_partner' ||
        verificationType == 'location_partner' ||
        verificationType == 'location_focus_partner';
  }

  bool _isFocusVerification(String verificationType) {
    return verificationType == 'focus_auto' ||
        verificationType == 'focus_partner' ||
        verificationType == 'location_focus' ||
        verificationType == 'location_focus_partner';
  }

  bool _isLocationVerification(String verificationType) {
    return verificationType == 'location' ||
        verificationType == 'location_focus' ||
        verificationType == 'location_partner' ||
        verificationType == 'location_focus_partner';
  }

  int calculateCompletionAward({
    required int basePoints,
    required String verificationType,
  }) {
    var award = basePoints <= 0 ? 0 : basePoints;

    if (_isFocusVerification(verificationType)) {
      award += 4;
    }

    if (_isLocationVerification(verificationType)) {
      award += 3;
    }

    if (_isPartnerVerification(verificationType)) {
      award += 5;
    }

    return award;
  }

  int calculatePenalty({
    required int penaltyPoints,
    required String penaltyReason,
  }) {
    final base = penaltyPoints <= 0 ? 0 : penaltyPoints;

    switch (penaltyReason) {
      case 'abandoned':
        return -(base + 4);
      case 'failed':
        return -(base + 3);
      case 'rejected':
        return -(base + 2);
      case 'missed':
        return -base;
      default:
        return -base;
    }
  }

  Future<Map<String, dynamic>?> _fetchStatsRow(String userId) async {
    final row = await _supabase
        .from('user_discipline_stats')
        .select('''
          user_id,
          execution_points,
          current_streak,
          best_streak,
          total_completed,
          total_failed,
          total_missed,
          clean_sessions
        ''')
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  Future<void> _ensureStatsRowExists(String userId) async {
    final existing = await _supabase
        .from('user_discipline_stats')
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) return;

    await _supabase.from('user_discipline_stats').insert({
      'user_id': userId,
      'execution_points': 0,
      'current_streak': 0,
      'best_streak': 0,
      'total_completed': 0,
      'total_failed': 0,
      'total_missed': 0,
      'clean_sessions': 0,
    });
  }

  Future<void> _ensurePointLedgerTableCanBeUsed() async {
    // Intentionally no-op.
    // Ledger writes are attempted defensively in _insertLedgerEvent.
  }

  Future<bool> _hasLedgerEvent({
    required String userId,
    required String logId,
    required String eventType,
  }) async {
    try {
      final row = await _supabase
          .from('point_events')
          .select('point_event_id')
          .eq('user_id', userId)
          .eq('log_id', logId)
          .eq('event_type', eventType)
          .maybeSingle();

      return row != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _insertLedgerEvent({
    required String userId,
    required String logId,
    required String habitId,
    required int pointsDelta,
    required String eventType,
    required String reason,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _ensurePointLedgerTableCanBeUsed();

      await _supabase.from('point_events').insert({
        'user_id': userId,
        'log_id': logId,
        'habit_id': habitId,
        'points_delta': pointsDelta,
        'event_type': eventType,
        'reason': reason,
        'metadata': metadata ?? <String, dynamic>{},
      });
    } catch (_) {
      // Keep the app working even if the ledger table is not present yet.
    }
  }

  Future<void> _updateStats({
    required String userId,
    required int pointsDelta,
    required int completedDelta,
    required int failedDelta,
    required int missedDelta,
    required int cleanSessionsDelta,
    int? currentStreakOverride,
    int? bestStreakOverride,
  }) async {
    await _ensureStatsRowExists(userId);
    final current = await _fetchStatsRow(userId);

    final currentPoints = _coerceInt(current?['execution_points']);
    final currentCompleted = _coerceInt(current?['total_completed']);
    final currentFailed = _coerceInt(current?['total_failed']);
    final currentMissed = _coerceInt(current?['total_missed']);
    final currentCleanSessions = _coerceInt(current?['clean_sessions']);
    final currentStreak = _coerceInt(current?['current_streak']);
    final bestStreak = _coerceInt(current?['best_streak']);

    final nextPoints = currentPoints + pointsDelta;
    final nextCompleted = currentCompleted + completedDelta;
    final nextFailed = currentFailed + failedDelta;
    final nextMissed = currentMissed + missedDelta;
    final nextCleanSessions = currentCleanSessions + cleanSessionsDelta;

    final resolvedCurrentStreak = currentStreakOverride ?? currentStreak;
    final resolvedBestStreak = bestStreakOverride ??
        (resolvedCurrentStreak > bestStreak ? resolvedCurrentStreak : bestStreak);

    await _supabase
        .from('user_discipline_stats')
        .update({
          'execution_points': nextPoints < 0 ? 0 : nextPoints,
          'total_completed': nextCompleted < 0 ? 0 : nextCompleted,
          'total_failed': nextFailed < 0 ? 0 : nextFailed,
          'total_missed': nextMissed < 0 ? 0 : nextMissed,
          'clean_sessions': nextCleanSessions < 0 ? 0 : nextCleanSessions,
          'current_streak':
              resolvedCurrentStreak < 0 ? 0 : resolvedCurrentStreak,
          'best_streak': resolvedBestStreak < 0 ? 0 : resolvedBestStreak,
        })
        .eq('user_id', userId);
  }

  Future<void> _updateProfileLevelAndTitle(String userId) async {
    final stats = await _fetchStatsRow(userId);
    final xp = _coerceInt(stats?['execution_points']);

    final level = _levelFromXp(xp);
    final title = _titleFromLevel(level);

    await _supabase.from('profiles').update({
      'prestige_level': level,
      'current_title': title,
    }).eq('id', userId);
  }

  int _levelFromXp(int xp) {
    if (xp >= 2500) return 10;
    if (xp >= 1800) return 9;
    if (xp >= 1300) return 8;
    if (xp >= 900) return 7;
    if (xp >= 600) return 6;
    if (xp >= 400) return 5;
    if (xp >= 250) return 4;
    if (xp >= 140) return 3;
    if (xp >= 60) return 2;
    return 1;
  }

  String _titleFromLevel(int level) {
    switch (level) {
      case 10:
        return 'Mythic';
      case 9:
        return 'Elite';
      case 8:
        return 'Relentless';
      case 7:
        return 'Unbreakable';
      case 6:
        return 'Disciplined';
      case 5:
        return 'Sharpened';
      case 4:
        return 'Consistent';
      case 3:
        return 'Builder';
      case 2:
        return 'Rising';
      default:
        return 'Starter';
    }
  }

  Future<void> applyCompletionPoints({
    required String userId,
    required String logId,
    required String habitId,
    required int basePoints,
    required String verificationType,
  }) async {
    const eventType = 'completion_award';

    final alreadyApplied = await _hasLedgerEvent(
      userId: userId,
      logId: logId,
      eventType: eventType,
    );

    if (alreadyApplied) return;

    final awarded = calculateCompletionAward(
      basePoints: basePoints,
      verificationType: verificationType,
    );

    final stats = await _fetchStatsRow(userId);
    final currentStreak = _coerceInt(stats?['current_streak']) + 1;
    final bestStreak = _coerceInt(stats?['best_streak']);
    final nextBestStreak = currentStreak > bestStreak ? currentStreak : bestStreak;

    await _updateStats(
      userId: userId,
      pointsDelta: awarded,
      completedDelta: 1,
      failedDelta: 0,
      missedDelta: 0,
      cleanSessionsDelta: _isFocusVerification(verificationType) ? 1 : 0,
      currentStreakOverride: currentStreak,
      bestStreakOverride: nextBestStreak,
    );

    await _insertLedgerEvent(
      userId: userId,
      logId: logId,
      habitId: habitId,
      pointsDelta: awarded,
      eventType: eventType,
      reason: verificationType,
      metadata: {
        'base_points': basePoints,
        'verification_type': verificationType,
      },
    );

    await _updateProfileLevelAndTitle(userId);
  }

  Future<void> applyPenaltyPoints({
    required String userId,
    required String logId,
    required String habitId,
    required int penaltyPoints,
    required String penaltyReason,
  }) async {
    final eventType = 'penalty_$penaltyReason';

    final alreadyApplied = await _hasLedgerEvent(
      userId: userId,
      logId: logId,
      eventType: eventType,
    );

    if (alreadyApplied) return;

    final penaltyDelta = calculatePenalty(
      penaltyPoints: penaltyPoints,
      penaltyReason: penaltyReason,
    );

    await _updateStats(
      userId: userId,
      pointsDelta: penaltyDelta,
      completedDelta: 0,
      failedDelta: penaltyReason == 'failed' || penaltyReason == 'abandoned' || penaltyReason == 'rejected' ? 1 : 0,
      missedDelta: penaltyReason == 'missed' ? 1 : 0,
      cleanSessionsDelta: 0,
      currentStreakOverride: 0,
    );

    await _insertLedgerEvent(
      userId: userId,
      logId: logId,
      habitId: habitId,
      pointsDelta: penaltyDelta,
      eventType: eventType,
      reason: penaltyReason,
      metadata: {
        'penalty_points': penaltyPoints,
      },
    );

    await _updateProfileLevelAndTitle(userId);
  }

  Future<int> fetchCurrentPoints(String userId) async {
    final stats = await _fetchStatsRow(userId);
    return _coerceInt(stats?['execution_points']);
  }

  Future<Map<String, dynamic>?> fetchStats(String userId) async {
    return _fetchStatsRow(userId);
  }
}