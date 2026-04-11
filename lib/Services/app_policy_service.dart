// ignore_for_file: dead_code

import 'package:supabase_flutter/supabase_flutter.dart';

class AppPolicyService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Set<String> _achievrAppIds = {
    'com.example.achievr_app',
    'com.achievr.app',
    'achievr',
  };

  static const int _maxAllowedAppsPerHabit = 2;

  String get _userId {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('No authenticated user found.');
    }
    return user.id;
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
          verification_type,
          verification_locked,
          evidence_type,
          active,
          duration_minutes,
          min_valid_minutes
        ''')
        .eq('habit_id', habitId)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  bool _habitSupportsAppPolicy(Map<String, dynamic> habit) {
    final verificationType =
        (habit['verification_type'] ?? '').toString().trim();

    return verificationType == 'focus_auto' ||
        verificationType == 'focus_partner' ||
        verificationType == 'location_focus' ||
        verificationType == 'location_focus_partner';
  }

  Future<Map<String, dynamic>?> fetchHabitAppPolicy({
    required String habitId,
  }) async {
    final response = await _supabase
        .from('habit_app_policies')
        .select('''
          habit_app_policy_id,
          habit_id,
          user_id,
          policy_mode,
          leave_grace_seconds,
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

  Future<List<Map<String, dynamic>>> fetchAllowedAppsForHabit({
    required String habitId,
  }) async {
    final response = await _supabase
        .from('habit_allowed_apps')
        .select('''
          habit_allowed_app_id,
          habit_id,
          user_id,
          app_identifier,
          app_label,
          active,
          created_at
        ''')
        .eq('habit_id', habitId)
        .eq('active', true)
        .order('app_label', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> fetchFullAppPolicyForHabit({
    required String habitId,
  }) async {
    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    if (!_habitSupportsAppPolicy(habit)) {
      throw Exception(
        'This habit does not use focus-based verification, so app policies do not apply.',
      );
    }

    final snapshot = await buildFocusSessionPolicySnapshot(habitId: habitId);

    return {
      'habit': habit,
      'policy': {
        'policy_mode': snapshot['app_policy_mode'],
        'leave_grace_seconds': snapshot['leave_grace_seconds'],
      },
      'allowed_apps': snapshot['allowed_apps_full'],
      'supports_app_policy': true,
      'screen_off_allowed': snapshot['allow_screen_off'],
      'is_default_policy': snapshot['is_default_policy'],
      'max_allowed_apps': _maxAllowedAppsPerHabit,
    };
  }

  Future<void> upsertHabitAppPolicy({
    required String habitId,
    required String policyMode,
    required int leaveGraceSeconds,
    required bool allowScreenOff,
  }) async {
    final userId = _userId;

    _validatePolicyMode(policyMode);

    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    if (!_habitSupportsAppPolicy(habit)) {
      throw Exception(
        'This habit does not support app policy configuration because it is not focus-based.',
      );
    }

    final computedGraceSeconds = _computeGraceSecondsFromHabit(habit);

    await _supabase.from('habit_app_policies').upsert(
      {
        'habit_id': habitId,
        'user_id': userId,
        'policy_mode': policyMode,
        'leave_grace_seconds': computedGraceSeconds,
        'active': true,
      },
      onConflict: 'habit_id',
    );
  }

  Future<void> syncComputedGraceForHabit({
    required String habitId,
  }) async {
    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    if (!_habitSupportsAppPolicy(habit)) {
      return;
    }

    final existing = await fetchHabitAppPolicy(habitId: habitId);
    if (existing == null) return;

    final computedGraceSeconds = _computeGraceSecondsFromHabit(habit);

    await _supabase.from('habit_app_policies').update({
      'leave_grace_seconds': computedGraceSeconds,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('habit_id', habitId);
  }

  Future<void> removeHabitAppPolicy({
    required String habitId,
  }) async {
    await _supabase
        .from('habit_app_policies')
        .delete()
        .eq('habit_id', habitId);
  }

  Future<void> addAllowedAppToHabit({
    required String habitId,
    required String appIdentifier,
    required String appLabel,
  }) async {
    final userId = _userId;

    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    if (!_habitSupportsAppPolicy(habit)) {
      throw Exception(
        'This habit does not support app allow-list configuration.',
      );
    }

    final snapshot = await buildFocusSessionPolicySnapshot(habitId: habitId);
    final policyMode = (snapshot['app_policy_mode'] ?? '').toString();

    if (policyMode != 'allow_list') {
      throw Exception(
        'Allowed apps can only be managed when policy mode is allow_list.',
      );
    }

    if (appIdentifier.trim().isEmpty || appLabel.trim().isEmpty) {
      throw Exception('App identifier and app label are required.');
    }

    final currentApps = await fetchAllowedAppsForHabit(habitId: habitId);
    final existingPackages = currentApps
        .map((app) => (app['app_identifier'] ?? '').toString())
        .toSet();

    if (!existingPackages.contains(appIdentifier.trim()) &&
        currentApps.length >= _maxAllowedAppsPerHabit) {
      throw Exception('You can only allow up to 2 apps for a focus habit.');
    }

    await _supabase.from('habit_allowed_apps').upsert({
      'habit_id': habitId,
      'user_id': userId,
      'app_identifier': appIdentifier.trim(),
      'app_label': appLabel.trim(),
      'active': true,
    });
  }

  Future<void> removeAllowedAppFromHabit({
    required String habitId,
    required String appIdentifier,
  }) async {
    await _supabase
        .from('habit_allowed_apps')
        .delete()
        .eq('habit_id', habitId)
        .eq('app_identifier', appIdentifier);
  }

  Future<void> replaceAllowedAppsForHabit({
    required String habitId,
    required List<Map<String, String>> apps,
  }) async {
    final snapshot = await buildFocusSessionPolicySnapshot(habitId: habitId);
    final policyMode = (snapshot['app_policy_mode'] ?? '').toString();

    if (policyMode != 'allow_list') {
      throw Exception(
        'Allowed apps can only be saved when policy mode is allow_list.',
      );
    }

    final cleanedApps = apps
        .where(
          (app) =>
              (app['app_identifier'] ?? '').trim().isNotEmpty &&
              (app['app_label'] ?? '').trim().isNotEmpty,
        )
        .toList();

    if (cleanedApps.length > _maxAllowedAppsPerHabit) {
      throw Exception('You can only allow up to 2 apps for a focus habit.');
    }

    await _supabase
        .from('habit_allowed_apps')
        .delete()
        .eq('habit_id', habitId);

    if (cleanedApps.isEmpty) return;

    final userId = _userId;

    final inserts = cleanedApps
        .map(
          (app) => {
            'habit_id': habitId,
            'user_id': userId,
            'app_identifier': app['app_identifier']!.trim(),
            'app_label': app['app_label']!.trim(),
            'active': true,
          },
        )
        .toList();

    if (inserts.isNotEmpty) {
      await _supabase.from('habit_allowed_apps').insert(inserts);
    }
  }

  Future<Map<String, dynamic>> assertCanRunFocusWithApp({
    required String habitId,
    required String foregroundAppIdentifier,
    required bool isScreenOff,
  }) async {
    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    if (!_habitSupportsAppPolicy(habit)) {
      return {
        'allowed': true,
        'reason': 'No app policy required for this habit.',
      };
    }

    final snapshot = await buildFocusSessionPolicySnapshot(habitId: habitId);

    final policyMode =
        (snapshot['app_policy_mode'] ?? 'achievr_only').toString();
    final allowScreenOff =
        (snapshot['allow_screen_off'] as bool?) ?? true;

    if (isScreenOff) {
      return {
        'allowed': allowScreenOff,
        'reason': allowScreenOff
            ? 'Screen off is allowed for this session.'
            : 'Screen off is not allowed for this session.',
      };
    }

    if (_achievrAppIds.contains(foregroundAppIdentifier)) {
      return {
        'allowed': true,
        'reason': 'Achievr is always allowed.',
      };
    }

    if (policyMode == 'achievr_only') {
      return {
        'allowed': false,
        'reason': 'Only Achievr is allowed during this session.',
      };
    }

    if (policyMode == 'allow_list') {
      final allowedIdentifiers =
          (snapshot['allowed_app_identifiers'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toSet();

      final isAllowed = allowedIdentifiers.contains(foregroundAppIdentifier);

      return {
        'allowed': isAllowed,
        'reason': isAllowed
            ? 'This app is on the allowed list.'
            : 'This app is not on the allowed list for this session.',
      };
    }

    return {
      'allowed': false,
      'reason': 'Unknown app policy mode.',
    };
  }

  Future<Map<String, dynamic>> buildFocusSessionPolicySnapshot({
    required String habitId,
  }) async {
    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    if (!_habitSupportsAppPolicy(habit)) {
      return {
        'app_policy_mode': null,
        'leave_grace_seconds': 0,
        'allow_screen_off': true,
        'allowed_app_identifiers': const <String>[],
        'allowed_app_labels': const <String>[],
        'allowed_apps_full': const <Map<String, dynamic>>[],
        'is_default_policy': false,
        'max_allowed_apps': _maxAllowedAppsPerHabit,
      };
    }

    final policy = await fetchHabitAppPolicy(habitId: habitId);
    final allowedApps = await fetchAllowedAppsForHabit(habitId: habitId);

    final resolvedMode = _resolveEffectivePolicyMode(policy);
    final computedGraceSeconds = _computeGraceSecondsFromHabit(habit);
    final storedGraceSeconds =
        _coerceInt(policy?['leave_grace_seconds']) ?? computedGraceSeconds;

    final effectiveGraceSeconds =
        storedGraceSeconds > 0 ? storedGraceSeconds : computedGraceSeconds;

    return {
      'app_policy_mode': resolvedMode,
      'leave_grace_seconds': effectiveGraceSeconds,
      'allow_screen_off': true,
      'allowed_app_identifiers': allowedApps
          .map((app) => (app['app_identifier'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList(),
      'allowed_app_labels': allowedApps
          .map((app) => (app['app_label'] ?? '').toString())
          .where((label) => label.isNotEmpty)
          .toList(),
      'allowed_apps_full': allowedApps,
      'is_default_policy': policy == null,
      'max_allowed_apps': _maxAllowedAppsPerHabit,
    };
  }

  int _computeGraceSecondsFromHabit(Map<String, dynamic> habit) {
    final minValidMinutes = _coerceInt(habit['min_valid_minutes']);
    final durationMinutes = _coerceInt(habit['duration_minutes']);

    final requiredMinutes = (minValidMinutes != null && minValidMinutes > 0)
        ? minValidMinutes
        : (durationMinutes != null && durationMinutes > 0)
            ? durationMinutes
            : 12;

    final derivedGraceMinutes = (requiredMinutes / 12).round().clamp(1, 10);
    return derivedGraceMinutes * 60;
  }

  String _resolveEffectivePolicyMode(Map<String, dynamic>? policy) {
    final raw = (policy?['policy_mode'] ?? '').toString().trim();

    if (raw == 'achievr_only' || raw == 'allow_list') {
      return raw;
    }

    return 'achievr_only';
  }

  void _validatePolicyMode(String policyMode) {
    if (policyMode != 'achievr_only' && policyMode != 'allow_list') {
      throw Exception(
        'Only achievr_only and allow_list are supported right now.',
      );
    }
  }

  int? _coerceInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString());
  }
}