import 'package:supabase_flutter/supabase_flutter.dart';

class AppPolicyService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Set<String> _achievrAppIds = {
    'com.example.achievr_app',
    'com.achievr.app',
    'achievr',
  };

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

    final rows = List<Map<String, dynamic>>.from(response);

    return rows.where((row) {
      final id = (row['app_identifier'] ?? '').toString().trim();
      return id.isNotEmpty && !_achievrAppIds.contains(id);
    }).toList();
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
      'allowed_apps': snapshot['selected_allowed_apps_full'],
      'supports_app_policy': true,
      'screen_off_allowed': snapshot['allow_screen_off'],
      'is_default_policy': snapshot['is_default_policy'],
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

    final safeGraceSeconds = leaveGraceSeconds.clamp(0, 3600);

    final habit = await fetchHabitById(habitId: habitId);
    if (habit == null) {
      throw Exception('Habit not found.');
    }

    if (!_habitSupportsAppPolicy(habit)) {
      throw Exception(
        'This habit does not support app policy configuration because it is not focus-based.',
      );
    }

    final existing = await fetchHabitAppPolicy(habitId: habitId);

    if (existing != null) {
      await _supabase
          .from('habit_app_policies')
          .update({
            'policy_mode': policyMode,
            'leave_grace_seconds': safeGraceSeconds,
            'active': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('habit_app_policy_id', existing['habit_app_policy_id']);
      return;
    }

    await _supabase.from('habit_app_policies').insert({
      'habit_id': habitId,
      'user_id': userId,
      'policy_mode': policyMode,
      'leave_grace_seconds': safeGraceSeconds,
      'active': true,
    });
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
    final cleanIdentifier = appIdentifier.trim();
    final cleanLabel = appLabel.trim();

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

    if (cleanIdentifier.isEmpty || cleanLabel.isEmpty) {
      throw Exception('App identifier and app label are required.');
    }

    if (_achievrAppIds.contains(cleanIdentifier)) {
      throw Exception('Achievr is already always allowed.');
    }

    final existingSelectedApps =
        List<Map<String, dynamic>>.from(
      snapshot['selected_allowed_apps_full'] ?? [],
    );

    if (existingSelectedApps.isNotEmpty) {
      throw Exception(
        'Only one extra app can be allowed for a focus habit. Remove the current one first.',
      );
    }

    await _supabase.from('habit_allowed_apps').insert({
      'habit_id': habitId,
      'user_id': userId,
      'app_identifier': cleanIdentifier,
      'app_label': cleanLabel,
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

    final filtered = apps
        .where(
          (app) =>
              (app['app_identifier'] ?? '').trim().isNotEmpty &&
              (app['app_label'] ?? '').trim().isNotEmpty &&
              !_achievrAppIds.contains((app['app_identifier'] ?? '').trim()),
        )
        .toList();

    if (filtered.length > 1) {
      throw Exception('Only one extra app can be allowed for a focus habit.');
    }

    await _supabase
        .from('habit_allowed_apps')
        .delete()
        .eq('habit_id', habitId);

    if (filtered.isEmpty) return;

    final userId = _userId;

    await _supabase.from('habit_allowed_apps').insert({
      'habit_id': habitId,
      'user_id': userId,
      'app_identifier': filtered.first['app_identifier']!.trim(),
      'app_label': filtered.first['app_label']!.trim(),
      'active': true,
    });
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
    final allowScreenOff = (snapshot['allow_screen_off'] as bool?) ?? true;
    final cleanForeground = foregroundAppIdentifier.trim();

    if (isScreenOff) {
      return {
        'allowed': allowScreenOff,
        'reason': allowScreenOff
            ? 'Screen off is allowed.'
            : 'Screen off is not allowed.',
      };
    }

    if (_achievrAppIds.contains(cleanForeground)) {
      return {
        'allowed': true,
        'reason': 'Achievr is always allowed.',
      };
    }

    if (policyMode == 'achievr_only') {
      return {
        'allowed': false,
        'reason': 'Only Achievr is allowed.',
      };
    }

    if (policyMode == 'allow_list') {
      final allowedIdentifiers =
          (snapshot['selected_allowed_app_identifiers'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toSet();

      final isAllowed = allowedIdentifiers.contains(cleanForeground);

      return {
        'allowed': isAllowed,
        'reason': isAllowed
            ? 'This app is allowed.'
            : 'This app is not allowed for this habit.',
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
        'selected_allowed_app_identifiers': const <String>[],
        'selected_allowed_app_labels': const <String>[],
        'selected_allowed_apps_full': const <Map<String, dynamic>>[],
        'is_default_policy': false,
      };
    }

    final policy = await fetchHabitAppPolicy(habitId: habitId);
    final selectedAllowedApps =
        await fetchAllowedAppsForHabit(habitId: habitId);

    final resolvedMode = _resolveEffectivePolicyMode(policy);
    final resolvedGraceSeconds =
        (_coerceInt(policy?['leave_grace_seconds']) ?? 30).clamp(0, 3600);

    final selectedIdentifiers = selectedAllowedApps
        .map((app) => (app['app_identifier'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();

    final selectedLabels = selectedAllowedApps
        .map((app) => (app['app_label'] ?? '').toString())
        .where((label) => label.isNotEmpty)
        .toList();

    return {
      'app_policy_mode': resolvedMode,
      'leave_grace_seconds': resolvedGraceSeconds,
      'allow_screen_off': true,
      'allowed_app_identifiers': [
        ..._achievrAppIds,
        ...selectedIdentifiers,
      ],
      'allowed_app_labels': [
        'Achievr',
        ...selectedLabels,
      ],
      'selected_allowed_app_identifiers': selectedIdentifiers,
      'selected_allowed_app_labels': selectedLabels,
      'selected_allowed_apps_full': selectedAllowedApps,
      'is_default_policy': policy == null,
    };
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