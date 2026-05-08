// ignore_for_file: unused_element

import 'dart:math' as math;

import 'package:achievr_app/Services/badge_service.dart';
import 'package:achievr_app/Services/points_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VerificationService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final PointsService _pointsService = PointsService();
  final BadgeService _badgeService = BadgeService();

  String get _userId {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('No authenticated user found.');
    }
    return user.id;
  }

  // =========================================================
  // HABIT / CONFIG FETCHING
  // =========================================================

  Future<List<Map<String, dynamic>>> fetchMyActiveHabitsForVerification() async {
    final userId = _userId;

    final goalsResponse = await _supabase
        .from('goals')
        .select('goal_id, title')
        .eq('user_id', userId)
        .eq('active', true)
        .order('created_at', ascending: true);

    final goals = List<Map<String, dynamic>>.from(goalsResponse);
    if (goals.isEmpty) return [];

    final goalIds = goals.map((g) => g['goal_id'].toString()).toList();

    final habitsResponse = await _supabase
        .from('habits')
        .select('''
          habit_id,
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
          active
        ''')
        .inFilter('goal_id', goalIds)
        .eq('active', true)
        .order('created_at', ascending: true);

    final habits = List<Map<String, dynamic>>.from(habitsResponse);

    final goalMap = {
      for (final goal in goals) goal['goal_id'].toString(): goal,
    };

    final results = <Map<String, dynamic>>[];

    for (final habit in habits) {
      final goalId = habit['goal_id'].toString();

      final verifier = await fetchHabitVerifier(
        habitId: habit['habit_id'].toString(),
      );

      final locationConfig = await fetchHabitLocationConfig(
        habitId: habit['habit_id'].toString(),
      );

      results.add({
        ...habit,
        'goal': goalMap[goalId],
        'verifier': verifier,
        'location_config': locationConfig,
        'can_change_verification': false,
        'can_manage_verifier': _habitNeedsVerifier(habit),
        'can_manage_location': _habitNeedsLocation(habit),
      });
    }

    return results;
  }

  Future<Map<String, dynamic>?> fetchHabitById({
    required String habitId,
  }) async {
    final response = await _supabase
        .from('habits')
        .select('''
          habit_id,
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
          active
        ''')
        .eq('habit_id', habitId)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>?> fetchHabitVerifier({
    required String habitId,
  }) async {
    final response = await _supabase
        .from('habit_verifiers')
        .select('''
          habit_verifier_id,
          habit_id,
          verifier_user_id,
          assigned_by_user_id,
          active,
          created_at
        ''')
        .eq('habit_id', habitId)
        .eq('active', true)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>?> fetchHabitLocationConfig({
    required String habitId,
  }) async {
    final response = await _supabase
        .from('habit_location_configs')
        .select('''
          habit_location_config_id,
          habit_id,
          user_id,
          label,
          latitude,
          longitude,
          radius_meters,
          active,
          created_at,
          updated_at
        ''')
        .eq('habit_id', habitId)
        .eq('active', true)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>?> fetchEvidenceSnapshot({
    required String evidenceSnapshotId,
  }) async {
    final response = await _supabase
        .from('verification_evidence_snapshots')
        .select('''
          evidence_snapshot_id,
          log_id,
          habit_id,
          user_id,
          focus_session_id,
          evidence_type,
          scheduled_minutes,
          required_valid_minutes,
          actual_valid_minutes,
          completion_ratio,
          interruption_count,
          exit_count,
          threshold_met,
          user_note,
          photo_url,
          created_at
        ''')
        .eq('evidence_snapshot_id', evidenceSnapshotId)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  // =========================================================
  // SETUP RULES
  // =========================================================

  bool _habitNeedsVerifier(Map<String, dynamic> habit) {
    final verificationType =
        (habit['verification_type'] ?? '').toString().trim();
    final requiresVerifier = (habit['requires_verifier'] as bool?) ?? false;

    return requiresVerifier ||
        verificationType == 'partner' ||
        verificationType == 'focus_partner' ||
        verificationType == 'location_partner' ||
        verificationType == 'location_focus_partner';
  }

  bool _habitNeedsLocation(Map<String, dynamic> habit) {
    final verificationType =
        (habit['verification_type'] ?? '').toString().trim();
    final evidenceType = (habit['evidence_type'] ?? '').toString().trim();

    return verificationType == 'location' ||
        verificationType == 'location_focus' ||
        verificationType == 'location_partner' ||
        verificationType == 'location_focus_partner' ||
        evidenceType.contains('location');
  }

  bool _habitNeedsFocus(Map<String, dynamic> habit) {
    final verificationType =
        (habit['verification_type'] ?? '').toString().trim();

    return verificationType == 'focus_auto' ||
        verificationType == 'focus_partner' ||
        verificationType == 'location_focus' ||
        verificationType == 'location_focus_partner';
  }

  Future<void> assignVerifierToHabit({
    required String habitId,
    required String verifierUserId,
  }) async {
    final userId = _userId;

    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    if (!_habitNeedsVerifier(habit)) {
      throw Exception(
        'This habit does not use partner verification. Verification is fixed by the task template.',
      );
    }

    await _supabase.from('habit_verifiers').upsert({
      'habit_id': habitId,
      'verifier_user_id': verifierUserId,
      'assigned_by_user_id': userId,
      'active': true,
    });
  }

  Future<void> removeVerifierFromHabit({
    required String habitId,
  }) async {
    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    if (_habitNeedsVerifier(habit)) {
      throw Exception(
        'This habit requires a verifier. You can change the assigned verifier, but you cannot remove verification because it is fixed by the template.',
      );
    }

    await _supabase.from('habit_verifiers').delete().eq('habit_id', habitId);
  }

  Future<void> upsertHabitLocationConfig({
    required String habitId,
    required String label,
    required double latitude,
    required double longitude,
    required int radiusMeters,
  }) async {
    final userId = _userId;

    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    if (!_habitNeedsLocation(habit)) {
      throw Exception(
        'This habit does not use location verification. Location rules are fixed by the task template.',
      );
    }

    if (label.trim().isEmpty) {
      throw Exception('Location label is required.');
    }

    if (radiusMeters < 25 || radiusMeters > 1000) {
      throw Exception('Radius must be between 25 and 1000 meters.');
    }

    await _supabase.from('habit_location_configs').upsert({
      'habit_id': habitId,
      'user_id': userId,
      'label': label.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'active': true,
    });
  }

  Future<void> removeHabitLocationConfig({
    required String habitId,
  }) async {
    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    if (_habitNeedsLocation(habit)) {
      throw Exception(
        'This habit requires a pinned location. You can update the location, but you cannot remove location gating because it is fixed by the template.',
      );
    }

    await _supabase
        .from('habit_location_configs')
        .delete()
        .eq('habit_id', habitId);
  }

  // =========================================================
  // LOCATION / FOCUS ELIGIBILITY HELPERS
  // =========================================================

  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }

  double _distanceMeters({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) {
    const earthRadiusMeters = 6371000.0;

    final dLat = _degreesToRadians(endLat - startLat);
    final dLng = _degreesToRadians(endLng - startLng);

    final a = math.pow(math.sin(dLat / 2), 2).toDouble() +
        math.cos(_degreesToRadians(startLat)) *
            math.cos(_degreesToRadians(endLat)) *
            math.pow(math.sin(dLng / 2), 2).toDouble();

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  Future<bool> isWithinHabitLocationRadius({
    required String habitId,
    required double currentLatitude,
    required double currentLongitude,
  }) async {
    final locationConfig = await fetchHabitLocationConfig(habitId: habitId);

    if (locationConfig == null) {
      return false;
    }

    final targetLat = _coerceDouble(locationConfig['latitude']);
    final targetLng = _coerceDouble(locationConfig['longitude']);
    final radiusMeters = _coerceInt(locationConfig['radius_meters']);

    if (targetLat == null || targetLng == null || radiusMeters == null) {
      return false;
    }

    final distance = _distanceMeters(
      startLat: currentLatitude,
      startLng: currentLongitude,
      endLat: targetLat,
      endLng: targetLng,
    );

    return distance <= radiusMeters;
  }

  Future<void> assertLocationEligible({
    required String habitId,
    required double currentLatitude,
    required double currentLongitude,
  }) async {
    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    if (!_habitNeedsLocation(habit)) {
      return;
    }

    final locationConfig = await fetchHabitLocationConfig(habitId: habitId);
    if (locationConfig == null) {
      throw Exception(
        'This habit requires a pinned verification location before it can be completed.',
      );
    }

    final insideRadius = await isWithinHabitLocationRadius(
      habitId: habitId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
    );

    if (!insideRadius) {
      final label = (locationConfig['label'] ?? 'required location').toString();
      throw Exception(
        'You must be within the allowed radius of $label to verify this task.',
      );
    }
  }

  Future<void> assertCanStartFocusForHabit({
    required String habitId,
    required double currentLatitude,
    required double currentLongitude,
  }) async {
    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    if (!_habitNeedsFocus(habit)) {
      throw Exception('This habit does not use focus-based verification.');
    }

    if (_habitNeedsLocation(habit)) {
      await assertLocationEligible(
        habitId: habitId,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
      );
    }
  }

  // =========================================================
  // VERIFICATION REQUESTS
  // =========================================================

  Future<List<Map<String, dynamic>>> fetchMyAssignedVerificationRequests() async {
    final userId = _userId;

    final response = await _supabase
        .from('log_verification_requests')
        .select('''
          request_id,
          log_id,
          habit_id,
          requester_user_id,
          verifier_user_id,
          status,
          note,
          decision_note,
          threshold_met,
          auto_eligible,
          submitted_at,
          reviewed_at,
          focus_session_id,
          evidence_snapshot_id
        ''')
        .eq('verifier_user_id', userId)
        .order('submitted_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> fetchMySubmittedVerificationRequests() async {
    final userId = _userId;

    final response = await _supabase
        .from('log_verification_requests')
        .select('''
          request_id,
          log_id,
          habit_id,
          requester_user_id,
          verifier_user_id,
          status,
          note,
          decision_note,
          threshold_met,
          auto_eligible,
          submitted_at,
          reviewed_at,
          focus_session_id,
          evidence_snapshot_id
        ''')
        .eq('requester_user_id', userId)
        .order('submitted_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> submitLogForVerification({
    required String logId,
    required String habitId,
    String? note,
    double? currentLatitude,
    double? currentLongitude,
  }) async {
    final userId = _userId;

    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    final verificationType =
        (habit['verification_type'] ?? '').toString().trim();

    final isPartnerFlow =
        verificationType == 'partner' ||
            verificationType == 'focus_partner' ||
            verificationType == 'location_partner' ||
            verificationType == 'location_focus_partner';

    if (!isPartnerFlow) {
      throw Exception(
        'This habit does not use partner verification. Verification is fixed by the task template.',
      );
    }

    final verifier = await fetchHabitVerifier(habitId: habitId);
    if (verifier == null) {
      throw Exception('No verifier is assigned to this habit.');
    }

    if (_habitNeedsLocation(habit)) {
      if (currentLatitude == null || currentLongitude == null) {
        throw Exception(
          'Current location is required for this verification method.',
        );
      }

      await assertLocationEligible(
        habitId: habitId,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
      );
    }

    final logResponse = await _supabase
        .from('habit_logs')
        .select('''
          log_id,
          habit_id,
          user_id,
          status,
          evidence_type,
          required_valid_minutes
        ''')
        .eq('log_id', logId)
        .maybeSingle();

    if (logResponse == null) {
      throw Exception('Habit log not found.');
    }

    final log = Map<String, dynamic>.from(logResponse);

    if (log['user_id']?.toString() != userId) {
      throw Exception('You can only submit your own logs for verification.');
    }

    final currentStatus = (log['status'] ?? '').toString();
    const allowedStatuses = {
      'pending',
      'in_progress',
      'ready',
      'failed',
      'rejected',
    };

    if (currentStatus.isNotEmpty &&
        currentStatus != 'pending_verification' &&
        !allowedStatuses.contains(currentStatus)) {
      throw Exception('This log cannot be submitted from status: $currentStatus');
    }

    final existingPending = await _supabase
        .from('log_verification_requests')
        .select('request_id')
        .eq('log_id', logId)
        .eq('status', 'pending')
        .maybeSingle();

    if (existingPending != null) {
      throw Exception('This log already has a pending verification request.');
    }

    String? focusSessionId;
    bool thresholdMet = false;
    bool autoEligible = false;
    String? evidenceSnapshotId;

    final requiresFocus =
        verificationType == 'focus_partner' ||
            verificationType == 'location_focus_partner';

    if (requiresFocus) {
      final focusResponse = await _supabase
          .from('focus_sessions')
          .select('''
            focus_session_id,
            status,
            threshold_met,
            valid_focus_seconds,
            interruption_count,
            exit_count
          ''')
          .eq('log_id', logId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (focusResponse == null) {
        throw Exception('No focus session evidence found for this task.');
      }

      final focus = Map<String, dynamic>.from(focusResponse);
      focusSessionId = focus['focus_session_id']?.toString();
      thresholdMet = (focus['threshold_met'] as bool?) ?? false;
      autoEligible = thresholdMet;

      if (!thresholdMet) {
        throw Exception(
          'Focus threshold not met yet. This task cannot be submitted for partner verification.',
        );
      }

      final habitDurationMinutes = _coerceInt(habit['duration_minutes']);
      final requiredValidMinutes = _coerceInt(habit['min_valid_minutes']) ??
          _coerceInt(log['required_valid_minutes']);
      final actualValidMinutes =
          ((_coerceInt(focus['valid_focus_seconds']) ?? 0) / 60).floor();

      final evidenceInsert = await _supabase
          .from('verification_evidence_snapshots')
          .insert({
            'log_id': logId,
            'habit_id': habitId,
            'user_id': userId,
            'focus_session_id': focusSessionId,
            'evidence_type': habit['evidence_type'] ?? 'focus_summary',
            'scheduled_minutes': habitDurationMinutes,
            'required_valid_minutes': requiredValidMinutes,
            'actual_valid_minutes': actualValidMinutes,
            'completion_ratio': (habitDurationMinutes != null &&
                    habitDurationMinutes > 0)
                ? actualValidMinutes / habitDurationMinutes
                : null,
            'interruption_count': _coerceInt(focus['interruption_count']) ?? 0,
            'exit_count': _coerceInt(focus['exit_count']) ?? 0,
            'threshold_met': thresholdMet,
            'user_note': note,
          })
          .select('evidence_snapshot_id')
          .single();

      evidenceSnapshotId = evidenceInsert['evidence_snapshot_id']?.toString();
    }

    final verifierUserId = verifier['verifier_user_id'].toString();

    await _supabase.from('log_verification_requests').insert({
      'log_id': logId,
      'habit_id': habitId,
      'requester_user_id': userId,
      'verifier_user_id': verifierUserId,
      'status': 'pending',
      'note': note,
      'decision_note': null,
      'focus_session_id': focusSessionId,
      'evidence_snapshot_id': evidenceSnapshotId,
      'threshold_met': thresholdMet,
      'auto_eligible': autoEligible,
      'submitted_at': DateTime.now().toIso8601String(),
    });

    await _supabase.from('habit_logs').update({
      'status': 'pending_verification',
      'submitted_at': DateTime.now().toIso8601String(),
    }).eq('log_id', logId);
  }

  Future<void> approveVerificationRequest({
    required String requestId,
    required String logId,
    String? decisionNote,
  }) async {
    final reviewerUserId = _userId;

    final requestResponse = await _supabase
        .from('log_verification_requests')
        .select('''
          request_id,
          log_id,
          habit_id,
          requester_user_id,
          verifier_user_id,
          status
        ''')
        .eq('request_id', requestId)
        .maybeSingle();

    if (requestResponse == null) {
      throw Exception('Verification request not found.');
    }

    final request = Map<String, dynamic>.from(requestResponse);
    final habitId = request['habit_id']?.toString();
    final requesterUserId = request['requester_user_id']?.toString();
    final verifierUserId = request['verifier_user_id']?.toString();
    final status = (request['status'] ?? '').toString();

    if (habitId == null || requesterUserId == null || verifierUserId == null) {
      throw Exception('Verification request is missing required identifiers.');
    }

    if (verifierUserId != reviewerUserId) {
      throw Exception('You are not the assigned verifier for this request.');
    }

    if (status != 'pending') {
      throw Exception('This verification request is no longer pending.');
    }

    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    await _supabase
        .from('log_verification_requests')
        .update({
          'status': 'approved',
          'decision_note': decisionNote,
          'reviewed_at': DateTime.now().toIso8601String(),
        })
        .eq('request_id', requestId);

    await _supabase.from('habit_logs').update({
      'status': 'done',
      'closed_at': DateTime.now().toIso8601String(),
    }).eq('log_id', logId);

    final basePoints = _coerceInt(habit['base_points']) ?? 0;
    final verificationType =
        (habit['verification_type'] ?? 'partner').toString();

    await _pointsService.applyCompletionPoints(
      userId: requesterUserId,
      logId: logId,
      habitId: habitId,
      basePoints: basePoints,
      verificationType: verificationType,
    );

    await _badgeService.evaluateAndAwardCoreBadges(userId: requesterUserId);
  }

  Future<void> rejectVerificationRequest({
    required String requestId,
    required String logId,
    String? decisionNote,
  }) async {
    final reviewerUserId = _userId;

    final requestResponse = await _supabase
        .from('log_verification_requests')
        .select('''
          request_id,
          log_id,
          habit_id,
          requester_user_id,
          verifier_user_id,
          status
        ''')
        .eq('request_id', requestId)
        .maybeSingle();

    if (requestResponse == null) {
      throw Exception('Verification request not found.');
    }

    final request = Map<String, dynamic>.from(requestResponse);
    final habitId = request['habit_id']?.toString();
    final requesterUserId = request['requester_user_id']?.toString();
    final verifierUserId = request['verifier_user_id']?.toString();
    final status = (request['status'] ?? '').toString();

    if (habitId == null || requesterUserId == null || verifierUserId == null) {
      throw Exception('Verification request is missing required identifiers.');
    }

    if (verifierUserId != reviewerUserId) {
      throw Exception('You are not the assigned verifier for this request.');
    }

    if (status != 'pending') {
      throw Exception('This verification request is no longer pending.');
    }

    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    await _supabase
        .from('log_verification_requests')
        .update({
          'status': 'rejected',
          'decision_note': decisionNote,
          'reviewed_at': DateTime.now().toIso8601String(),
        })
        .eq('request_id', requestId);

    await _supabase.from('habit_logs').update({
      'status': 'rejected',
      'failed_at': DateTime.now().toIso8601String(),
      'failure_reason': decisionNote ?? 'Rejected by verifier',
    }).eq('log_id', logId);

    final penaltyPoints = _coerceInt(habit['penalty_points']) ?? 0;

    await _pointsService.applyPenaltyPoints(
      userId: requesterUserId,
      logId: logId,
      habitId: habitId,
      penaltyPoints: penaltyPoints,
      penaltyReason: 'rejected',
    );

    await _badgeService.evaluateAndAwardCoreBadges(userId: requesterUserId);
  }

  // =========================================================
  // TYPE HELPERS
  // =========================================================

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