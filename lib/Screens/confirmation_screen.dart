import 'package:achievr_app/Screens/time_constraint_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dashboard/dashboard_screen.dart';

class ConfirmationScreen extends StatefulWidget {
  final Map<String, List<Map<String, dynamic>>> schedule;
  final String userId;
  final List<Map<String, dynamic>> goalsWithHabits;
  final Map<String, Set<int>> blockedHours;

  const ConfirmationScreen({
    super.key,
    required this.schedule,
    required this.userId,
    required this.goalsWithHabits,
    required this.blockedHours,
  });

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen> {
  static const List<String> weekOrder = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  static const Map<String, int> dayToDbIndex = {
    'Monday': 1,
    'Tuesday': 2,
    'Wednesday': 3,
    'Thursday': 4,
    'Friday': 5,
    'Saturday': 6,
  };

  static const List<int> schedulableHours = [
    6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22
  ];

  final SupabaseClient supabase = Supabase.instance.client;

  late Map<String, List<Map<String, dynamic>>> displayedSchedule;
  late Map<String, int> freeHoursByDay;

  bool _isSaving = false;
  int _regenerationSeed = 0;
  int _unscheduledRequiredSessions = 0;

  @override
  void initState() {
    super.initState();
    _distributeHabits();
  }

  void _goToTimeConstraints() {
    final List<Map<String, dynamic>> detailedGoals = widget.goalsWithHabits
        .map((goal) {
          final List<dynamic> rawHabits = goal['habits'] as List<dynamic>? ?? [];

          return {
            'goal_id': goal['goal_id'],
            'goal_template_id': goal['goal_template_id'],
            'title': goal['title'],
            'category': goal['category'],
            'description': goal['description'] ?? '',
            'why': goal['why'] ?? '',
            'metrics': goal['metrics'] ?? '',
            'habits': rawHabits.map<Map<String, dynamic>>((habit) {
              if (habit is Map<String, dynamic>) {
                return {
                  'habit_id': habit['habit_id'],
                  'habit_template_id': habit['habit_template_id'],
                  'title': habit['title'],
                  'description': habit['description'],
                  'target_frequency': habit['target_frequency'],
                  'duration_minutes': habit['duration_minutes'],
                  'verification_type': habit['verification_type'],
                  'verification_locked': habit['verification_locked'] ?? true,
                  'requires_verifier': habit['requires_verifier'] ?? false,
                  'evidence_type': habit['evidence_type'],
                  'enforcement_level': habit['enforcement_level'],
                  'min_valid_minutes': habit['min_valid_minutes'],
                  'min_completion_ratio': habit['min_completion_ratio'],
                  'max_interruptions': habit['max_interruptions'],
                  'grace_seconds': habit['grace_seconds'],
                  'strict_fail_on_exit': habit['strict_fail_on_exit'] ?? false,
                  'base_points': habit['base_points'],
                  'penalty_points': habit['penalty_points'],
                  'tier_weight': habit['tier_weight'],
                };
              }

              return {
                'title': habit.toString(),
                'verification_type': 'manual',
                'evidence_type': 'none',
              };
            }).toList(),
          };
        })
        .toList();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TimeConstraintScreen(
          detailedGoals: detailedGoals,
          userId: widget.userId,
        ),
      ),
    );
  }

  Set<int> _buildUnavailableHours(String day) {
    final Set<int> blocked = {...(widget.blockedHours[day] ?? <int>{})};
    final Set<int> unavailable = {...blocked};

    final List<int> sortedBlocked = blocked.toList()..sort();

    for (int i = 0; i < sortedBlocked.length; i++) {
      final int currentHour = sortedBlocked[i];

      if (i > 0) {
        final int previousHour = sortedBlocked[i - 1];
        if (currentHour == previousHour + 1) {
          unavailable.add(previousHour);
          unavailable.add(currentHour);
        }
      }
    }

    return unavailable;
  }

  int _calculateFreeHoursForDay(String day) {
    final Set<int> unavailable = _buildUnavailableHours(day);
    return schedulableHours.where((hour) => !unavailable.contains(hour)).length;
  }

  List<int> _buildPreferredHours(int goalCount) {
    if (goalCount <= 1) return [9];
    if (goalCount == 2) return [9, 17];
    if (goalCount == 3) return [8, 13, 18];
    return [8, 12, 16, 20];
  }

  int? _findBestStartHour(String day, int preferredHour, int duration) {
    final List<int> candidates = [];

    for (int startHour in schedulableHours) {
      if (_isSlotValid(day, startHour, duration)) {
        candidates.add(startHour);
      }
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final int distanceA = (a - preferredHour).abs();
      final int distanceB = (b - preferredHour).abs();

      if (distanceA != distanceB) {
        return distanceA.compareTo(distanceB);
      }

      return a.compareTo(b);
    });

    return candidates.first;
  }

  bool _isSlotValid(String day, int startHour, int duration) {
    final int endHour = startHour + duration;

    if (!schedulableHours.contains(startHour)) return false;
    if (endHour > 23) return false;

    final Set<int> unavailable = _buildUnavailableHours(day);

    for (int hour = startHour; hour < endHour; hour++) {
      if (unavailable.contains(hour)) return false;
    }

    final List<Map<String, dynamic>> tasks = displayedSchedule[day] ?? [];

    for (final task in tasks) {
      final int existingStart = task['start'] as int;
      final int existingEnd = task['end'] as int;

      final bool overlaps = startHour < existingEnd && endHour > existingStart;
      if (overlaps) return false;

      final bool violatesRecoveryGap =
          (startHour >= existingEnd && startHour < existingEnd + 1) ||
              (endHour <= existingStart && endHour > existingStart - 1);

      if (violatesRecoveryGap) return false;
    }

    return true;
  }

  int _habitDurationHours(Map<String, dynamic> habit) {
    final dynamic rawMinutes = habit['duration_minutes'] ?? habit['duration'];
    final int minutes = rawMinutes is int
        ? rawMinutes
        : int.tryParse(rawMinutes?.toString() ?? '') ?? 60;

    final int hours = (minutes / 60).ceil();
    return hours.clamp(1, 4);
  }

  void _distributeHabits() {
    displayedSchedule = {
      for (final day in weekOrder) day: <Map<String, dynamic>>[],
    };

    freeHoursByDay = {
      for (final day in weekOrder) day: _calculateFreeHoursForDay(day),
    };

    _unscheduledRequiredSessions = 0;

    final List<Map<String, dynamic>> validGoals = widget.goalsWithHabits
        .where((goal) {
          final habits = goal['habits'] as List<dynamic>? ?? [];
          return habits.isNotEmpty;
        })
        .map((goal) => Map<String, dynamic>.from(goal))
        .toList();

    if (validGoals.isEmpty) return;

    final Map<String, int> habitRotationIndex = {
      for (final goal in validGoals) goal['goal_id'].toString(): 0,
    };

    final List<int> preferredHours =
        _buildPreferredHours(validGoals.length);

    final int dayOffset = _regenerationSeed % weekOrder.length;

    for (int dayLoopIndex = 0; dayLoopIndex < weekOrder.length; dayLoopIndex++) {
      final String day = weekOrder[(dayLoopIndex + dayOffset) % weekOrder.length];

      for (int goalIndex = 0; goalIndex < validGoals.length; goalIndex++) {
        final goal = validGoals[goalIndex];
        final String goalId = goal['goal_id'].toString();
        final String goalTitle = goal['title'].toString();

        final List<Map<String, dynamic>> habits =
            (goal['habits'] as List<dynamic>)
                .map((habit) => Map<String, dynamic>.from(habit as Map))
                .toList();

        if (habits.isEmpty) {
          _unscheduledRequiredSessions++;
          continue;
        }

        final int rotation = habitRotationIndex[goalId] ?? 0;
        final Map<String, dynamic> chosenHabit =
            habits[rotation % habits.length];

        final String habitTitle = chosenHabit['title'].toString();
        final int duration = _habitDurationHours(chosenHabit);

        final int preferredHour =
            preferredHours[goalIndex.clamp(0, preferredHours.length - 1)];

        final int? startHour =
            _findBestStartHour(day, preferredHour, duration);

        if (startHour == null) {
          _unscheduledRequiredSessions++;
          continue;
        }

        displayedSchedule[day]!.add({
          'goal_id': goalId,
          'goal_title': goalTitle,
          'habit_id': chosenHabit['habit_id'],
          'habit_title': habitTitle,
          'start': startHour,
          'end': startHour + duration,
          'duration_hours': duration,
          'verification_type': chosenHabit['verification_type'],
        });

        habitRotationIndex[goalId] = rotation + 1;
      }
    }

    for (final day in weekOrder) {
      displayedSchedule[day]!.sort(
        (a, b) => (a['start'] as int).compareTo(b['start'] as int),
      );
    }
  }

  String _formatTime(int hour) {
    final String suffix = hour >= 12 ? 'PM' : 'AM';
    final int displayHour =
        hour == 0 ? 12 : hour > 12 ? hour - 12 : hour;
    return '$displayHour $suffix';
  }

  int _calculateTotalTasks() {
    int total = 0;
    for (final tasks in displayedSchedule.values) {
      total += tasks.length;
    }
    return total;
  }

  int _calculateTotalFreeHours() {
    int total = 0;
    for (final value in freeHoursByDay.values) {
      total += value;
    }
    return total;
  }

  Future<void> _acceptSchedule() async {
    setState(() => _isSaving = true);

    try {
      final List<String> goalIds = widget.goalsWithHabits
          .map((goal) => (goal['goal_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();

      if (goalIds.isEmpty) {
        throw Exception('No goal IDs available for schedule saving.');
      }

      final habitsResponse = await supabase
          .from('habits')
          .select('habit_id, goal_id, title')
          .inFilter('goal_id', goalIds);

      final List<Map<String, dynamic>> habitRows =
          List<Map<String, dynamic>>.from(habitsResponse);

      final Map<String, String> habitKeyToId = {
        for (final row in habitRows)
          '${row['goal_id']}::${row['title']}': row['habit_id'] as String,
      };

      final List<String> habitIds =
          habitRows.map((row) => row['habit_id'] as String).toList();

      if (habitIds.isNotEmpty) {
        await supabase
            .from('habit_schedules')
            .delete()
            .inFilter('habit_id', habitIds);
      }

      final List<Map<String, dynamic>> scheduleInserts = [];

      for (final day in weekOrder) {
        final int? dayIndex = dayToDbIndex[day];
        if (dayIndex == null) continue;

        for (final task in displayedSchedule[day]!) {
          final String goalId = task['goal_id'] as String;
          final String habitTitle = task['habit_title'] as String;
          final int start = task['start'] as int;
          final int end = task['end'] as int;

          final String? habitId =
              (task['habit_id']?.toString().isNotEmpty ?? false)
                  ? task['habit_id'].toString()
                  : habitKeyToId['$goalId::$habitTitle'];

          if (habitId == null) continue;

          scheduleInserts.add({
            'habit_id': habitId,
            'day_of_week': dayIndex,
            'start_time': '${start.toString().padLeft(2, '0')}:00:00',
            'end_time': '${end.toString().padLeft(2, '0')}:00:00',
            'source': 'onboarding',
          });
        }
      }

      if (scheduleInserts.isNotEmpty) {
        await supabase.from('habit_schedules').insert(scheduleInserts);
      }

      await supabase.from('profiles').update({
        'setup_completed': true,
        'onboarding_step': 5,
      }).eq('id', widget.userId);

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
        (_) => false,
      );
    } catch (e) {
      debugPrint('Error saving schedule: $e');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save schedule: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _regenerateSchedule() {
    setState(() {
      _regenerationSeed++;
      _distributeHabits();
    });
  }

  String _taskSubtitle(Map<String, dynamic> task) {
    final verification = (task['verification_type'] ?? '').toString();
    if (verification.isEmpty) {
      return '${_formatTime(task['start'] as int)} - ${_formatTime(task['end'] as int)}';
    }

    return '${_formatTime(task['start'] as int)} - ${_formatTime(task['end'] as int)}'
        '  •  ${verification.replaceAll('_', ' ')}';
  }

  @override
  Widget build(BuildContext context) {
    final int totalTasks = _calculateTotalTasks();
    final int totalFreeHours = _calculateTotalFreeHours();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text('Schedule Review'),
        backgroundColor: const Color(0xFF0F0F0F),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goToTimeConstraints,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF171717),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF262626)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Schedule Summary',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• $totalTasks total habit sessions scheduled\n'
                    '• $totalFreeHours usable hours remain after blocked time and recovery buffers\n'
                    '• Minimum daily rule enforced: at least 1 habit from each goal per day\n'
                    '• 1-hour recovery gap enforced between habits',
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.4,
                    ),
                  ),
                  if (_unscheduledRequiredSessions > 0) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Warning: $_unscheduledRequiredSessions required sessions could not be placed because availability is too tight.',
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                children: weekOrder.map((day) {
                  final tasks = displayedSchedule[day] ?? [];
                  final freeHours = freeHoursByDay[day] ?? 0;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$day  •  $freeHours free hrs',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (tasks.isEmpty)
                          const Text(
                            'No sessions scheduled',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ...tasks.map((task) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF17171A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF262626)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task['habit_title'].toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  task['goal_title'].toString(),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _taskSubtitle(task),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : _regenerateSchedule,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF3A3A42)),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text('Regenerate'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _acceptSchedule,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Accept Schedule',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}