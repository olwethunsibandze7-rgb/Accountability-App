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

    final bool setupCompleted =
        (profile['setup_completed'] as bool?) ?? false;
    final int onboardingStep =
        (profile['onboarding_step'] as int?) ?? 0;

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

Future<List<Map<String, dynamic>>> _buildDetailedGoalsFromDb(String userId) async {
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
    final int endHour =
        int.parse((row['end_time'] as String).split(':')[0]);

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
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  final SupabaseClient supabase = Supabase.instance.client;

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
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.session == null) {
        setState(() => _error = 'Login failed. Check credentials.');
        return;
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
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

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await supabase.auth.signUp(
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

      // Profile should already be created by DB trigger.
      // This update makes sure the important onboarding defaults are set.
      await supabase.from('profiles').update({
        'username': username,
        'timezone': 'UTC',
        'plan_tier': 'free',
        'strict_mode_enabled': true,
        'wake_time': '06:00:00',
        'sleep_time': '22:00:00',
        'setup_completed': false,
        'onboarding_step': 1,
      }).eq('id', user.id);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: Colors.white12,
      hintStyle: const TextStyle(color: Colors.white70),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 16,
        horizontal: 20,
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  const Text(
                    'Welcome to Achievr',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 40),

                  TextField(
                    controller: _usernameController,
                    decoration: inputDecoration.copyWith(hintText: 'Username'),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _emailController,
                    decoration: inputDecoration.copyWith(hintText: 'Email'),
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _passwordController,
                    decoration: inputDecoration.copyWith(hintText: 'Password'),
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 24),

                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
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
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton(
                            onPressed: _signup,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white24),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
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
                        const SizedBox(height: 24),
                      ],
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