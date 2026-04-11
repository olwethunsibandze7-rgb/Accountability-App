import 'package:achievr_app/Services/friends_service.dart';
import 'package:achievr_app/Services/shared_progress_service.dart';
import 'package:flutter/material.dart';

class SharedProgressScreen extends StatefulWidget {
  const SharedProgressScreen({super.key});

  @override
  State<SharedProgressScreen> createState() => _SharedProgressScreenState();
}

class _SharedProgressScreenState extends State<SharedProgressScreen> {
  final FriendsService _friendsService = FriendsService();
  final SharedProgressService _sharedProgressService = SharedProgressService();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _permissions = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _friendsService.fetchAcceptedFriendProfiles(),
        _sharedProgressService.fetchMySharingPermissions(),
      ]);

      if (!mounted) return;

      setState(() {
        _friends = List<Map<String, dynamic>>.from(results[0] as List);
        _permissions = List<Map<String, dynamic>>.from(results[1] as List);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Failed to load visibility settings.\n$e';
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic>? _permissionForViewer(String viewerUserId) {
    for (final permission in _permissions) {
      if (permission['viewer_user_id']?.toString() == viewerUserId) {
        return permission;
      }
    }
    return null;
  }

  Future<void> _togglePermission({
    required String viewerUserId,
    required bool canViewProgress,
    required bool canViewGoalTitles,
    required bool canViewHabitTitles,
  }) async {
    try {
      setState(() {
        _isSaving = true;
      });

      await _sharedProgressService.upsertSharingPermission(
        viewerUserId: viewerUserId,
        canViewProgress: canViewProgress,
        canViewGoalTitles: canViewGoalTitles,
        canViewHabitTitles: canViewHabitTitles,
      );

      await _loadData();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Visibility settings updated.')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update permission: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  int get _progressVisibleCount {
    int count = 0;
    for (final friend in _friends) {
      final viewerUserId = friend['other_user_id']?.toString() ?? '';
      final permission = _permissionForViewer(viewerUserId);
      if (permission?['can_view_progress'] == true) count++;
    }
    return count;
  }

  int get _goalTitlesVisibleCount {
    int count = 0;
    for (final friend in _friends) {
      final viewerUserId = friend['other_user_id']?.toString() ?? '';
      final permission = _permissionForViewer(viewerUserId);
      if (permission?['can_view_goal_titles'] == true) count++;
    }
    return count;
  }

  int get _habitTitlesVisibleCount {
    int count = 0;
    for (final friend in _friends) {
      final viewerUserId = friend['other_user_id']?.toString() ?? '';
      final permission = _permissionForViewer(viewerUserId);
      if (permission?['can_view_habit_titles'] == true) count++;
    }
    return count;
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
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCard() {
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
            'Visibility',
            style: TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Control what each friend can see. This is where you decide how much social pressure, transparency, and accountability you want.',
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
                  label: 'Friends',
                  value: '${_friends.length}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Progress Visible',
                  value: '$_progressVisibleCount',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Goal Titles Visible',
                  value: '$_goalTitlesVisibleCount',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVisibilitySummaryCard() {
    return Container(
      margin: const EdgeInsets.only(top: 18),
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
            'Current visibility baseline',
            subtitle: 'A quick read on how exposed your progress currently is.',
          ),
          Text(
            _friends.isEmpty
                ? 'You do not have any friends connected yet, so nothing is being shared.'
                : '$_progressVisibleCount of ${_friends.length} friend${_friends.length == 1 ? '' : 's'} can see your progress. '
                    '$_goalTitlesVisibleCount can see goal names, and $_habitTitlesVisibleCount can see habit names.',
            style: const TextStyle(
              color: Color(0xFFB3B3BB),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendPermissionCard(Map<String, dynamic> friend) {
    final otherProfile = friend['other_profile'] as Map<String, dynamic>?;
    final viewerUserId = friend['other_user_id'].toString();
    final username = (otherProfile?['username'] ?? 'Unknown').toString();
    final publicHandle = (otherProfile?['public_handle'] ?? '').toString();

    final permission = _permissionForViewer(viewerUserId);

    final canViewProgress = permission?['can_view_progress'] == true;
    final canViewGoalTitles = permission?['can_view_goal_titles'] == true;
    final canViewHabitTitles = permission?['can_view_habit_titles'] == true;

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
            username,
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            publicHandle.isNotEmpty ? '@$publicHandle' : viewerUserId,
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Can view progress',
              style: TextStyle(color: Color(0xFFF5F5F5)),
            ),
            subtitle: const Text(
              'Allows overall progress visibility.',
              style: TextStyle(color: Color(0xFF9A9AA3)),
            ),
            value: canViewProgress,
            activeThumbColor: Colors.blueAccent,
            onChanged: _isSaving
                ? null
                : (value) {
                    _togglePermission(
                      viewerUserId: viewerUserId,
                      canViewProgress: value,
                      canViewGoalTitles: canViewGoalTitles,
                      canViewHabitTitles: canViewHabitTitles,
                    );
                  },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Can view goal titles',
              style: TextStyle(color: Color(0xFFF5F5F5)),
            ),
            subtitle: const Text(
              'Shows actual goal names instead of hidden placeholders.',
              style: TextStyle(color: Color(0xFF9A9AA3)),
            ),
            value: canViewGoalTitles,
            activeThumbColor: Colors.blueAccent,
            onChanged: _isSaving
                ? null
                : (value) {
                    _togglePermission(
                      viewerUserId: viewerUserId,
                      canViewProgress: canViewProgress,
                      canViewGoalTitles: value,
                      canViewHabitTitles: canViewHabitTitles,
                    );
                  },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Can view habit titles',
              style: TextStyle(color: Color(0xFFF5F5F5)),
            ),
            subtitle: const Text(
              'Shows specific habit names instead of generic progress only.',
              style: TextStyle(color: Color(0xFF9A9AA3)),
            ),
            value: canViewHabitTitles,
            activeThumbColor: Colors.blueAccent,
            onChanged: _isSaving
                ? null
                : (value) {
                    _togglePermission(
                      viewerUserId: viewerUserId,
                      canViewProgress: canViewProgress,
                      canViewGoalTitles: canViewGoalTitles,
                      canViewHabitTitles: value,
                    );
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsSection() {
    return Container(
      margin: const EdgeInsets.only(top: 18),
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
            'Friend-by-friend controls',
            subtitle: 'Set visibility rules for each person individually.',
          ),
          if (_friends.isEmpty)
            const Text(
              'No friends found. Add people first to control what they can see.',
              style: TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 13,
              ),
            ),
          ..._friends.map(_buildFriendPermissionCard),
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

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFFF5F5F5),
      backgroundColor: const Color(0xFF17171A),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          _buildTopCard(),
          _buildVisibilitySummaryCard(),
          _buildPermissionsSection(),
        ],
      ),
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
          'Visibility',
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