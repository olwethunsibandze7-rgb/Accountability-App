// ignore_for_file: unused_element_parameter

import 'package:achievr_app/Screens/Social/friend_profile_screen.dart';
import 'package:achievr_app/Screens/Social/friend_requests_screen.dart';
import 'package:achievr_app/Screens/Social/friends_screen.dart';
import 'package:achievr_app/Screens/Social/shared_progress_screen.dart';
import 'package:achievr_app/Screens/Social/verification_settings_screen.dart';
import 'package:achievr_app/Screens/home_screen.dart';
import 'package:achievr_app/Widgets/hold_to_refresh_wrapper.dart';
import 'package:achievr_app/Widgets/points_feedback.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isLoading = true;
  bool _isSigningOut = false;
  String? _error;

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _disciplineStats;
  List<Map<String, dynamic>> _recentBadges = [];

  int _allTimeDone = 0;
  int _activeGoals = 0;
  int _activeHabits = 0;

  @override
  void initState() {
    super.initState();
    _loadSocialData();
  }

  Future<void> _loadSocialData() async {
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

      final profileFuture = supabase
          .from('profiles')
          .select('''
            id,
            username,
            public_handle,
            plan_tier,
            strict_mode_enabled,
            wake_time,
            sleep_time,
            current_title,
            prestige_level,
            accountability_score_visible
          ''')
          .eq('id', user.id)
          .maybeSingle();

      final statsFuture = supabase
          .from('user_discipline_stats')
          .select('''
            user_id,
            execution_points,
            current_streak,
            best_streak,
            total_completed,
            total_failed,
            total_missed,
            clean_sessions
          ''')
          .eq('user_id', user.id)
          .maybeSingle();

      final goalsFuture = supabase
          .from('goals')
          .select('goal_id')
          .eq('user_id', user.id)
          .eq('active', true);

      final allDoneFuture = supabase
          .from('habit_logs')
          .select('log_id')
          .eq('user_id', user.id)
          .eq('status', 'done');

      final badgesFuture = supabase
          .from('user_badges')
          .select('''
            user_badge_id,
            awarded_at,
            badge_definitions (
              badge_id,
              code,
              title,
              description,
              icon,
              rarity,
              category
            )
          ''')
          .eq('user_id', user.id)
          .order('awarded_at', ascending: false)
          .limit(6);

      final results = await Future.wait<dynamic>([
        profileFuture,
        statsFuture,
        goalsFuture,
        allDoneFuture,
        badgesFuture,
      ]);

      final profileResponse = results[0] as Map<String, dynamic>?;
      final statsResponse = results[1] as Map<String, dynamic>?;
      final goals = List<Map<String, dynamic>>.from(results[2] as List);
      final allDone = List<Map<String, dynamic>>.from(results[3] as List);
      final recentBadges = List<Map<String, dynamic>>.from(results[4] as List);

      int activeHabits = 0;

      if (goals.isNotEmpty) {
        final goalIds = goals.map((goal) => goal['goal_id'].toString()).toList();

        final habitsResponse = await supabase
            .from('habits')
            .select('habit_id')
            .inFilter('goal_id', goalIds)
            .eq('active', true);

        activeHabits = List<Map<String, dynamic>>.from(habitsResponse).length;
      }

      if (!mounted) return;

      setState(() {
        _profile = profileResponse;
        _disciplineStats = statsResponse;
        _recentBadges = recentBadges;
        _activeGoals = goals.length;
        _activeHabits = activeHabits;
        _allTimeDone = allDone.length;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('SOCIAL SCREEN ERROR: $e');
      debugPrint('$st');

      if (!mounted) return;

      setState(() {
        _error = 'Failed to load social data.\n$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      setState(() {
        _isSigningOut = true;
      });

      await supabase.auth.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } catch (e) {
      debugPrint('SIGN OUT ERROR: $e');

      if (!mounted) return;

      setState(() {
        _isSigningOut = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to sign out.')),
      );
    }
  }

  void _openFriends() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FriendsScreen()),
    ).then((_) => _loadSocialData());
  }

  void _openRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FriendRequestsScreen()),
    ).then((_) => _loadSocialData());
  }

  void _openVerification() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VerificationSettingsScreen()),
    ).then((_) => _loadSocialData());
  }

  void _openVisibility() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SharedProgressScreen()),
    ).then((_) => _loadSocialData());
  }

  void _openOwnProfile() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          userId: user.id,
          isFriend: true,
        ),
      ),
    ).then((_) => _loadSocialData());
  }

  void _showProfileSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17171A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A3A42),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF101013),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF232329)),
                    ),
                    child: Center(
                      child: Text(
                        _username.isNotEmpty ? _username[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: Color(0xFFF5F5F5),
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _username,
                    style: const TextStyle(
                      color: Color(0xFFF5F5F5),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _publicHandle.isNotEmpty ? '@$_publicHandle' : _currentTitle,
                    style: const TextStyle(
                      color: Color(0xFF9A9AA3),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildMiniPill(label: _currentTitle, filled: true),
                      _buildMiniPill(label: 'Lv $_prestigeLevel'),
                      _buildMiniPill(label: '$_executionPoints XP'),
                      _buildMiniPill(label: 'Streak $_currentStreak'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricChip(
                          label: 'Points',
                          value: _executionPoints.toString(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricChip(
                          label: 'Current Streak',
                          value: _currentStreak.toString(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricChip(
                          label: 'Best Streak',
                          value: _bestStreak.toString(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricChip(
                          label: 'Clean Sessions',
                          value: _cleanSessions.toString(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildInfoRow('Plan', _planTier.toUpperCase()),
                  _buildInfoRow('Strict mode', _strictMode ? 'Enabled' : 'Disabled'),
                  _buildInfoRow('Wake time', _formatTimeDisplay(_wakeTime)),
                  _buildInfoRow('Sleep time', _formatTimeDisplay(_sleepTime)),
                  _buildInfoRow('Active goals', '$_activeGoals'),
                  _buildInfoRow('Active habits', '$_activeHabits'),
                  _buildInfoRow('All-time done', '$_allTimeDone'),
                  _buildInfoRow('Total failed', _totalFailed.toString()),
                  _buildInfoRow('Total missed', _totalMissed.toString()),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _buildSectionTitle(
                      'Recent badges',
                      subtitle: 'Your most recently unlocked identity markers.',
                    ),
                  ),
                  if (_recentBadges.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF101013),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF232329)),
                      ),
                      child: const Text(
                        'No badges unlocked yet.',
                        style: TextStyle(color: Color(0xFF9A9AA3)),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _recentBadges.map(_buildBadgeTile).toList(),
                    ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _openOwnProfile,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF5F5F5),
                        side: const BorderSide(color: Color(0xFF3A3A42)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Open Full Profile'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSigningOut ? null : _signOut,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF5F5F5),
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: const Color(0xFF2A2A2F),
                        disabledForegroundColor: const Color(0xFF6F6F76),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.logout),
                      label: Text(
                        _isSigningOut ? 'Signing Out...' : 'Sign Out',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String get _username {
    final username = _profile?['username'];
    if (username is String && username.trim().isNotEmpty) {
      return username.trim();
    }
    return 'User';
  }

  String get _publicHandle {
    final handle = _profile?['public_handle'];
    if (handle is String && handle.trim().isNotEmpty) {
      return handle.trim();
    }
    return '';
  }

  String get _planTier {
    final tier = _profile?['plan_tier'];
    if (tier is String && tier.trim().isNotEmpty) {
      return tier.trim();
    }
    return 'free';
  }

  String get _wakeTime {
    final wake = _profile?['wake_time'];
    return wake?.toString() ?? '--:--';
  }

  String get _sleepTime {
    final sleep = _profile?['sleep_time'];
    return sleep?.toString() ?? '--:--';
  }

  bool get _strictMode => _profile?['strict_mode_enabled'] == true;

  String get _currentTitle {
    final title = _profile?['current_title'];
    if (title is String && title.trim().isNotEmpty) {
      return title.trim();
    }
    return 'Starter';
  }

  int get _prestigeLevel {
    final value = _profile?['prestige_level'];
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse('${value ?? ''}') ?? 1;
  }

  int get _executionPoints {
    final value = _disciplineStats?['execution_points'];
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  int get _currentStreak {
    final value = _disciplineStats?['current_streak'];
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  int get _bestStreak {
    final value = _disciplineStats?['best_streak'];
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  int get _cleanSessions {
    final value = _disciplineStats?['clean_sessions'];
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  int get _totalFailed {
    final value = _disciplineStats?['total_failed'];
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  int get _totalMissed {
    final value = _disciplineStats?['total_missed'];
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  String _formatTimeDisplay(String raw) {
    if (raw == '--:--') return raw;

    final parts = raw.split(':');
    if (parts.length < 2) return raw;

    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;

    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : hour > 12 ? hour - 12 : hour;
    final minuteText = minute.toString().padLeft(2, '0');

    return '$displayHour:$minuteText $suffix';
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

  Widget _buildMiniPill({
    required String label,
    bool filled = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: filled ? const Color(0xFFF5F5F5) : const Color(0xFF101013),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: filled ? const Color(0xFFF5F5F5) : const Color(0xFF232329),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: filled ? Colors.black : const Color(0xFFF5F5F5),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        _buildIconShell(
          icon: Icons.menu_rounded,
          onTap: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        const Spacer(),
        Column(
          children: const [
            Text(
              'Social',
              style: TextStyle(
                color: Color(0xFFF5F5F5),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'Friends + accountability',
              style: TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const Spacer(),
        const _ProfileAvatarSpacer(),
      ],
    );
  }

  Widget _buildProfileAvatarButton() {
    return GestureDetector(
      onTap: _showProfileSheet,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF17171A),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF232329)),
            ),
            child: Row(
              children: [
                Text(
                  'Lv $_prestigeLevel',
                  style: const TextStyle(
                    color: Color(0xFF9A9AA3),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '•',
                  style: TextStyle(
                    color: Color(0xFF4FC3F7),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedPointsText(
                  value: _executionPoints,
                  style: const TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  suffix: ' XP',
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF17171A),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF232329)),
            ),
            child: Center(
              child: Text(
                _username.isNotEmpty ? _username[0].toUpperCase() : 'U',
                style: const TextStyle(
                  color: Color(0xFFF5F5F5),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconShell({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF17171A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF232329)),
        ),
        child: Icon(
          icon,
          color: const Color(0xFFF5F5F5),
          size: 20,
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMiniPill(label: _currentTitle, filled: true),
              _buildMiniPill(label: 'Lv $_prestigeLevel'),
              _buildMiniPill(label: 'Streak $_currentStreak'),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Hey, $_username',
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You are building a $_currentTitle identity. Keep stacking verified wins so friends instantly see progress, level, and accountability strength.',
            style: const TextStyle(
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
                  label: 'Points',
                  value: _executionPoints.toString(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'All-Time Done',
                  value: '$_allTimeDone',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Current Streak',
                  value: _currentStreak.toString(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainGrid() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Social hub',
            subtitle: 'Four clean entry points for your accountability system.',
          ),
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  icon: Icons.group_outlined,
                  title: 'Friends',
                  subtitle: 'Search and view status-rich profiles',
                  onTap: _openFriends,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionCard(
                  icon: Icons.mail_outline,
                  title: 'Requests',
                  subtitle: 'Incoming and sent invites',
                  onTap: _openRequests,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  icon: Icons.verified_user_outlined,
                  title: 'Verification',
                  subtitle: 'Manage verifiers and reviews',
                  onTap: _openVerification,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionCard(
                  icon: Icons.visibility_outlined,
                  title: 'Visibility',
                  subtitle: 'Control shared progress',
                  onTap: _openVisibility,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Accountability baseline',
            subtitle: 'The profile details people should eventually recognize.',
          ),
          Row(
            children: [
              Expanded(
                child: _buildMetricChip(
                  label: 'Active Habits',
                  value: '$_activeHabits',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Active Goals',
                  value: '$_activeGoals',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Best Streak',
                  value: _bestStreak.toString(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Title', _currentTitle),
          _buildInfoRow('Plan', _planTier.toUpperCase()),
          _buildInfoRow('Strict mode', _strictMode ? 'Enabled' : 'Disabled'),
          _buildInfoRow('Wake time', _formatTimeDisplay(_wakeTime)),
          _buildInfoRow('Sleep time', _formatTimeDisplay(_sleepTime)),
        ],
      ),
    );
  }

  Widget _buildBadgeTile(Map<String, dynamic> row) {
    final badge = row['badge_definitions'] as Map<String, dynamic>?;
    final title = (badge?['title'] ?? 'Badge').toString();
    final rarity = (badge?['rarity'] ?? 'common').toString();

    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: rarity == 'rare'
              ? const Color(0xFFFFB74D)
              : rarity == 'uncommon'
                  ? const Color(0xFF4FC3F7)
                  : const Color(0xFF232329),
        ),
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
          const SizedBox(height: 4),
          Text(
            rarity.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF101013),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF232329)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFF5F5F5), size: 20),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFFF5F5F5),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDanger ? const Color(0xFF4A2525) : const Color(0xFF232329),
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Icon(
          icon,
          color: isDanger
              ? const Color(0xFFFF8A80)
              : const Color(0xFF9A9AA3),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isDanger
                ? const Color(0xFFFF8A80)
                : const Color(0xFFF5F5F5),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF9A9AA3),
            fontSize: 12,
            height: 1.35,
          ),
        ),
        trailing: Icon(
          isDanger ? Icons.logout : Icons.chevron_right,
          color: isDanger
              ? const Color(0xFFFF8A80)
              : const Color(0xFF6F6F76),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0F0F0F),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF17171A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF232329)),
                ),
                child: Row(
                  children: [
                    _buildProfileAvatarButton(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Control Center',
                            style: TextStyle(
                              color: Color(0xFFF5F5F5),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_currentTitle • Lv $_prestigeLevel',
                            style: const TextStyle(
                              color: Color(0xFF9A9AA3),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildDrawerTile(
                icon: Icons.group_outlined,
                title: 'Friends',
                subtitle: 'Friends list and public identity preview',
                onTap: _openFriends,
              ),
              _buildDrawerTile(
                icon: Icons.mail_outline,
                title: 'Requests',
                subtitle: 'Incoming and outgoing friend requests',
                onTap: _openRequests,
              ),
              _buildDrawerTile(
                icon: Icons.verified_user_outlined,
                title: 'Verification',
                subtitle: 'Manage verifiers and partner review setup',
                onTap: _openVerification,
              ),
              _buildDrawerTile(
                icon: Icons.visibility_outlined,
                title: 'Visibility',
                subtitle: 'Control what others can see',
                onTap: _openVisibility,
              ),
              const Spacer(),
              _buildDrawerTile(
                icon: Icons.logout,
                title: _isSigningOut ? 'Signing Out...' : 'Sign Out',
                subtitle: 'End your current session',
                isDanger: true,
                onTap: _isSigningOut ? () {} : _signOut,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFFF5F5F5),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF5F5F5)),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFB3B3BB)),
          ),
        ),
      );
    }

    return HoldToRefreshWrapper(
      onRefresh: _loadSocialData,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                _buildTopBar(),
                Positioned(
                  right: 0,
                  child: _buildProfileAvatarButton(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _buildHeroCard(),
            const SizedBox(height: 18),
            _buildMainGrid(),
            const SizedBox(height: 18),
            _buildSnapshotCard(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0B0B0C),
      drawer: _buildDrawer(),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }
}

class _ProfileAvatarSpacer extends StatelessWidget {
  const _ProfileAvatarSpacer();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 44, height: 44);
  }
}