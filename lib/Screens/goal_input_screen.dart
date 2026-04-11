import 'package:achievr_app/Screens/time_constraint_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../Widgets/primary_button.dart';

class GoalInputScreen extends StatefulWidget {
  final String userId;
  final List<Map<String, dynamic>> selectedGoalRecords;
  final Map<String, dynamic> goalHabits;

  const GoalInputScreen({
    super.key,
    required this.userId,
    required this.selectedGoalRecords,
    required this.goalHabits,
  });

  @override
  State<GoalInputScreen> createState() => _GoalInputScreenState();
}

class _GoalInputScreenState extends State<GoalInputScreen> {
  late List<TextEditingController> _descriptionControllers;
  late List<TextEditingController> _whyControllers;
  late List<TextEditingController> _metricsControllers;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _descriptionControllers = widget.selectedGoalRecords
        .map(
          (goal) => TextEditingController(
            text: (goal['description'] ?? '').toString(),
          ),
        )
        .toList();

    _whyControllers = widget.selectedGoalRecords
        .map(
          (goal) => TextEditingController(
            text: (goal['why'] ?? '').toString(),
          ),
        )
        .toList();

    _metricsControllers = widget.selectedGoalRecords
        .map(
          (goal) => TextEditingController(
            text: (goal['success_metric'] ?? goal['metrics'] ?? '').toString(),
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    for (final controller in [
      ..._descriptionControllers,
      ..._whyControllers,
      ..._metricsControllers,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get allFilled {
    for (int i = 0; i < widget.selectedGoalRecords.length; i++) {
      if (_descriptionControllers[i].text.trim().isEmpty ||
          _whyControllers[i].text.trim().isEmpty) {
        return false;
      }
    }
    return true;
  }

  List<Map<String, dynamic>> _normalizeHabits(dynamic rawHabits) {
    if (rawHabits is! List) return [];

    return rawHabits.map<Map<String, dynamic>>((habit) {
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
    }).toList();
  }

  String _habitMeta(Map<String, dynamic> habit) {
    final List<String> parts = [];

    final duration = habit['duration_minutes'];
    if (duration != null) {
      parts.add('${duration.toString()} min');
    }

    final verificationType =
        (habit['verification_type'] ?? '').toString().trim();
    if (verificationType.isNotEmpty) {
      parts.add(verificationType.replaceAll('_', ' '));
    }

    return parts.join(' • ');
  }

  Future<void> _saveGoalDetails() async {
    if (!allFilled) return;

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final List<Map<String, dynamic>> detailedGoals = [];

      for (int i = 0; i < widget.selectedGoalRecords.length; i++) {
        final goalRecord = widget.selectedGoalRecords[i];
        final String goalId = goalRecord['goal_id'].toString();
        final String goalTitle = goalRecord['title'].toString();
        final String goalCategory =
            (goalRecord['category'] ?? 'General').toString();

        final String goalDescription = _descriptionControllers[i].text.trim();
        final String goalWhy = _whyControllers[i].text.trim();
        final String goalMetric = _metricsControllers[i].text.trim();

        await supabase.from('goals').update({
          'description': goalDescription,
          'why': goalWhy,
          'success_metric': goalMetric.isEmpty ? null : goalMetric,
        }).eq('goal_id', goalId);

        final List<Map<String, dynamic>> habits = _normalizeHabits(
          widget.goalHabits[goalTitle] ?? [],
        );

        detailedGoals.add({
          'goal_id': goalId,
          'goal_template_id': goalRecord['goal_template_id'],
          'title': goalTitle,
          'category': goalCategory,
          'description': goalDescription,
          'why': goalWhy,
          'metrics': goalMetric,
          'habits': habits,
        });
      }

      await supabase.from('profiles').update({
        'onboarding_step': 3,
      }).eq('id', widget.userId);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TimeConstraintScreen(
            detailedGoals: detailedGoals,
            userId: widget.userId,
          ),
        ),
      );
    } on PostgrestException catch (e) {
      debugPrint('Postgrest error updating goal details: ${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Database error: ${e.message}')),
      );
    } catch (e) {
      debugPrint('Error updating goal details: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving goals: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    bool requiredField = false,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white12,
        hintText: hint,
        labelText: requiredField ? '$label *' : label,
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white54),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
      ),
    );
  }

  Widget _buildHabitPreviewCard(Map<String, dynamic> habit) {
    final title = (habit['title'] ?? 'Untitled habit').toString();
    final description = (habit['description'] ?? '').toString();
    final meta = _habitMeta(habit);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              meta,
              style: const TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 11,
              ),
            ),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(
                color: Color(0xFFB3B3BB),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGoalSection(int index) {
    final goal = widget.selectedGoalRecords[index];
    final String goalTitle = goal['title'].toString();
    final List<Map<String, dynamic>> habits = _normalizeHabits(
      widget.goalHabits[goalTitle] ?? [],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF232323)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            goalTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _descriptionControllers[index],
            label: 'Define the Outcome',
            hint: 'What exactly changes when this goal is achieved?',
            maxLines: 2,
            requiredField: true,
          ),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _whyControllers[index],
            label: 'Emotional Reason',
            hint: 'Why is this important to you?',
            maxLines: 2,
            requiredField: true,
          ),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _metricsControllers[index],
            label: 'Success Metric (Optional)',
            hint: r'E.g., 5 workouts/week, 20 pages/day, $500 saved/month',
          ),
          if (habits.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Included Habits',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            ...habits.map(_buildHabitPreviewCard),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        title: const Text('Clarify Your Goals'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: widget.selectedGoalRecords.length,
              itemBuilder: (_, index) => _buildGoalSection(index),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : PrimaryButton(
                    text: 'Continue',
                    onPressed: allFilled ? _saveGoalDetails : null,
                  ),
          ),
        ],
      ),
    );
  }
}