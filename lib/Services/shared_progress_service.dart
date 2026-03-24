import 'package:supabase_flutter/supabase_flutter.dart';

class SharedProgressService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String get _userId {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('No authenticated user found.');
    }
    return user.id;
  }

  Future<List<Map<String, dynamic>>> fetchMySharingPermissions() async {
    final userId = _userId;

    final response = await _supabase
        .from('shared_progress_permissions')
        .select('''
          permission_id,
          owner_user_id,
          viewer_user_id,
          can_view_progress,
          can_view_goal_titles,
          can_view_habit_titles,
          created_at,
          updated_at
        ''')
        .eq('owner_user_id', userId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> upsertSharingPermission({
    required String viewerUserId,
    required bool canViewProgress,
    required bool canViewGoalTitles,
    required bool canViewHabitTitles,
  }) async {
    final userId = _userId;

    await _supabase.from('shared_progress_permissions').upsert({
      'owner_user_id': userId,
      'viewer_user_id': viewerUserId,
      'can_view_progress': canViewProgress,
      'can_view_goal_titles': canViewGoalTitles,
      'can_view_habit_titles': canViewHabitTitles,
    });
  }

  Future<void> removeSharingPermission({
    required String viewerUserId,
  }) async {
    final userId = _userId;

    await _supabase
        .from('shared_progress_permissions')
        .delete()
        .eq('owner_user_id', userId)
        .eq('viewer_user_id', viewerUserId);
  }

  Future<Map<String, dynamic>?> fetchPermissionForViewer({
    required String ownerUserId,
  }) async {
    final userId = _userId;

    final response = await _supabase
        .from('shared_progress_permissions')
        .select('''
          permission_id,
          owner_user_id,
          viewer_user_id,
          can_view_progress,
          can_view_goal_titles,
          can_view_habit_titles,
          created_at,
          updated_at
        ''')
        .eq('owner_user_id', ownerUserId)
        .eq('viewer_user_id', userId)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> fetchViewableProgressForUser({
    required String ownerUserId,
  }) async {
    final permission = await fetchPermissionForViewer(ownerUserId: ownerUserId);

    if (permission == null || permission['can_view_progress'] != true) {
      throw Exception('You do not have permission to view this user\'s progress.');
    }

    final profile = await _supabase
        .from('profiles')
        .select('id, username')
        .eq('id', ownerUserId)
        .maybeSingle();

    final goals = await _supabase
        .from('goals')
        .select('goal_id, title, active')
        .eq('user_id', ownerUserId)
        .eq('active', true);

    final doneLogs = await _supabase
        .from('habit_logs')
        .select('log_id')
        .eq('user_id', ownerUserId)
        .eq('status', 'done');

    List<Map<String, dynamic>> goalList = List<Map<String, dynamic>>.from(goals);

    if (permission['can_view_goal_titles'] != true) {
      goalList = goalList
          .map((goal) => {
                'goal_id': goal['goal_id'],
                'title': 'Hidden Goal',
                'active': goal['active'],
              })
          .toList();
    }

    return {
      'profile': profile,
      'goals': goalList,
      'done_count': List<Map<String, dynamic>>.from(doneLogs).length,
      'permission': permission,
    };
  }
}