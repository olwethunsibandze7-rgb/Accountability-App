import 'package:achievr_app/Screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  Map<String, dynamic>? profile;

  List<Map<String, dynamic>> goals = [];
  List<Map<String, dynamic>> habits = [];
  List<Map<String, dynamic>> todaysTasks = [];
  List<Map<String, dynamic>> todayLogs = [];
  List<Map<String, dynamic>> verificationQueue = [];

  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  int get _todayDayOfWeek {
    final weekday = DateTime.now().weekday; // Mon=1 ... Sun=7
    return weekday > 6 ? 6 : weekday;
  }

  String get _todayLabel {
    const dayNames = [
      '',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return dayNames[DateTime.now().weekday];
  }

  String _formatDate(DateTime dt) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month]} ${dt.day}';
  }

  String _formatTimeString(String hhmmss) {
    final parts = hhmmss.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;

    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : hour > 12 ? hour - 12 : hour;

    return '$displayHour $suffix';
  }

  Future<void> _loadDashboardData() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _error = 'No authenticated user found.';
        _isLoading = false;
      });
      return;
    }

    try {
      final profileResponse = await supabase
          .from('profiles')
          .select(
            'id, username, plan_tier, strict_mode_enabled, setup_completed',
          )
          .eq('id', user.id)
          .maybeSingle();

      final goalsResponse = await supabase
          .from('goals')
          .select(
            'goal_id, title, description, category, why, success_metric, active, created_at',
          )
          .eq('user_id', user.id)
          .eq('active', true)
          .order('created_at', ascending: true);

      final List<Map<String, dynamic>> fetchedGoals =
          List<Map<String, dynamic>>.from(goalsResponse);

      List<Map<String, dynamic>> fetchedHabits = [];
      List<Map<String, dynamic>> fetchedSchedules = [];
      List<Map<String, dynamic>> fetchedLogs = [];

      if (fetchedGoals.isNotEmpty) {
        final List<String> goalIds =
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

        if (fetchedHabits.isNotEmpty) {
          final List<String> habitIds =
              fetchedHabits.map((habit) => habit['habit_id'].toString()).toList();

          final schedulesResponse = await supabase
              .from('habit_schedules')
              .select(
                'schedule_id, habit_id, day_of_week, start_time, end_time, source',
              )
              .inFilter('habit_id', habitIds)
              .eq('day_of_week', _todayDayOfWeek)
              .order('start_time', ascending: true);

          fetchedSchedules = List<Map<String, dynamic>>.from(schedulesResponse);

          final today = DateTime.now();
          final todayDate =
              '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

          final logsResponse = await supabase
              .from('habit_logs')
              .select('log_id, habit_id, log_date, status, closed_at')
              .inFilter('habit_id', habitIds)
              .eq('log_date', todayDate);

          fetchedLogs = List<Map<String, dynamic>>.from(logsResponse);
        }
      }

      final Map<String, Map<String, dynamic>> goalById = {
        for (final goal in fetchedGoals) goal['goal_id'].toString(): goal,
      };

      final Map<String, Map<String, dynamic>> habitById = {
        for (final habit in fetchedHabits) habit['habit_id'].toString(): habit,
      };

      final Map<String, Map<String, dynamic>> logByHabitId = {
        for (final log in fetchedLogs) log['habit_id'].toString(): log,
      };

      final transformedGoals = fetchedGoals.map((goal) {
        return {
          'goal_id': goal['goal_id'],
          'title': goal['title'] ?? 'Untitled Goal',
          'description': goal['description'] ?? '',
          'why': goal['why'] ?? '',
          'success_metric': goal['success_metric'] ?? '',
          'category': goal['category'] ?? '',
        };
      }).toList();

      final transformedHabits = fetchedHabits.map((habit) {
        final goal = goalById[habit['goal_id'].toString()];
        return {
          'habit_id': habit['habit_id'],
          'goal_id': habit['goal_id'],
          'goal_title': goal?['title'] ?? 'Unknown Goal',
          'title': habit['title'] ?? 'Untitled Habit',
          'verification_type': habit['verification_type'],
          'enforcement_level': habit['enforcement_level'] ?? 1,
        };
      }).toList();

      final transformedTodayTasks = fetchedSchedules.map((schedule) {
        final habit = habitById[schedule['habit_id'].toString()];
        final log = logByHabitId[schedule['habit_id'].toString()];
        final goal = habit != null ? goalById[habit['goal_id'].toString()] : null;

        final status = (log?['status'] ?? 'pending').toString();

        return {
          'schedule_id': schedule['schedule_id'],
          'habit_id': schedule['habit_id'],
          'habit_title': habit?['title'] ?? 'Untitled Habit',
          'goal_title': goal?['title'] ?? 'Unknown Goal',
          'start_time': schedule['start_time'],
          'end_time': schedule['end_time'],
          'verification_type': habit?['verification_type'],
          'status': status,
          'enforcement_level': habit?['enforcement_level'] ?? 1,
        };
      }).toList();

      final transformedVerificationQueue = transformedTodayTasks
          .where((task) =>
              task['verification_type'] != null &&
              task['status'].toString() != 'done')
          .toList();

      if (!mounted) return;

      setState(() {
        profile = profileResponse;
        goals = List<Map<String, dynamic>>.from(transformedGoals);
        habits = List<Map<String, dynamic>>.from(transformedHabits);
        todaysTasks = List<Map<String, dynamic>>.from(transformedTodayTasks);
        todayLogs = List<Map<String, dynamic>>.from(fetchedLogs);
        verificationQueue =
            List<Map<String, dynamic>>.from(transformedVerificationQueue);
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');

      if (!mounted) return;
      setState(() {
        _error = 'Failed to load dashboard data.';
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await supabase.auth.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } catch (e) {
      debugPrint('Error signing out: $e');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to sign out.')),
      );
    }
  }

  String get _username {
    final username = profile?['username'];
    if (username is String && username.trim().isNotEmpty) {
      return username.trim();
    }
    return 'User';
  }

  int get _doneCount =>
      todaysTasks.where((task) => task['status'] == 'done').length;

  int get _pendingCount =>
      todaysTasks.where((task) => task['status'] != 'done').length;

  Map<String, int> get _todayGoalCounts {
    final Map<String, int> counts = {};
    for (final task in todaysTasks) {
      final goal = task['goal_title'].toString();
      counts[goal] = (counts[goal] ?? 0) + 1;
    }
    return counts;
  }

  Widget _buildTopHero() {
    final strictMode = profile?['strict_mode_enabled'] == true;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF272727)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$_todayLabel • ${_formatDate(DateTime.now())}',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Welcome back, $_username',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            strictMode
                ? 'Today is execution day. Complete your scheduled habits and protect the system.'
                : 'Stay consistent today. Focus on the habits tied directly to your goals.',
            style: const TextStyle(
              color: Colors.white70,
              height: 1.4,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildMetricChip(
                  label: 'Today',
                  value: '${todaysTasks.length}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Done',
                  value: '$_doneCount',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Pending',
                  value: '$_pendingCount',
                ),
              ),
            ],
          ),
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
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
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
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTodayTasksCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF272727)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Today’s schedule',
            subtitle: 'Your recurring commitments for today.',
          ),
          if (todaysTasks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'No habits are scheduled for today.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ...todaysTasks.map((task) {
            final status = task['status'].toString();
            final isDone = status == 'done';

            return Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF101010),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDone
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFF242424),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone ? Colors.green : Colors.white54,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task['habit_title'].toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          task['goal_title'].toString(),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_formatTimeString(task['start_time'].toString())} – ${_formatTimeString(task['end_time'].toString())}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isDone ? 'Done' : 'Pending',
                    style: TextStyle(
                      color: isDone ? Colors.greenAccent : Colors.orangeAccent,
                      fontWeight: FontWeight.w700,
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
  }

  Widget _buildGoalFocusCard() {
    final counts = _todayGoalCounts;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF272727)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Goal focus today',
            subtitle: 'What today’s habits are actually pushing forward.',
          ),
          if (counts.isEmpty)
            const Text(
              'No active goal-linked work is scheduled today.',
              style: TextStyle(color: Colors.white54),
            ),
          ...counts.entries.map(
            (entry) => Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF101010),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF242424)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${entry.value} task${entry.value == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF272727)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Verification queue',
            subtitle: 'Habits that may require evidence or completion proof.',
          ),
          if (verificationQueue.isEmpty)
            const Text(
              'No pending verification items today.',
              style: TextStyle(color: Colors.white54),
            ),
          ...verificationQueue.map(
            (task) => Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF101010),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF242424)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      task['habit_title'].toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    task['verification_type']?.toString() ?? 'manual',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalsOverviewCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF272727)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Active goals',
            subtitle: 'Your current outcomes and why they matter.',
          ),
          if (goals.isEmpty)
            const Text(
              'No active goals found.',
              style: TextStyle(color: Colors.white54),
            ),
          ...goals.map(
            (goal) => Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF101010),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF242424)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goal['title'].toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (goal['description'].toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      goal['description'].toString(),
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (goal['why'].toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Why: ${goal['why']}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopHero(),
            const SizedBox(height: 18),
            _buildTodayTasksCard(),
            const SizedBox(height: 18),
            _buildGoalFocusCard(),
            const SizedBox(height: 18),
            _buildVerificationCard(),
            const SizedBox(height: 18),
            _buildGoalsOverviewCard(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String tierText =
        profile?['plan_tier']?.toString().trim().isNotEmpty == true
            ? profile!['plan_tier'].toString().trim()
            : 'free';

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF151515),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Account",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _username,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Plan: $tierText',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.white70),
                title: const Text(
                  "Refresh",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _loadDashboardData();
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text(
                  "Sign Out",
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: _signOut,
              ),
              const Spacer(),
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Discipline compounds.',
                  style: TextStyle(color: Colors.white24),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: todaysTasks.isEmpty ? null : () {},
        backgroundColor: const Color(0xFFF5F5F5),
        foregroundColor: Colors.black,
        label: const Text("Focus"),
        icon: const Icon(Icons.center_focus_strong),
      ),
    );
  }
}