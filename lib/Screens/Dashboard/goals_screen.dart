import 'package:achievr_app/Widgets/hold_to_refresh_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _error;

  List<Map<String, dynamic>> _goals = [];
  List<Map<String, dynamic>> _habits = [];

  @override
  void initState() {
    super.initState();
    _loadGoalsData();
  }

  Future<void> _loadGoalsData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (!mounted) return;
        setState(() {
          _error = 'No authenticated user found.';
          _isLoading = false;
        });
        return;
      }

      final goalsResponse = await supabase
          .from('goals')
          .select(
            'goal_id, title, description, category, why, success_metric, active, created_at',
          )
          .eq('user_id', user.id)
          .eq('active', true)
          .order('created_at', ascending: true);

      final fetchedGoals = List<Map<String, dynamic>>.from(goalsResponse);

      List<Map<String, dynamic>> fetchedHabits = [];

      if (fetchedGoals.isNotEmpty) {
        final goalIds =
            fetchedGoals.map((goal) => goal['goal_id'].toString()).toList();

        final habitsResponse = await supabase
            .from('habits')
            .select(
              'habit_id, goal_id, title, verification_type, enforcement_level, active, created_at',
            )
            .inFilter('goal_id', goalIds)
            .eq('active', true)
            .order('created_at', ascending: true);

        fetchedHabits = List<Map<String, dynamic>>.from(habitsResponse);
      }

      if (!mounted) return;

      setState(() {
        _goals = fetchedGoals;
        _habits = fetchedHabits;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('GOALS SCREEN ERROR: $e');
      debugPrint('$st');

      if (!mounted) return;

      setState(() {
        _error = 'Failed to load goals.\n$e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _habitsForGoal(String goalId) {
    return _habits
        .where((habit) => habit['goal_id'].toString() == goalId)
        .toList();
  }

  int get _unsupportedGoalsCount {
    return _goals.where((goal) {
      final goalId = goal['goal_id'].toString();
      return _habitsForGoal(goalId).isEmpty;
    }).length;
  }

  String _goalHealthLabel(List<Map<String, dynamic>> habits) {
    final count = habits.length;

    if (count == 0) return 'Unsupported';
    if (count == 1) return 'Light structure';
    if (count >= 2 && count <= 4) return 'Strong structure';
    return 'Overloaded';
  }

  String _goalHealthMessage(List<Map<String, dynamic>> habits) {
    final count = habits.length;

    if (count == 0) {
      return 'This goal has no enforcing habits yet, so execution risk is high.';
    }
    if (count == 1) {
      return 'This goal has minimal enforcement. Consider adding another habit to strengthen consistency.';
    }
    if (count >= 2 && count <= 4) {
      return 'This goal has a solid habit structure supporting steady execution.';
    }
    return 'This goal may be carrying too many habits. Simplifying could improve consistency.';
  }

  Color _goalHealthColor(String label) {
    switch (label) {
      case 'Unsupported':
        return const Color(0xFFFF8A80);
      case 'Light structure':
        return const Color(0xFFFFD166);
      case 'Strong structure':
        return const Color(0xFFB3E5FC);
      case 'Overloaded':
        return const Color(0xFFE57373);
      default:
        return const Color(0xFF7C7C84);
    }
  }

  String _habitCountLabel(int count) {
    return '$count habit${count == 1 ? '' : 's'}';
  }

  Widget _buildSectionTitle(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricChip({
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthChip(String label) {
    final color = _goalHealthColor(label);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildTopCard() {
    final totalHabits = _habits.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Goals',
            style: TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Your active outcomes, why they matter, and the habits enforcing them.',
            style: TextStyle(
              color: Color(0xFFB3B3BB),
              height: 1.45,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildMetricChip(
                  label: 'Active Goals',
                  value: '${_goals.length}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Active Habits',
                  value: '$totalHabits',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Unsupported',
                  value: '$_unsupportedGoalsCount',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHabitChip(Map<String, dynamic> habit) {
    final verificationType = (habit['verification_type'] ?? 'manual').toString();
    final enforcementLevel =
        (habit['enforcement_level'] ?? 'standard').toString();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 5),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF7C7C84),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  habit['title']?.toString() ?? 'Untitled Habit',
                  style: const TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Verification: $verificationType',
                      style: const TextStyle(
                        color: Color(0xFF9A9AA3),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Enforcement: $enforcementLevel',
                      style: const TextStyle(
                        color: Color(0xFF9A9AA3),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalCard(Map<String, dynamic> goal, int index) {
    final goalId = goal['goal_id'].toString();
    final habits = _habitsForGoal(goalId);
    final healthLabel = _goalHealthLabel(habits);
    final healthMessage = _goalHealthMessage(habits);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + (index * 90)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF17171A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _goalHealthColor(healthLabel)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    goal['title']?.toString() ?? 'Untitled Goal',
                    style: const TextStyle(
                      color: Color(0xFFF5F5F5),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _buildHealthChip(healthLabel),
              ],
            ),
            if ((goal['category'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                goal['category'].toString(),
                style: const TextStyle(
                  color: Color(0xFF9A9AA3),
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF101013),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF232329)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Execution health',
                    style: TextStyle(
                      color: Color(0xFFF5F5F5),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    healthMessage,
                    style: const TextStyle(
                      color: Color(0xFFB3B3BB),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _habitCountLabel(habits.length),
                    style: const TextStyle(
                      color: Color(0xFF9A9AA3),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if ((goal['description'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                goal['description'].toString(),
                style: const TextStyle(
                  color: Color(0xFFB3B3BB),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
            if ((goal['why'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF101013),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF232329)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Why this matters',
                      style: TextStyle(
                        color: Color(0xFFF5F5F5),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      goal['why'].toString(),
                      style: const TextStyle(
                        color: Color(0xFFB3B3BB),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if ((goal['success_metric'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF101013),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF232329)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Success metric',
                      style: TextStyle(
                        color: Color(0xFFF5F5F5),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      goal['success_metric'].toString(),
                      style: const TextStyle(
                        color: Color(0xFFB3B3BB),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            _buildSectionTitle(
              'Enforcing habits',
              subtitle: 'The recurring actions that move this goal forward.',
            ),
            if (habits.isEmpty)
              const Text(
                'No habits attached to this goal.',
                style: TextStyle(
                  color: Color(0xFF9A9AA3),
                  fontSize: 13,
                ),
              ),
            ...habits.map(_buildHabitChip),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFF5F5F5),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFB3B3BB),
            ),
          ),
        ),
      );
    }

    return HoldToRefreshWrapper(
      onRefresh: _loadGoalsData,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopCard(),
            const SizedBox(height: 18),
            if (_goals.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF17171A),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF232329)),
                ),
                child: const Text(
                  'No active goals found.',
                  style: TextStyle(
                    color: Color(0xFF9A9AA3),
                    fontSize: 14,
                  ),
                ),
              ),
            ...List.generate(
              _goals.length,
              (index) => _buildGoalCard(_goals[index], index),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0C),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }
}