import 'package:achievr_app/Services/friends_service.dart';
import 'package:achievr_app/Services/shared_progress_service.dart';
import 'package:flutter/material.dart';

class SharedProgressScreen extends StatefulWidget {
  const SharedProgressScreen({super.key});

  @override
  State<SharedProgressScreen> createState() => _SharedProgressScreenState();
}

class _SharedProgressScreenState extends State<SharedProgressScreen> {
  final SharedProgressService _sharedProgressService = SharedProgressService();
  final FriendsService _friendsService = FriendsService();

  bool _isLoading = true;
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
      final friends = await _friendsService.fetchAcceptedFriendProfiles();
      final permissions = await _sharedProgressService.fetchMySharingPermissions();

      if (!mounted) return;

      setState(() {
        _friends = friends;
        _permissions = permissions;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Failed to load shared progress settings.\n$e';
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic>? _permissionForViewer(String viewerUserId) {
    for (final permission in _permissions) {
      if (permission['viewer_user_id'].toString() == viewerUserId) {
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
      await _sharedProgressService.upsertSharingPermission(
        viewerUserId: viewerUserId,
        canViewProgress: canViewProgress,
        canViewGoalTitles: canViewGoalTitles,
        canViewHabitTitles: canViewHabitTitles,
      );

      await _loadData();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shared progress settings updated.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update permission: $e')),
      );
    }
  }

  Widget _buildFriendPermissionCard(Map<String, dynamic> friend) {
    final otherProfile = friend['other_profile'] as Map<String, dynamic>?;
    final viewerUserId = friend['other_user_id'].toString();
    final username = (otherProfile?['username'] ?? 'Unknown').toString();

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
            onChanged: (value) {
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
            onChanged: (value) {
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
              'Shows actual habit names instead of restricted visibility later.',
              style: TextStyle(color: Color(0xFF9A9AA3)),
            ),
            value: canViewHabitTitles,
            activeThumbColor: Colors.blueAccent,
            onChanged: (value) {
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
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF17171A),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF232329)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shared Progress',
                  style: TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Control what each friend can see about your progress, goals, and habits.',
                  style: TextStyle(
                    color: Color(0xFFB3B3BB),
                    height: 1.45,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_friends.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF17171A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF232329)),
              ),
              child: const Text(
                'No accepted friends yet. Add friends before configuring shared progress.',
                style: TextStyle(
                  color: Color(0xFF9A9AA3),
                  fontSize: 13,
                ),
              ),
            ),
          ..._friends.map(_buildFriendPermissionCard),
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
          'Shared Progress',
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