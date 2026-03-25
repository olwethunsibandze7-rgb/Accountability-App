import 'package:supabase_flutter/supabase_flutter.dart';

class VerificationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String get _userId {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('No authenticated user found.');
    }
    return user.id;
  }

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
        .select('habit_id, goal_id, title, verification_type, active')
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

      results.add({
        ...habit,
        'goal': goalMap[goalId],
        'verifier': verifier,
      });
    }

    return results;
  }

  Future<void> updateHabitVerificationType({
    required String habitId,
    required String verificationType,
  }) async {
    await _supabase
        .from('habits')
        .update({'verification_type': verificationType})
        .eq('habit_id', habitId);

    await _supabase
        .from('habit_logs')
        .update({'verification_type': verificationType})
        .eq('habit_id', habitId)
        .inFilter('status', ['pending', 'awaiting_verification']);
  }

  Future<void> assignVerifierToHabit({
    required String habitId,
    required String verifierUserId,
  }) async {
    final userId = _userId;

    await _supabase.from('habit_verifiers').upsert({
      'habit_id': habitId,
      'verifier_user_id': verifierUserId,
      'assigned_by_user_id': userId,
      'active': true,
    });

    await updateHabitVerificationType(
      habitId: habitId,
      verificationType: 'partner',
    );
  }

  Future<void> switchHabitToManual({
    required String habitId,
  }) async {
    await _supabase
        .from('habit_verifiers')
        .delete()
        .eq('habit_id', habitId);

    await updateHabitVerificationType(
      habitId: habitId,
      verificationType: 'manual',
    );
  }

  Future<void> removeVerifierFromHabit({
    required String habitId,
  }) async {
    await _supabase
        .from('habit_verifiers')
        .delete()
        .eq('habit_id', habitId);
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
          submitted_at,
          reviewed_at
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
          submitted_at,
          reviewed_at
        ''')
        .eq('requester_user_id', userId)
        .order('submitted_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> submitLogForVerification({
    required String logId,
    required String habitId,
    String? note,
  }) async {
    final userId = _userId;

    final verifier = await fetchHabitVerifier(habitId: habitId);
    if (verifier == null) {
      throw Exception('No verifier is assigned to this habit.');
    }

    final verifierUserId = verifier['verifier_user_id'].toString();

    await _supabase.from('log_verification_requests').upsert({
      'log_id': logId,
      'habit_id': habitId,
      'requester_user_id': userId,
      'verifier_user_id': verifierUserId,
      'status': 'pending',
      'note': note,
    });

    await _supabase.from('habit_logs').update({
      'status': 'awaiting_verification',
      'verification_type': 'partner',
    }).eq('log_id', logId);
  }

  Future<void> approveVerificationRequest({
    required String requestId,
    required String logId,
  }) async {
    await _supabase
        .from('log_verification_requests')
        .update({
          'status': 'approved',
          'reviewed_at': DateTime.now().toIso8601String(),
        })
        .eq('request_id', requestId);

    await _supabase.from('habit_logs').update({
      'status': 'done',
      'closed_at': DateTime.now().toIso8601String(),
    }).eq('log_id', logId);
  }

  Future<void> rejectVerificationRequest({
    required String requestId,
    required String logId,
  }) async {
    await _supabase
        .from('log_verification_requests')
        .update({
          'status': 'rejected',
          'reviewed_at': DateTime.now().toIso8601String(),
        })
        .eq('request_id', requestId);

    await _supabase.from('habit_logs').update({
      'status': 'pending',
      'verification_type': 'partner',
    }).eq('log_id', logId);
  }
}