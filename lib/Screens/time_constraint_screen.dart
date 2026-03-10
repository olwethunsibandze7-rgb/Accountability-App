import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../Widgets/primary_button.dart';
import 'confirmation_screen.dart';

class TimeConstraintScreen extends StatefulWidget {
  final List<Map<String, dynamic>> detailedGoals;
  final String userId;

  const TimeConstraintScreen({
    super.key,
    required this.detailedGoals,
    required this.userId,
  });

  @override
  State<TimeConstraintScreen> createState() => _TimeConstraintScreenState();
}

class _TimeConstraintScreenState extends State<TimeConstraintScreen> {
  static const List<String> days = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
  ];

  static const Map<String, int> dayToDbIndex = {
    "Monday": 1,
    "Tuesday": 2,
    "Wednesday": 3,
    "Thursday": 4,
    "Friday": 5,
    "Saturday": 6,
  };

  final List<int> hours = List.generate(18, (i) => 6 + i); // 6 to 23
  final double cellHeight = 32.0;

  late Map<String, Set<int>> blockedHours;
  bool loading = true;
  bool saving = false;

  final SupabaseClient supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    blockedHours = {
      for (final day in days) day: <int>{},
    };
    _loadBlockedHours();
  }

  Future<void> _loadBlockedHours() async {
    try {
      final response = await supabase
          .from('fixed_time_blocks')
          .select('day_of_week, start_time, end_time')
          .eq('user_id', widget.userId);

      final Map<String, Set<int>> loaded = {
        for (final day in days) day: <int>{},
      };

      for (final row in response) {
        final int? dayOfWeek = row['day_of_week'] as int?;
        final String? startTime = row['start_time'] as String?;
        final String? endTime = row['end_time'] as String?;

        if (dayOfWeek == null || startTime == null || endTime == null) {
          continue;
        }

        final String dayName = dayToDbIndex.entries
            .firstWhere(
              (entry) => entry.value == dayOfWeek,
              orElse: () => const MapEntry('', 0),
            )
            .key;

        if (dayName.isEmpty) continue;

        final int startHour = int.parse(startTime.split(':')[0]);
        final int endHour = int.parse(endTime.split(':')[0]);

        for (int hour = startHour; hour < endHour; hour++) {
          if (loaded.containsKey(dayName)) {
            loaded[dayName]!.add(hour);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        blockedHours = loaded;
        loading = false;
      });
    } catch (e) {
      debugPrint("Error loading blocked hours: $e");
      if (!mounted) return;
      setState(() {
        loading = false;
      });
    }
  }

  void _toggleBlock(String day, int hour) {
    setState(() {
      if (blockedHours[day]!.contains(hour)) {
        blockedHours[day]!.remove(hour);
      } else {
        blockedHours[day]!.add(hour);
      }
    });
  }

  List<Map<String, dynamic>> _buildBlocksForDb() {
    final List<Map<String, dynamic>> inserts = [];

    blockedHours.forEach((day, hoursSet) {
      final int? dayIndex = dayToDbIndex[day];
      if (dayIndex == null) return;

      final List<int> sortedHours = hoursSet.toList()..sort();

      int? blockStart;
      int? previousHour;

      for (final hour in sortedHours) {
        if (blockStart == null) {
          blockStart = hour;
          previousHour = hour;
        } else if (hour == previousHour! + 1) {
          previousHour = hour;
        } else {
          inserts.add({
            'user_id': widget.userId,
            'day_of_week': dayIndex,
            'start_time': '${blockStart.toString().padLeft(2, '0')}:00:00',
            'end_time': '${(previousHour + 1).toString().padLeft(2, '0')}:00:00',
            'label': 'Blocked',
          });

          blockStart = hour;
          previousHour = hour;
        }
      }

      if (blockStart != null && previousHour != null) {
        inserts.add({
          'user_id': widget.userId,
          'day_of_week': dayIndex,
          'start_time': '${blockStart.toString().padLeft(2, '0')}:00:00',
          'end_time': '${(previousHour + 1).toString().padLeft(2, '0')}:00:00',
          'label': 'Blocked',
        });
      }
    });

    return inserts;
  }

  Future<void> _saveAndContinue() async {
    setState(() => saving = true);

    try {
      final List<Map<String, dynamic>> dbBlocks = _buildBlocksForDb();

      await supabase
          .from('fixed_time_blocks')
          .delete()
          .eq('user_id', widget.userId);

      if (dbBlocks.isNotEmpty) {
        await supabase.from('fixed_time_blocks').insert(dbBlocks);
      }

      await supabase.from('profiles').update({
        'onboarding_step': 4,
      }).eq('id', widget.userId);

      final List<Map<String, dynamic>> goalsWithHabits = widget.detailedGoals
          .map((goal) {
            final List<dynamic> rawHabits = goal['habits'] as List<dynamic>? ?? [];

            return {
              'goal_id': goal['goal_id'],
              'title': goal['title'],
              'category': goal['category'],
              'description': goal['description'],
              'why': goal['why'],
              'metrics': goal['metrics'],
              'habits': rawHabits
                  .map((habitTitle) => {
                        'title': habitTitle.toString(),
                        'duration': 1,
                      })
                  .toList(),
            };
          })
          .toList();

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConfirmationScreen(
            schedule: const {},
            userId: widget.userId,
            goalsWithHabits: goalsWithHabits,
            blockedHours: blockedHours,
          ),
        ),
      );
    } catch (e) {
      debugPrint("Error saving blocked hours: $e");

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save blocked hours: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  String _formatHourLabel(int hour) {
    final int displayHour =
        hour == 0 ? 12 : hour > 12 ? hour - 12 : hour;
    final String suffix = hour >= 12 ? 'PM' : 'AM';
    return '$displayHour$suffix';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F0F),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text("Blocked Time"),
        backgroundColor: const Color(0xFF0F0F0F),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Select times when you are unavailable.\nYour habits will be scheduled around these blocks.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: days.map((day) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        children: [
                          Text(
                            day.substring(0, 3),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.6,
                            child: SingleChildScrollView(
                              child: Column(
                                children: hours.map((hour) {
                                  final bool isBlocked =
                                      blockedHours[day]!.contains(hour);

                                  return GestureDetector(
                                    onTap: () => _toggleBlock(day, hour),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(vertical: 2),
                                      width: 68,
                                      height: cellHeight,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: isBlocked
                                            ? Colors.black
                                            : const Color(0xFF1C1C1C),
                                        border: Border.all(
                                          color: Colors.white24,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        _formatHourLabel(hour),
                                        style: TextStyle(
                                          color: isBlocked
                                              ? Colors.white
                                              : Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: saving
                  ? const Center(child: CircularProgressIndicator())
                  : PrimaryButton(
                      text: "Continue",
                      onPressed: _saveAndContinue,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}