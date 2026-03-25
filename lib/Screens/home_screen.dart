import 'package:achievr_app/Screens/Dashboard/dashboard_screen.dart';
import 'package:achievr_app/Screens/goal_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'goal_input_screen.dart';
import 'time_constraint_screen.dart';
import 'confirmation_screen.dart';
import 'goal_setup_screen.dart';

// --------------------------
// Providers
// --------------------------

final supabaseSessionProvider = StreamProvider<Session?>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange
      .map((event) => event.session);
});

// --------------------------
// HomeScreen
// --------------------------

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeInController;
  AnimationController? _fadeOutController;
  late final Animation<double> _opacityIn;
  Animation<double>? _opacityOut;

  final SupabaseClient supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();

    _fadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _opacityIn = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _fadeInController,
        curve: Curves.easeOutCubic,
      ),
    );

    _fadeInController.forward();

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      _startFadeOut();
    });
  }

  void _startFadeOut() {
    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _opacityOut = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _fadeOutController!,
        curve: Curves.easeInOut,
      ),
    );

    _fadeOutController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (!mounted) return;
        _checkAuthAndNavigate();
      }
    });

    _fadeOutController!.forward();
  }

  Future<void> _checkAuthAndNavigate() async {
    final session = supabase.auth.currentSession;

    if (session == null) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginSignupScreen()),
      );
      return;
    }

    try {
      final userId = session.user.id;

      final profile = await supabase
          .from('profiles')
          .select(
            'username, setup_completed, onboarding_step, plan_tier, strict_mode_enabled',
          )
          .eq('id', userId)
          .maybeSingle();

      if (profile == null) {
        await supabase.auth.signOut();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginSignupScreen()),
        );
        return;
      }

      final bool setupCompleted = (profile['setup_completed'] as bool?) ?? false;
      final int onboardingStep = (profile['onboarding_step'] as int?) ?? 0;

      if (!mounted) return;

      if (setupCompleted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
        return;
      }

      switch (onboardingStep) {
        case 0:
        case 1:
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const GoalSetupIntroScreen()),
          );
          break;

        case 2:
          await _resumeGoalInput(userId);
          break;

        case 3:
          await _resumeTimeConstraints(userId);
          break;

        case 4:
          await _resumeConfirmation(userId);
          break;

        default:
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const GoalSetupIntroScreen()),
          );
      }
    } catch (e) {
      debugPrint('Error checking auth/setup state: $e');

      await supabase.auth.signOut();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginSignupScreen()),
      );
    }
  }

  Future<void> _resumeGoalInput(String userId) async {
    final goalsResponse = await supabase
        .from('goals')
        .select('goal_id, title, category, description, why, success_metric')
        .eq('user_id', userId)
        .eq('active', true)
        .order('created_at', ascending: true);

    final List<Map<String, dynamic>> goalRecords =
        List<Map<String, dynamic>>.from(goalsResponse);

    if (!mounted) return;

    if (goalRecords.isEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const GoalSetupIntroScreen()),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GoalInputScreen(
          userId: userId,
          selectedGoalRecords: goalRecords,
          goalHabits: GoalSelectionScreen.goalHabits,
        ),
      ),
    );
  }

  Future<void> _resumeTimeConstraints(String userId) async {
    final detailedGoals = await _buildDetailedGoalsFromDb(userId);

    if (!mounted) return;

    if (detailedGoals.isEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const GoalSetupIntroScreen()),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TimeConstraintScreen(
          detailedGoals: detailedGoals,
          userId: userId,
        ),
      ),
    );
  }

  Future<void> _resumeConfirmation(String userId) async {
    final detailedGoals = await _buildDetailedGoalsFromDb(userId);
    final blockedHours = await _loadBlockedHoursFromDb(userId);

    final goalsWithHabits = detailedGoals.map((goal) {
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
    }).toList();

    if (!mounted) return;

    if (goalsWithHabits.isEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const GoalSetupIntroScreen()),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ConfirmationScreen(
          schedule: const {},
          userId: userId,
          goalsWithHabits: goalsWithHabits,
          blockedHours: blockedHours,
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _buildDetailedGoalsFromDb(
    String userId,
  ) async {
    final goalsResponse = await supabase
        .from('goals')
        .select('goal_id, title, category, description, why, success_metric')
        .eq('user_id', userId)
        .eq('active', true)
        .order('created_at', ascending: true);

    final List<Map<String, dynamic>> goalRows =
        List<Map<String, dynamic>>.from(goalsResponse);

    if (goalRows.isEmpty) return [];

    final List<String> goalIds =
        goalRows.map((g) => g['goal_id'].toString()).toList();

    final habitsResponse = await supabase
        .from('habits')
        .select('goal_id, title')
        .inFilter('goal_id', goalIds)
        .eq('active', true)
        .order('created_at', ascending: true);

    final List<Map<String, dynamic>> habitRows =
        List<Map<String, dynamic>>.from(habitsResponse);

    final Map<String, List<String>> habitsByGoalId = {};
    for (final row in habitRows) {
      final goalId = row['goal_id'].toString();
      final title = row['title'].toString();
      habitsByGoalId.putIfAbsent(goalId, () => []);
      habitsByGoalId[goalId]!.add(title);
    }

    return goalRows.map((goal) {
      final goalId = goal['goal_id'].toString();
      return {
        'goal_id': goalId,
        'title': goal['title'],
        'category': goal['category'],
        'description': goal['description'] ?? '',
        'why': goal['why'] ?? '',
        'metrics': goal['success_metric'] ?? '',
        'habits': habitsByGoalId[goalId] ?? <String>[],
      };
    }).toList();
  }

  Future<Map<String, Set<int>>> _loadBlockedHoursFromDb(String userId) async {
    const dayMap = {
      1: 'Monday',
      2: 'Tuesday',
      3: 'Wednesday',
      4: 'Thursday',
      5: 'Friday',
      6: 'Saturday',
    };

    final Map<String, Set<int>> blockedHours = {
      'Monday': <int>{},
      'Tuesday': <int>{},
      'Wednesday': <int>{},
      'Thursday': <int>{},
      'Friday': <int>{},
      'Saturday': <int>{},
    };

    final response = await supabase
        .from('fixed_time_blocks')
        .select('day_of_week, start_time, end_time')
        .eq('user_id', userId);

    for (final row in response) {
      final int dayIndex = row['day_of_week'] as int;
      final String? dayName = dayMap[dayIndex];
      if (dayName == null) continue;

      final int startHour =
          int.parse((row['start_time'] as String).split(':')[0]);
      final int endHour = int.parse((row['end_time'] as String).split(':')[0]);

      for (int hour = startHour; hour < endHour; hour++) {
        blockedHours[dayName]!.add(hour);
      }
    }

    return blockedHours;
  }

  @override
  void dispose() {
    _fadeInController.dispose();
    _fadeOutController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _fadeInController,
          if (_fadeOutController != null) _fadeOutController!,
        ]),
        builder: (context, child) {
          double opacity = _opacityIn.value;

          if (_fadeOutController != null && _opacityOut != null) {
            opacity *= _opacityOut!.value;
          }

          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: child,
          );
        },
        child: const Center(
          child: Text(
            'achievr.',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------
// LOGIN / SIGNUP SCREEN
// --------------------------

class LoginSignupScreen extends StatefulWidget {
  const LoginSignupScreen({super.key});

  @override
  State<LoginSignupScreen> createState() => _LoginSignupScreenState();
}

class _LoginSignupScreenState extends State<LoginSignupScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  Future<void> _showLoginDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AuthLoginDialog(supabase: supabase),
    );
  }

  Future<void> _showSignupDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AuthSignupDialog(supabase: supabase),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Welcome To Achievr',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'We are discipline, structure and accountability',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFB3B3BB),
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _showLoginDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _showSignupDialog,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthLoginDialog extends StatefulWidget {
  final SupabaseClient supabase;

  const _AuthLoginDialog({required this.supabase});

  @override
  State<_AuthLoginDialog> createState() => _AuthLoginDialogState();
}

class _AuthLoginDialogState extends State<_AuthLoginDialog> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _error;

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are required.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await widget.supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.session == null) {
        setState(() => _error = 'Login failed. Check credentials.');
        return;
      }

      if (!mounted) return;

      Navigator.of(context).pop();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Unexpected error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.white12,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 16,
        horizontal: 16,
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF17171A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Login',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to continue your execution system.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFB3B3BB),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Email'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Password'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Login',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthSignupDialog extends StatefulWidget {
  final SupabaseClient supabase;

  const _AuthSignupDialog({required this.supabase});

  @override
  State<_AuthSignupDialog> createState() => _AuthSignupDialogState();
}

class _AuthSignupDialogState extends State<_AuthSignupDialog> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _error;

  bool _strictModeEnabled = true;
  String _selectedPlan = 'free';
  TimeOfDay _wakeTime = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _sleepTime = const TimeOfDay(hour: 22, minute: 0);

  Future<void> _pickWakeTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _wakeTime,
    );

    if (picked != null) {
      setState(() => _wakeTime = picked);
    }
  }

  Future<void> _pickSleepTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _sleepTime,
    );

    if (picked != null) {
      setState(() => _sleepTime = picked);
    }
  }

  String _timeToDbString(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }

  String _timeToLabel(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $suffix';
  }

Future<void> _signup() async {
  final username = _usernameController.text.trim();
  final email = _emailController.text.trim();
  final password = _passwordController.text.trim();

  if (username.isEmpty) {
    setState(() => _error = 'Username is required.');
    return;
  }

  if (email.isEmpty || password.isEmpty) {
    setState(() => _error = 'Email and password are required.');
    return;
  }

  if (password.length < 6) {
    setState(() => _error = 'Password must be at least 6 characters.');
    return;
  }

  setState(() {
    _isLoading = true;
    _error = null;
  });

  try {
    final response = await widget.supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'username': username,
      },
    );

    final user = response.user;
    if (user == null) {
      setState(() => _error = 'Signup failed. Try again.');
      return;
    }

    final cleanBase = username
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '')
        .replaceAll(RegExp(r'_+'), '_');

    final safeBase = cleanBase.isEmpty ? 'user' : cleanBase;
    final shortCode =
        user.id.replaceAll('-', '').substring(0, 4).toUpperCase();
    final publicHandle = '${safeBase}_$shortCode';

    await widget.supabase.from('profiles').upsert({
      'id': user.id,
      'username': username,
      'public_handle': publicHandle,
      'timezone': 'UTC',
      'plan_tier': _selectedPlan,
      'strict_mode_enabled': _strictModeEnabled,
      'wake_time': _timeToDbString(_wakeTime),
      'sleep_time': _timeToDbString(_sleepTime),
      'setup_completed': false,
      'onboarding_step': 1,
    });

    if (!mounted) return;

    Navigator.of(context).pop();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const GoalSetupIntroScreen()),
    );
  } on AuthException catch (e) {
    setState(() => _error = e.message);
  } catch (e) {
    setState(() => _error = 'Unexpected error: $e');
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.white12,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 16,
        horizontal: 16,
      ),
    );
  }

  Widget _buildLockedPlanCard({
    required String title,
    required String subtitle,
    required bool selected,
    required bool locked,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: locked ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF101013),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Colors.blueAccent
                : locked
                    ? const Color(0xFF3A3A42)
                    : const Color(0xFF232329),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: locked
                              ? const Color(0xFF7C7C84)
                              : const Color(0xFFF5F5F5),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (locked) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.lock,
                          color: Color(0xFF7C7C84),
                          size: 16,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: locked
                          ? const Color(0xFF6F6F76)
                          : const Color(0xFF9A9AA3),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Radio<String>(
              value: title.toLowerCase() == 'free' ? 'free' : 'pro',
              // ignore: deprecated_member_use
              groupValue: _selectedPlan,
              // ignore: deprecated_member_use
              onChanged: locked
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _selectedPlan = value);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF17171A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Sign Up',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create your account and set your default execution profile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFB3B3BB),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Username'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Email'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Password'),
                ),
                const SizedBox(height: 14),
                const SizedBox(height: 18),
                Container(
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
                        'Plan',
                        style: TextStyle(
                          color: Color(0xFFF5F5F5),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildLockedPlanCard(
                        title: 'Free',
                        subtitle: 'Default plan for your current build.',
                        selected: _selectedPlan == 'free',
                        locked: false,
                        onTap: () => setState(() => _selectedPlan = 'free'),
                      ),
                      const SizedBox(height: 10),
                      _buildLockedPlanCard(
                        title: 'Pro',
                        subtitle: 'Locked for now. Paid plan is not yet available in this build.',
                        selected: _selectedPlan == 'pro',
                        locked: true,
                        onTap: null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101013),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF232329)),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _strictModeEnabled,
                    onChanged: (value) {
                      setState(() => _strictModeEnabled = value);
                    },
                    activeThumbColor: Colors.blueAccent,
                    title: const Text(
                      'Strict mode',
                      style: TextStyle(
                        color: Color(0xFFF5F5F5),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'Enable a stricter default accountability profile.',
                      style: TextStyle(color: Color(0xFF9A9AA3)),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _pickWakeTime,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Wake time',
                              style: TextStyle(color: Color(0xFF9A9AA3)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _timeToLabel(_wakeTime),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _pickSleepTime,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Sleep time',
                              style: TextStyle(color: Color(0xFF9A9AA3)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _timeToLabel(_sleepTime),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Create Account',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}