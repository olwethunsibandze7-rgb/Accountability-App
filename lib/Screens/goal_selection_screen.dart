import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../Widgets/primary_button.dart';
import 'goal_input_screen.dart';
import 'providers.dart';

class GoalSelectionScreen extends ConsumerWidget {
  const GoalSelectionScreen({super.key});

  static const int maxGoals = 2;

  static const Map<String, List<String>> goalCategories = {
    "Health & Fitness": [
      "Build Strength",
      "Lose Weight",
      "Improve Endurance",
      "Sleep Discipline",
      "Daily Movement",
    ],
    "Career & Productivity": [
      "Deep Work Routine",
      "Launch a Project",
      "Skill Development",
      "Networking Consistency",
      "Daily Output Target",
    ],
    "Mental & Emotional": [
      "Meditation Practice",
      "Reduce Screen Time",
      "Journaling Habit",
      "Emotional Regulation",
      "Stress Management",
    ],
    "Financial": [
      "Increase Income",
      "Savings Discipline",
      "Budget Tracking",
      "Debt Reduction",
      "Investment Learning",
    ],
    "Personal Growth": [
      "Reading Habit",
      "Public Speaking",
      "Creative Practice",
      "Social Confidence",
      "Language Learning",
    ],
  };

  static const Map<String, List<String>> goalHabits = {
    "Launch a Project": [
      "Break project into tasks",
      "Daily review progress",
      "Complete one priority action",
    ],
    "Build Strength": [
      "Push-ups",
      "Bodyweight exercises",
      "Track reps/sets",
    ],
    "Lose Weight": [
      "Track calories",
      "Daily walk",
      "Drink 8 glasses of water",
    ],
    "Meditation Practice": [
      "Morning meditation",
      "Evening reflection",
      "Focus on breath",
    ],
    "Reading Habit": [
      "Read 20 pages",
      "Summarize key points",
      "Note one insight",
    ],
    "Improve Endurance": [
      "20 min cardio",
      "Increase intensity slightly",
      "Stretch after",
    ],
    "Sleep Discipline": [
      "Consistent bedtime",
      "No screens 1hr before",
      "Wake up same time",
    ],
    "Daily Movement": [
      "Walk 5000 steps",
      "Take stairs",
      "Stretch break",
    ],
    "Deep Work Routine": [
      "Block 2hr focus time",
      "Remove distractions",
      "Set top priority",
    ],
    "Skill Development": [
      "Practice 30 minutes",
      "Study one lesson",
      "Apply new knowledge",
    ],
    "Networking Consistency": [
      "Send one message",
      "Engage on LinkedIn",
      "Schedule coffee chat",
    ],
    "Daily Output Target": [
      "Define 3 key tasks",
      "Complete by noon",
      "Review end of day",
    ],
    "Reduce Screen Time": [
      "No phone first hour",
      "Set app limits",
      "Read instead of scroll",
    ],
    "Journaling Habit": [
      "Write 3 gratitudes",
      "Reflect on emotions",
      "Set intention",
    ],
    "Emotional Regulation": [
      "Pause before reacting",
      "Name your emotion",
      "Practice deep breath",
    ],
    "Stress Management": [
      "5 min mindfulness",
      "Identify stress trigger",
      "Take a break",
    ],
    "Increase Income": [
      "Research side hustle",
      "Apply for one gig",
      "Update skills",
    ],
    "Savings Discipline": [
      "Transfer to savings",
      "Automate 10%",
      "Review expenses",
    ],
    "Budget Tracking": [
      "Log all expenses",
      "Categorize spending",
      "Check budget limits",
    ],
    "Debt Reduction": [
      "Pay extra on debt",
      "List all debts",
      "Avoid new debt",
    ],
    "Investment Learning": [
      "Read one article",
      "Watch one tutorial",
      "Review portfolio",
    ],
    "Public Speaking": [
      "Practice out loud",
      "Record yourself",
      "Speak in meeting",
    ],
    "Creative Practice": [
      "Sketch or write",
      "Try new idea",
      "Create for 15 min",
    ],
    "Social Confidence": [
      "Start conversation",
      "Make eye contact",
      "Compliment someone",
    ],
    "Language Learning": [
      "Learn 5 words",
      "Practice 10 minutes",
      "Listen to native speech",
    ],
  };

  String? _findCategoryForGoal(String goalTitle) {
    for (final entry in goalCategories.entries) {
      if (entry.value.contains(goalTitle)) {
        return entry.key;
      }
    }
    return null;
  }

  Future<void> _saveGoalsAndNavigate(
  BuildContext context,
  Set<String> selectedGoals,
) async {
  final user = Supabase.instance.client.auth.currentUser;

  if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("User not authenticated.")),
    );
    return;
  }

      try {
      final supabase = Supabase.instance.client;

      debugPrint('STEP 0A: clearing existing onboarding goals');
      await supabase
          .from('goals')
          .delete()
          .eq('user_id', user.id);

      debugPrint('STEP 0B: clearing existing fixed time blocks');
      await supabase
          .from('fixed_time_blocks')
          .delete()
          .eq('user_id', user.id);

      debugPrint('STEP 1: preparing goals to insert');

      final List<Map<String, dynamic>> goalsToInsert = selectedGoals.map((goal) {
        return {
          'user_id': user.id,
          'title': goal,
          'category': _findCategoryForGoal(goal),
          'description': null,
          'why': null,
          'success_metric': null,
          'active': true,
        };
      }).toList();

    debugPrint('STEP 2: inserting goals');
    final dynamic insertedGoalsRaw = await supabase
        .from('goals')
        .insert(goalsToInsert)
        .select('goal_id, title, category');

    debugPrint('STEP 3: raw inserted goals = $insertedGoalsRaw');

    final List<Map<String, dynamic>> insertedGoalRows = [];

    if (insertedGoalsRaw is List) {
      for (final row in insertedGoalsRaw) {
        if (row is Map) {
          insertedGoalRows.add(Map<String, dynamic>.from(row));
        }
      }
    }

    debugPrint('STEP 4: parsed insertedGoalRows = $insertedGoalRows');

    if (insertedGoalRows.isEmpty) {
      throw Exception('Goals saved, but no inserted goal rows were returned.');
    }

    final List<Map<String, dynamic>> habitsToInsert = [];

    for (final goalRow in insertedGoalRows) {
      final goalId = goalRow['goal_id']?.toString();
      final goalTitle = goalRow['title']?.toString();

      debugPrint('STEP 5: processing goalRow = $goalRow');

      if (goalId == null || goalId.isEmpty) {
        throw Exception('goal_id missing from inserted goal row.');
      }

      if (goalTitle == null || goalTitle.isEmpty) {
        throw Exception('title missing from inserted goal row.');
      }

      final List<String> habits = goalHabits[goalTitle] ?? [];

      debugPrint('STEP 6: habits for $goalTitle = $habits');

      for (final habitTitle in habits.take(3)) {
        habitsToInsert.add({
          'goal_id': goalId,
          'title': habitTitle,
          'verification_type': 'manual',
          'enforcement_level': 1,
          'active': true,
        });
      }
    }

    debugPrint('STEP 7: habitsToInsert = $habitsToInsert');

    if (habitsToInsert.isNotEmpty) {
      await supabase.from('habits').insert(habitsToInsert);
      debugPrint('STEP 8: habits inserted successfully');
    }

    await supabase.from('profiles').update({
      'onboarding_step': 2,
    }).eq('id', user.id);

    debugPrint('STEP 9: profile updated successfully');

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GoalInputScreen(
          userId: user.id,
          selectedGoalRecords: insertedGoalRows,
          goalHabits: goalHabits,
        ),
      ),
    );
  } on PostgrestException catch (e) {
    debugPrint('POSTGREST ERROR: ${e.message}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Database error: ${e.message}')),
    );
  } catch (e, st) {
    debugPrint('GENERAL ERROR: $e');
    debugPrintStack(stackTrace: st);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error saving goals: $e')),
    );
  }
}

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedGoals = ref.watch(selectedGoalsProvider);
    final selectedNotifier = ref.read(selectedGoalsProvider.notifier);

    final bool canContinue = selectedGoals.length == maxGoals;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        title: const Text(
          "Select Your Focus Areas",
          style: TextStyle(color: Color(0xFFF5F5F5)),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              "Choose exactly 2 broad goals.\nYou will define them in detail next.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFAAAAAA),
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: goalCategories.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: const TextStyle(
                          color: Color(0xFFF5F5F5),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: entry.value.map((goal) {
                          final bool isSelected = selectedGoals.contains(goal);

                          return GestureDetector(
                            onTap: () => selectedNotifier.toggle(
                              goal,
                              maxGoals: maxGoals,
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFF5F5F5)
                                    : const Color(0xFF1C1C1C),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFF5F5F5)
                                      : const Color(0xFF2A2A2A),
                                ),
                              ),
                              child: Text(
                                goal,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.black
                                      : const Color(0xFFF5F5F5),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: PrimaryButton(
              text: canContinue
                  ? "Continue"
                  : "Select ${maxGoals - selectedGoals.length} more",
              onPressed: canContinue
                  ? () => _saveGoalsAndNavigate(context, selectedGoals)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}