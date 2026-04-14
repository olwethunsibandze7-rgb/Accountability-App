// ignore_for_file: unnecessary_cast

import 'package:achievr_app/Screens/Social/focus_policy_settings_screen.dart';
import 'package:achievr_app/Screens/Social/set_habit_location_screen.dart';
import 'package:achievr_app/Services/friends_service.dart';
import 'package:achievr_app/Services/habit_location_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VerificationSettingsScreen extends StatefulWidget {
  const VerificationSettingsScreen({super.key});

  @override
  State<VerificationSettingsScreen> createState() =>
      _VerificationSettingsScreenState();
}

class _VerificationSettingsScreenState
    extends State<VerificationSettingsScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;
  final FriendsService _friendsService = FriendsService();
  final HabitLocationService _habitLocationService = HabitLocationService();

  late TabController _tabController;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  List<Map<String, dynamic>> _habits = [];
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _myPendingSubmissions = [];
  List<Map<String, dynamic>> _inboxPending = [];
  List<Map<String, dynamic>> _inboxReviewed = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHubData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  Future<void> _loadHubData() async {
    final userId = _currentUserId;
    if (userId == null) {
      setState(() {
        _isLoading = false;
        _error = 'No authenticated user found.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final friendsFuture = _friendsService.fetchAcceptedFriendProfiles();
      final habitsFuture = _fetchMyHabits(userId);
      final myPendingFuture = _fetchRequestsForRequester(
        requesterUserId: userId,
        onlyPending: true,
      );
      final inboxPendingFuture = _fetchRequestsForVerifier(
        verifierUserId: userId,
        onlyPending: true,
      );
      final inboxReviewedFuture = _fetchRequestsForVerifier(
        verifierUserId: userId,
        reviewedOnly: true,
        limit: 10,
      );

      final results = await Future.wait([
        friendsFuture,
        habitsFuture,
        myPendingFuture,
        inboxPendingFuture,
        inboxReviewedFuture,
      ]);

      if (!mounted) return;

      setState(() {
        _friends = List<Map<String, dynamic>>.from(results[0] as List);
        _habits = List<Map<String, dynamic>>.from(results[1] as List);
        _myPendingSubmissions =
            List<Map<String, dynamic>>.from(results[2] as List);
        _inboxPending = List<Map<String, dynamic>>.from(results[3] as List);
        _inboxReviewed = List<Map<String, dynamic>>.from(results[4] as List);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Failed to load verification hub.\n$e';
        _isLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchMyHabits(String userId) async {
    final goalRows = await _supabase
        .from('goals')
        .select('goal_id, title')
        .eq('user_id', userId)
        .eq('active', true)
        .order('created_at', ascending: true);

    final goals = List<Map<String, dynamic>>.from(goalRows);
    if (goals.isEmpty) return [];

    final goalIds = goals.map((g) => g['goal_id'].toString()).toList();
    final goalMap = {
      for (final goal in goals) goal['goal_id'].toString(): goal,
    };

    final habitRows = await _supabase
        .from('habits')
        .select('''
          habit_id,
          goal_id,
          title,
          verification_type,
          requires_verifier,
          verification_locked,
          active
        ''')
        .inFilter('goal_id', goalIds)
        .eq('active', true)
        .order('created_at', ascending: true);

    final habits = List<Map<String, dynamic>>.from(habitRows);
    if (habits.isEmpty) return [];

    final habitIds = habits.map((h) => h['habit_id'].toString()).toList();

    final verifierRows = List<Map<String, dynamic>>.from(
      await _supabase
          .from('habit_verifiers')
          .select('habit_id, verifier_user_id, active')
          .inFilter('habit_id', habitIds)
          .eq('active', true),
    );

    final verifierMap = {
      for (final row in verifierRows) row['habit_id'].toString(): row,
    };

    final locationConfigRows = List<Map<String, dynamic>>.from(
      await _supabase
          .from('habit_location_configs')
          .select('''
            habit_location_config_id,
            habit_id,
            label,
            latitude,
            longitude,
            radius_meters,
            active
          ''')
          .inFilter('habit_id', habitIds)
          .eq('active', true),
    );

    final locationConfigMap = {
      for (final row in locationConfigRows) row['habit_id'].toString(): row,
    };

    return habits.map((habit) {
      final goal = goalMap[habit['goal_id'].toString()];
      final verifier = verifierMap[habit['habit_id'].toString()];
      final locationConfig = locationConfigMap[habit['habit_id'].toString()];

      return {
        ...habit,
        'goal_title': goal?['title']?.toString() ?? 'Unknown Goal',
        'verifier_user_id': verifier?['verifier_user_id'],
        'location_config': locationConfig,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchRequestsForRequester({
    required String requesterUserId,
    bool onlyPending = false,
    bool reviewedOnly = false,
    int limit = 100,
  }) async {
    var query = _supabase
        .from('log_verification_requests')
        .select('''
          request_id,
          log_id,
          habit_id,
          requester_user_id,
          verifier_user_id,
          status,
          note,
          submitted_at,
          reviewed_at
        ''')
        .eq('requester_user_id', requesterUserId);

    if (onlyPending) {
      query = query.eq('status', 'pending');
    }

    final rows =
        await query.order('submitted_at', ascending: false).limit(limit);

    final baseRows = List<Map<String, dynamic>>.from(rows);

    final filtered = reviewedOnly
        ? baseRows
            .where((row) => (row['status'] ?? '').toString() != 'pending')
            .toList()
        : baseRows;

    return _enrichRequests(filtered);
  }

  Future<List<Map<String, dynamic>>> _fetchRequestsForVerifier({
    required String verifierUserId,
    bool onlyPending = false,
    bool reviewedOnly = false,
    int limit = 100,
  }) async {
    var query = _supabase
        .from('log_verification_requests')
        .select('''
          request_id,
          log_id,
          habit_id,
          requester_user_id,
          verifier_user_id,
          status,
          note,
          submitted_at,
          reviewed_at
        ''')
        .eq('verifier_user_id', verifierUserId);

    if (onlyPending) {
      query = query.eq('status', 'pending');
    }

    final rows =
        await query.order('submitted_at', ascending: false).limit(limit);

    final baseRows = List<Map<String, dynamic>>.from(rows);

    final filtered = reviewedOnly
        ? baseRows
            .where((row) => (row['status'] ?? '').toString() != 'pending')
            .toList()
        : baseRows;

    return _enrichRequests(filtered);
  }

  Future<List<Map<String, dynamic>>> _enrichRequests(
    List<Map<String, dynamic>> baseRows,
  ) async {
    if (baseRows.isEmpty) return [];

    final requesterIds = baseRows
        .map((row) => row['requester_user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final verifierIds = baseRows
        .map((row) => row['verifier_user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final habitIds = baseRows
        .map((row) => row['habit_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final logIds = baseRows
        .map((row) => row['log_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final userIds = {...requesterIds, ...verifierIds}.toList();

    final profilesFuture = userIds.isEmpty
        ? Future.value(<Map<String, dynamic>>[])
        : _supabase
            .from('profiles')
            .select('id, username, public_handle')
            .inFilter('id', userIds)
            .then((value) => List<Map<String, dynamic>>.from(value));

    final habitsFuture = habitIds.isEmpty
        ? Future.value(<Map<String, dynamic>>[])
        : _supabase
            .from('habits')
            .select('habit_id, title, goal_id')
            .inFilter('habit_id', habitIds)
            .then((value) => List<Map<String, dynamic>>.from(value));

    final logsFuture = logIds.isEmpty
        ? Future.value(<Map<String, dynamic>>[])
        : _supabase
            .from('habit_logs')
            .select('log_id, log_date, scheduled_start, scheduled_end, status')
            .inFilter('log_id', logIds)
            .then((value) => List<Map<String, dynamic>>.from(value));

    final results = await Future.wait([
      profilesFuture,
      habitsFuture,
      logsFuture,
    ]);

    final profiles = results[0] as List<Map<String, dynamic>>;
    final habits = results[1] as List<Map<String, dynamic>>;
    final logs = results[2] as List<Map<String, dynamic>>;

    final profileMap = {
      for (final row in profiles) row['id'].toString(): row,
    };
    final habitMap = {
      for (final row in habits) row['habit_id'].toString(): row,
    };
    final logMap = {
      for (final row in logs) row['log_id'].toString(): row,
    };

    final goalIds = habits
        .map((row) => row['goal_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final goalRows = goalIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(await _supabase
            .from('goals')
            .select('goal_id, title')
            .inFilter('goal_id', goalIds));

    final goalMap = {
      for (final row in goalRows) row['goal_id'].toString(): row,
    };

    return baseRows.map((row) {
      final requester = profileMap[row['requester_user_id']?.toString() ?? ''];
      final verifier = profileMap[row['verifier_user_id']?.toString() ?? ''];
      final habit = habitMap[row['habit_id']?.toString() ?? ''];
      final goal = goalMap[habit?['goal_id']?.toString() ?? ''];
      final log = logMap[row['log_id']?.toString() ?? ''];

      return {
        ...row,
        'requester_profile': requester,
        'verifier_profile': verifier,
        'habit_title': habit?['title']?.toString() ?? 'Untitled Habit',
        'goal_title': goal?['title']?.toString() ?? 'Unknown Goal',
        'log_meta': log,
      };
    }).toList();
  }

  bool _habitNeedsVerifier(Map<String, dynamic> habit) {
    final type = (habit['verification_type'] ?? '').toString();
    final requiresVerifier = habit['requires_verifier'] == true;

    return requiresVerifier ||
        type == 'partner' ||
        type == 'focus_partner' ||
        type == 'location_partner' ||
        type == 'location_focus_partner';
  }

  bool _habitSupportsFocusPolicy(Map<String, dynamic> habit) {
    final type = (habit['verification_type'] ?? '').toString();

    return type == 'focus_auto' ||
        type == 'focus_partner' ||
        type == 'location_focus' ||
        type == 'location_focus_partner';
  }

  bool _habitNeedsLocation(Map<String, dynamic> habit) {
    final type = (habit['verification_type'] ?? '').toString();
    return _habitLocationService.habitRequiresLocation(type);
  }

  bool _shouldShowInMySetup(Map<String, dynamic> habit) {
    return _habitNeedsVerifier(habit) ||
        _habitSupportsFocusPolicy(habit) ||
        _habitNeedsLocation(habit);
  }

  Future<void> _openFocusPolicyForHabit(Map<String, dynamic> habit) async {
    final habitId = habit['habit_id']?.toString();
    final title = (habit['title'] ?? 'Habit').toString();
    final verificationType =
        (habit['verification_type'] ?? 'manual').toString();

    if (habitId == null || habitId.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FocusPolicySettingsScreen(
          habitId: habitId,
          habitTitle: title,
          verificationType: verificationType,
        ),
      ),
    );

    if (!mounted) return;
    await _loadHubData();
  }

  Future<void> _openLocationSetupForHabit(Map<String, dynamic> habit) async {
    final habitId = habit['habit_id']?.toString();
    final title = (habit['title'] ?? 'Habit').toString();
    final verificationType =
        (habit['verification_type'] ?? 'manual').toString();

    if (habitId == null || habitId.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SetHabitLocationScreen(
          habitId: habitId,
          habitTitle: title,
          verificationType: verificationType,
        ),
      ),
    );

    if (!mounted) return;
    await _loadHubData();
  }

  String _friendNameFromUserId(String? userId) {
    if (userId == null || userId.isEmpty) return 'No verifier';

    for (final friend in _friends) {
      final otherProfile = friend['other_profile'] as Map<String, dynamic>?;
      final otherUserId = friend['other_user_id']?.toString();

      if (otherUserId == userId) {
        final username = (otherProfile?['username'] ?? '').toString();
        if (username.isNotEmpty) return username;
      }
    }

    return 'Unknown';
  }

  String _verificationLabel(String raw) {
    switch (raw) {
      case 'manual':
        return 'Manual';
      case 'focus_auto':
        return 'Focus Auto';
      case 'partner':
        return 'Partner Review';
      case 'focus_partner':
        return 'Focus + Partner';
      case 'location':
        return 'Location';
      case 'location_focus':
        return 'Location + Focus';
      case 'location_partner':
        return 'Location + Partner';
      case 'location_focus_partner':
        return 'Location + Focus + Partner';
      default:
        return raw.replaceAll('_', ' ');
    }
  }

  String _requestStatusLabel(String raw) {
    switch (raw) {
      case 'pending':
        return 'Pending';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'expired':
        return 'Expired';
      default:
        return raw;
    }
  }

  String _locationSummary(Map<String, dynamic> habit) {
    final config = habit['location_config'] as Map<String, dynamic>?;
    if (config == null) {
      return 'Pinned place: Not set';
    }

    final label = (config['label'] ?? 'Pinned place').toString();
    final radius = config['radius_meters']?.toString() ?? 'Unknown';
    return 'Pinned place: $label • ${radius}m radius';
  }

  Color _requestStatusColor(String raw) {
    switch (raw) {
      case 'pending':
        return const Color(0xFF81D4FA);
      case 'approved':
        return const Color(0xFF81C784);
      case 'rejected':
      case 'expired':
        return const Color(0xFFE57373);
      default:
        return const Color(0xFF9A9AA3);
    }
  }

  Future<void> _pickVerifierForHabit(Map<String, dynamic> habit) async {
    if (_friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a friend first before assigning a verifier.'),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: const Color(0xFF17171A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose verifier',
                  style: TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  habit['title']?.toString() ?? 'Habit',
                  style: const TextStyle(
                    color: Color(0xFFB3B3BB),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                ..._friends.map((friend) {
                  final otherProfile =
                      friend['other_profile'] as Map<String, dynamic>?;
                  final username =
                      (otherProfile?['username'] ?? 'Unknown').toString();
                  final publicHandle =
                      (otherProfile?['public_handle'] ?? '').toString();
                  final otherUserId =
                      friend['other_user_id']?.toString() ?? '';

                  return Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101013),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF232329)),
                    ),
                    child: ListTile(
                      onTap: () => Navigator.pop(context, otherUserId),
                      title: Text(
                        username,
                        style: const TextStyle(color: Color(0xFFF5F5F5)),
                      ),
                      subtitle: Text(
                        publicHandle.isNotEmpty ? '@$publicHandle' : otherUserId,
                        style: const TextStyle(color: Color(0xFF9A9AA3)),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Color(0xFF9A9AA3),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, ''),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF8A80),
                      side: const BorderSide(color: Color(0xFFFF8A80)),
                    ),
                    child: const Text('Clear verifier'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) return;

    final habitId = habit['habit_id']?.toString();
    final currentUserId = _currentUserId;

    if (habitId == null || currentUserId == null) return;

    try {
      setState(() {
        _isSaving = true;
      });

      await _supabase
          .from('habit_verifiers')
          .update({'active': false})
          .eq('habit_id', habitId)
          .eq('active', true);

      if (selected.isNotEmpty) {
        await _supabase.from('habit_verifiers').insert({
          'habit_id': habitId,
          'verifier_user_id': selected,
          'assigned_by_user_id': currentUserId,
          'active': true,
        });
      }

      await _loadHubData();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selected.isEmpty ? 'Verifier removed.' : 'Verifier assigned.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to assign verifier: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _reviewRequest({
    required Map<String, dynamic> request,
    required bool approve,
  }) async {
    final requestId = request['request_id']?.toString();
    final logId = request['log_id']?.toString();

    if (requestId == null || logId == null) return;

    try {
      setState(() {
        _isSaving = true;
      });

      await _supabase.from('log_verification_requests').update({
        'status': approve ? 'approved' : 'rejected',
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('request_id', requestId);

      await _supabase.from('habit_logs').update({
        'status': approve ? 'done' : 'rejected',
        'closed_at': DateTime.now().toIso8601String(),
      }).eq('log_id', logId);

      await _loadHubData();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'Verification approved.' : 'Verification rejected.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to review request: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
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
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactActionChip({
    required String text,
    required bool filled,
    required VoidCallback? onTap,
  }) {
    final foreground = filled ? Colors.black : const Color(0xFFF5F5F5);
    final background =
        filled ? const Color(0xFFF5F5F5) : Colors.transparent;
    final borderColor =
        filled ? const Color(0xFFF5F5F5) : const Color(0xFF3A3A42);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final partnerHabits =
        _habits.where((habit) => _habitNeedsVerifier(habit)).length;
    final focusHabits =
        _habits.where((habit) => _habitSupportsFocusPolicy(habit)).length;
    final locationHabits =
        _habits.where((habit) => _habitNeedsLocation(habit)).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _buildMetricChip(
              label: 'Partner',
              value: '$partnerHabits',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildMetricChip(
              label: 'Focus',
              value: '$focusHabits',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildMetricChip(
              label: 'Location',
              value: '$locationHabits',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildMetricChip(
              label: 'Review',
              value: '${_inboxPending.length}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String raw) {
    final color = _requestStatusColor(raw);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        _requestStatusLabel(raw),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildMyHabitCard(Map<String, dynamic> habit) {
    final title = (habit['title'] ?? 'Untitled Habit').toString();
    final goalTitle = (habit['goal_title'] ?? 'Unknown Goal').toString();
    final verificationTypeRaw =
        (habit['verification_type'] ?? 'manual').toString();
    final verificationType = _verificationLabel(verificationTypeRaw);

    final needsVerifier = _habitNeedsVerifier(habit);
    final supportsFocusPolicy = _habitSupportsFocusPolicy(habit);
    final needsLocation = _habitNeedsLocation(habit);
    final verifierName =
        _friendNameFromUserId(habit['verifier_user_id']?.toString());
    final hasLocationConfig =
        (habit['location_config'] as Map<String, dynamic>?) != null;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            goalTitle,
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Method: $verificationType',
            style: const TextStyle(
              color: Color(0xFFB3B3BB),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            needsVerifier ? 'Verifier: $verifierName' : 'No verifier needed',
            style: const TextStyle(
              color: Color(0xFFB3B3BB),
              fontSize: 12,
            ),
          ),
          if (supportsFocusPolicy) ...[
            const SizedBox(height: 4),
            const Text(
              'Focus policy: allowed apps and grace period can be configured.',
              style: TextStyle(
                color: Color(0xFFB3B3BB),
                fontSize: 12,
              ),
            ),
          ],
          if (needsLocation) ...[
            const SizedBox(height: 4),
            Text(
              _locationSummary(habit),
              style: TextStyle(
                color: hasLocationConfig
                    ? const Color(0xFFB3B3BB)
                    : const Color(0xFFFFB74D),
                fontSize: 12,
              ),
            ),
          ],
          if (needsVerifier || supportsFocusPolicy || needsLocation) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (needsVerifier)
                  _buildCompactActionChip(
                    text:
                        habit['verifier_user_id'] == null ? 'Assign' : 'Change',
                    filled: false,
                    onTap: _isSaving ? null : () => _pickVerifierForHabit(habit),
                  ),
                if (needsLocation)
                  _buildCompactActionChip(
                    text: hasLocationConfig ? 'Change Location' : 'Set Location',
                    filled: false,
                    onTap:
                        _isSaving ? null : () => _openLocationSetupForHabit(habit),
                  ),
                if (supportsFocusPolicy)
                  _buildCompactActionChip(
                    text: 'Focus Policy',
                    filled: true,
                    onTap: _isSaving
                        ? null
                        : () => _openFocusPolicyForHabit(habit),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubmissionCard(Map<String, dynamic> request) {
    final verifier = request['verifier_profile'] as Map<String, dynamic>?;
    final verifierName = (verifier?['username'] ?? 'Unknown').toString();

    final logMeta = request['log_meta'] as Map<String, dynamic>?;
    final scheduledStart = logMeta?['scheduled_start']?.toString();
    final scheduledEnd = logMeta?['scheduled_end']?.toString();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request['habit_title']?.toString() ?? 'Untitled Habit',
                  style: const TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _buildStatusChip((request['status'] ?? 'pending').toString()),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            request['goal_title']?.toString() ?? 'Unknown Goal',
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Verifier: $verifierName',
            style: const TextStyle(
              color: Color(0xFFB3B3BB),
              fontSize: 12,
            ),
          ),
          if (scheduledStart != null && scheduledEnd != null) ...[
            const SizedBox(height: 4),
            Text(
              'Window: $scheduledStart → $scheduledEnd',
              style: const TextStyle(
                color: Color(0xFFB3B3BB),
                fontSize: 12,
              ),
            ),
          ],
          if ((request['note'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Note: ${(request['note'] ?? '').toString()}',
              style: const TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInboxCard(Map<String, dynamic> request, {bool reviewed = false}) {
    final requester = request['requester_profile'] as Map<String, dynamic>?;
    final requesterName = (requester?['username'] ?? 'Unknown').toString();

    final scheduled = request['log_meta'] as Map<String, dynamic>?;
    final start = scheduled?['scheduled_start']?.toString();
    final end = scheduled?['scheduled_end']?.toString();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request['habit_title']?.toString() ?? 'Untitled Habit',
                  style: const TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _buildStatusChip((request['status'] ?? 'pending').toString()),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${request['goal_title']?.toString() ?? 'Unknown Goal'} • $requesterName',
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              fontSize: 12,
            ),
          ),
          if (start != null && end != null) ...[
            const SizedBox(height: 8),
            Text(
              'Scheduled window: $start → $end',
              style: const TextStyle(
                color: Color(0xFFB3B3BB),
                fontSize: 12,
              ),
            ),
          ],
          if ((request['note'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Note: ${(request['note'] ?? '').toString()}',
              style: const TextStyle(
                color: Color(0xFFB3B3BB),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          if (!reviewed && (request['status'] ?? '') == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving
                        ? null
                        : () => _reviewRequest(
                              request: request,
                              approve: false,
                            ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF8A80),
                      side: const BorderSide(color: Color(0xFFFF8A80)),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving
                        ? null
                        : () => _reviewRequest(
                              request: request,
                              approve: true,
                            ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF5F5F5),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text(
                      'Approve',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMySetupTab() {
    final setupHabits =
        _habits.where((habit) => _shouldShowInMySetup(habit)).toList();

    return RefreshIndicator(
      onRefresh: _loadHubData,
      color: const Color(0xFFF5F5F5),
      backgroundColor: const Color(0xFF17171A),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
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
                  'My verification setup',
                  subtitle:
                      'Configure verifier assignment, pinned locations, and focus app policy per habit.',
                ),
                if (setupHabits.isEmpty)
                  const Text(
                    'No configurable verification habits found.',
                    style: TextStyle(color: Color(0xFF9A9AA3)),
                  ),
                ...setupHabits.map(_buildMyHabitCard),
              ],
            ),
          ),
          if (_myPendingSubmissions.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
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
                    'My pending submissions',
                    subtitle:
                        'Requests I already sent and that still need review.',
                  ),
                  ..._myPendingSubmissions.map(_buildSubmissionCard),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInboxTab() {
    return RefreshIndicator(
      onRefresh: _loadHubData,
      color: const Color(0xFFF5F5F5),
      backgroundColor: const Color(0xFF17171A),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
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
                  'Needs my review',
                  subtitle:
                      'Approve or reject partner submissions assigned to me.',
                ),
                if (_inboxPending.isEmpty)
                  const Text(
                    'No verification requests need your review right now.',
                    style: TextStyle(color: Color(0xFF9A9AA3)),
                  ),
                ..._inboxPending.map((request) => _buildInboxCard(request)),
              ],
            ),
          ),
          if (_inboxReviewed.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
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
                    'Recently reviewed',
                    subtitle:
                        'The latest approval and rejection decisions you made.',
                  ),
                  ..._inboxReviewed.map(
                    (request) => _buildInboxCard(
                      request,
                      reviewed: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
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

    return Column(
      children: [
        _buildStatsRow(),
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF17171A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF232329)),
          ),
          child: SizedBox(
            height: 56,
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorPadding: EdgeInsets.zero,
              labelColor: Colors.black,
              unselectedLabelColor: const Color(0xFF9A9AA3),
              dividerColor: Colors.transparent,
              tabs: [
                Tab(
                  text:
                      'My setup (${_habits.where((h) => _shouldShowInMySetup(h)).length})',
                ),
                Tab(text: 'For others (${_inboxPending.length})'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildMySetupTab(),
              _buildInboxTab(),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0C),
        elevation: 0,
        title: const Text(
          'Verification',
          style: TextStyle(
            color: Color(0xFFF5F5F5),
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFF5F5F5)),
      ),
      body: _buildBody(),
    );
  }
}