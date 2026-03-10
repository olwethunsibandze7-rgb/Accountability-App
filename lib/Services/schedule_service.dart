// lib/Services/schedule_service.dart
import 'package:flutter/foundation.dart'; // for debugPrint
import 'package:supabase_flutter/supabase_flutter.dart';

class ScheduleService {
  final SupabaseClient supabase = Supabase.instance.client;

  ScheduleService();

  /// Fetch all fixed time blocks for a user
  Future<List<Map<String, dynamic>>> getFixedTimeBlocks(String userId) async {
    try {
      final data = await supabase
          .from('fixed_time_blocks')
          .select()
          .eq('user_id', userId);

      return (data as List<dynamic>).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      debugPrint("Error fetching fixed time blocks: $e");
      return [];
    }
  }

  /// Save fixed time blocks for a user
  Future<void> saveFixedTimeBlocks(
      String userId, List<Map<String, dynamic>> blocks) async {
    try {
      await supabase.from('fixed_time_blocks').delete().eq('user_id', userId);

      if (blocks.isNotEmpty) {
        await supabase.from('fixed_time_blocks').insert(blocks);
      }
    } catch (e) {
      debugPrint("Error saving fixed time blocks: $e");
      rethrow;
    }
  }

  /// Fetch all habits for a user with goal info
  Future<List<Map<String, dynamic>>> getUserHabits(String userId) async {
    try {
      final data = await supabase
          .from('habits')
          .select('habit_id, title, verification_type, enforcement_level, goal_id, goals(title, description)')
          .eq('goals.user_id', userId)
          .order('created_at', ascending: true);

      return (data as List<dynamic>).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      debugPrint("Error fetching habits: $e");
      return [];
    }
  }

  /// Insert habit schedules
  Future<void> saveHabitSchedules(List<Map<String, dynamic>> schedules) async {
    try {
      if (schedules.isEmpty) return;
      await supabase.from('habit_schedules').insert(schedules);
    } catch (e) {
      debugPrint("Error saving habit schedules: $e");
      rethrow;
    }
  }

  /// Clear all habit schedules for a user
  Future<void> clearHabitSchedules(String userId) async {
    try {
      // Get habit IDs for the user
      final habits = await supabase
          .from('habits')
          .select('habit_id')
          .filter('goals.user_id', 'eq', userId); // updated in_ -> filter

      final habitIds =
          (habits as List<dynamic>).map((e) => e['habit_id'] as String).toList();

      if (habitIds.isEmpty) return;

      await supabase
          .from('habit_schedules')
          .delete()
          .filter('habit_id', 'in', habitIds); // updated in_ -> filter
    } catch (e) {
      debugPrint("Error clearing habit schedules: $e");
      rethrow;
    }
  }
}