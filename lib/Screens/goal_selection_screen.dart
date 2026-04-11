import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../Widgets/primary_button.dart';
import 'goal_input_screen.dart';
import 'providers.dart';

class GoalSelectionScreen extends ConsumerStatefulWidget {
  const GoalSelectionScreen({super.key});

  static const int maxGoals = 2;

  @override
  ConsumerState<GoalSelectionScreen> createState() =>
      _GoalSelectionScreenState();
}

class _GoalSelectionScreenState extends ConsumerState<GoalSelectionScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  List<Map<String, dynamic>> _goalTemplates = [];
  Map<String, List<Map<String, dynamic>>> _habitTemplatesByGoalCode = {};

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final goalTemplatesResponse = await supabase
          .from('goal_templates')
          .select(
            'goal_template_id, code, title, description, category, active',
          )
          .eq('active', true)
          .order('category', ascending: true)
          .order('title', ascending: true);

      final habitTemplatesResponse = await supabase
          .from('habit_templates')
          .select('''
            habit_template_id,
            goal_template_id,
            code,
            title,
            description,
            target_frequency,
            duration_minutes,
            verification_type,
            evidence_type,
            enforcement_level,
            min_valid_minutes,
            min_completion_ratio,
            max_interruptions,
            grace_seconds,
            strict_fail_on_exit,
            requires_verifier,
            base_points,
            penalty_points,
            tier_weight,
            active
          ''')
          .eq('active', true)
          .order('created_at', ascending: true);

      final goals =
          List<Map<String, dynamic>>.from(goalTemplatesResponse);
      final habits =
          List<Map<String, dynamic>>.from(habitTemplatesResponse);

      final Map<String, List<Map<String, dynamic>>> groupedHabits = {};
      for (final goal in goals) {
        final goalTemplateId = goal['goal_template_id'].toString();
        final goalCode = goal['code'].toString();

        final goalHabits = habits
            .where(
              (habit) =>
                  habit['goal_template_id']?.toString() == goalTemplateId,
            )
            .map((habit) => Map<String, dynamic>.from(habit))
            .toList();

        groupedHabits[goalCode] = goalHabits;
      }

      if (!mounted) return;

      setState(() {
        _goalTemplates = goals;
        _habitTemplatesByGoalCode = groupedHabits;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading goal templates: $e');

      if (!mounted) return;

      setState(() {
        _error = 'Failed to load goal templates.\n$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveGoalsAndNavigate(
    BuildContext context,
    Set<String> selectedGoalCodes,
  ) async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated.')),
      );
      return;
    }

    try {
      setState(() {
        _isSaving = true;
      });

      final selectedTemplates = _goalTemplates
          .where((goal) => selectedGoalCodes.contains(goal['code']))
          .toList();

      if (selectedTemplates.length != GoalSelectionScreen.maxGoals) {
        throw Exception(
          'Please select exactly ${GoalSelectionScreen.maxGoals} goals.',
        );
      }

      await supabase.from('goals').delete().eq('user_id', user.id);
      await supabase.from('fixed_time_blocks').delete().eq('user_id', user.id);

      final List<Map<String, dynamic>> goalsToInsert = selectedTemplates
          .map(
            (goalTemplate) => {
              'user_id': user.id,
              'goal_template_id': goalTemplate['goal_template_id'],
              'title': goalTemplate['title'],
              'category': goalTemplate['category'],
              'description': null,
              'why': null,
              'success_metric': null,
              'active': true,
            },
          )
          .toList();

      final insertedGoalsRaw = await supabase
          .from('goals')
          .insert(goalsToInsert)
          .select('goal_id, goal_template_id, title, category');

      final insertedGoalRows =
          List<Map<String, dynamic>>.from(insertedGoalsRaw);

      if (insertedGoalRows.isEmpty) {
        throw Exception('No goals were inserted.');
      }

      final List<Map<String, dynamic>> habitsToInsert = [];
      final Map<String, dynamic> goalHabitsForNextScreen = {};

      for (final insertedGoal in insertedGoalRows) {
        final goalId = insertedGoal['goal_id']?.toString();
        final goalTemplateId = insertedGoal['goal_template_id']?.toString();
        final goalTitle = insertedGoal['title']?.toString();

        if (goalId == null || goalId.isEmpty) {
          throw Exception('Inserted goal is missing goal_id.');
        }
        if (goalTemplateId == null || goalTemplateId.isEmpty) {
          throw Exception('Inserted goal is missing goal_template_id.');
        }
        if (goalTitle == null || goalTitle.isEmpty) {
          throw Exception('Inserted goal is missing title.');
        }

        final matchingTemplate = selectedTemplates.firstWhere(
          (template) =>
              template['goal_template_id']?.toString() == goalTemplateId,
          orElse: () => <String, dynamic>{},
        );

        final goalCode = matchingTemplate['code']?.toString();
        if (goalCode == null || goalCode.isEmpty) {
          throw Exception('Could not resolve selected goal code.');
        }

        final habitTemplates = _habitTemplatesByGoalCode[goalCode] ?? [];

        goalHabitsForNextScreen[goalTitle] = habitTemplates
            .map((habit) => Map<String, dynamic>.from(habit))
            .toList();

        for (final habitTemplate in habitTemplates) {
          habitsToInsert.add({
            'goal_id': goalId,
            'habit_template_id': habitTemplate['habit_template_id'],
            'title': habitTemplate['title'],
            'description': habitTemplate['description'],
            'target_frequency': habitTemplate['target_frequency'],
            'duration_minutes': habitTemplate['duration_minutes'],
            'verification_type': habitTemplate['verification_type'],
            'evidence_type': habitTemplate['evidence_type'],
            'enforcement_level': habitTemplate['enforcement_level'],
            'min_valid_minutes': habitTemplate['min_valid_minutes'],
            'min_completion_ratio': habitTemplate['min_completion_ratio'],
            'max_interruptions': habitTemplate['max_interruptions'],
            'grace_seconds': habitTemplate['grace_seconds'],
            'strict_fail_on_exit': habitTemplate['strict_fail_on_exit'],
            'requires_verifier': habitTemplate['requires_verifier'],
            'base_points': habitTemplate['base_points'],
            'penalty_points': habitTemplate['penalty_points'],
            'tier_weight': habitTemplate['tier_weight'],
            'verification_locked': true,
            'active': true,
          });
        }
      }

      if (habitsToInsert.isNotEmpty) {
        await supabase.from('habits').insert(habitsToInsert);
      }

      await supabase.from('profiles').update({
        'onboarding_step': 2,
      }).eq('id', user.id);

      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GoalInputScreen(
            userId: user.id,
            selectedGoalRecords: insertedGoalRows,
            goalHabits: goalHabitsForNextScreen,
          ),
        ),
      );
    } on PostgrestException catch (e) {
      debugPrint('Postgrest error saving selected goals: ${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Database error: ${e.message}')),
      );
    } catch (e, st) {
      debugPrint('Error saving selected goals: $e');
      debugPrintStack(stackTrace: st);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving goals: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupGoalsByCategory() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final goal in _goalTemplates) {
      final category = (goal['category'] ?? 'Other').toString();
      grouped.putIfAbsent(category, () => []);
      grouped[category]!.add(goal);
    }

    return grouped;
  }

  Widget _buildGoalCard({
    required Map<String, dynamic> goal,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final goalCode = (goal['code'] ?? '').toString();
    final habitCount = (_habitTemplatesByGoalCode[goalCode] ?? []).length;
    final description = (goal['description'] ?? '').toString();

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF5F5F5)
              : const Color(0xFF17171A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF5F5F5)
                : const Color(0xFF2A2A2F),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (goal['title'] ?? 'Untitled Goal').toString(),
              style: TextStyle(
                color: isSelected ? Colors.black : const Color(0xFFF5F5F5),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$habitCount habits',
              style: TextStyle(
                color: isSelected
                    ? Colors.black.withValues(alpha: 0.65)
                    : const Color(0xFF9A9AA3),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected
                      ? Colors.black.withValues(alpha: 0.75)
                      : const Color(0xFFB3B3BB),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedGoals = ref.watch(selectedGoalsProvider);
    final selectedNotifier = ref.read(selectedGoalsProvider.notifier);

    final canContinue =
        selectedGoals.length == GoalSelectionScreen.maxGoals;

    final groupedGoals = _groupGoalsByCategory();

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F0F),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F0F0F),
          elevation: 0,
          title: const Text(
            'Select Your Focus Areas',
            style: TextStyle(color: Color(0xFFF5F5F5)),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFB3B3BB)),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        title: const Text(
          'Select Your Focus Areas',
          style: TextStyle(color: Color(0xFFF5F5F5)),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Choose exactly 2 broad goals.\nYou will define them in detail next.',
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
              children: groupedGoals.entries.map((entry) {
                final category = entry.key;
                final goals = entry.value;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category,
                        style: const TextStyle(
                          color: Color(0xFFF5F5F5),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: goals.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.3,
                        ),
                        itemBuilder: (_, index) {
                          final goal = goals[index];
                          final code = (goal['code'] ?? '').toString();
                          final isSelected = selectedGoals.contains(code);

                          return _buildGoalCard(
                            goal: goal,
                            isSelected: isSelected,
                            onTap: () {
                              selectedNotifier.toggle(
                                code,
                                maxGoals: GoalSelectionScreen.maxGoals,
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: _isSaving
                ? const Center(child: CircularProgressIndicator())
                : PrimaryButton(
                    text: canContinue
                        ? 'Continue'
                        : 'Select ${GoalSelectionScreen.maxGoals - selectedGoals.length} more',
                    onPressed: canContinue
                        ? () => _saveGoalsAndNavigate(
                              context,
                              selectedGoals,
                            )
                        : null,
                  ),
          ),
        ],
      ),
    );
  }
}