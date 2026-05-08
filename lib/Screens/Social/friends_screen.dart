import 'dart:async';

import 'package:achievr_app/Screens/Social/friend_profile_screen.dart';
import 'package:achievr_app/Services/friends_service.dart';
import 'package:flutter/material.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final FriendsService _friendsService = FriendsService();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounce;

  bool _isLoadingFriends = true;
  bool _isSearching = false;
  bool _isRefreshing = false;
  String? _error;

  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _isLoadingFriends = true;
      _error = null;
    });

    try {
      final friends = await _friendsService.fetchAcceptedFriendProfiles();

      if (!mounted) return;

      setState(() {
        _friends = friends;
        _isLoadingFriends = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Failed to load friends.\n$e';
        _isLoadingFriends = false;
      });
    }
  }

  Future<void> _refreshEverything() async {
    setState(() {
      _isRefreshing = true;
      _error = null;
    });

    try {
      await _loadFriends();

      final query = _searchController.text.trim();
      if (query.isNotEmpty) {
        await _runSearch(query);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(value);
    });
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final results = await _friendsService.searchUsersByUsername(trimmed);

      final friendUserIds = _friends
          .map((friend) => friend['other_user_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final filtered = results.where((profile) {
        final id = profile['id']?.toString() ?? '';
        return !friendUserIds.contains(id);
      }).toList();

      if (!mounted) return;

      setState(() {
        _searchResults = filtered;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Failed to search users.\n$e';
        _isSearching = false;
      });
    }
  }

  Future<void> _sendRequest(String userId) async {
    try {
      await _friendsService.sendFriendRequest(addresseeUserId: userId);

      if (!mounted) return;

      setState(() {
        _searchResults = _searchResults
            .where((profile) => profile['id']?.toString() != userId)
            .toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend request sent.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _removeFriend(Map<String, dynamic> friend) async {
    final friendshipId = friend['friendship_id']?.toString();
    if (friendshipId == null || friendshipId.isEmpty) return;

    final otherProfile = friend['other_profile'] as Map<String, dynamic>?;
    final username = (otherProfile?['username'] ?? 'this friend').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17171A),
          title: const Text(
            'Remove friend',
            style: TextStyle(color: Color(0xFFF5F5F5)),
          ),
          content: Text(
            'Remove $username from your accountability circle?',
            style: const TextStyle(color: Color(0xFFB3B3BB)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5F5F5),
                foregroundColor: Colors.black,
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _friendsService.removeFriendship(friendshipId: friendshipId);
      await _loadFriends();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend removed.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove friend: $e')),
      );
    }
  }

  int _coerceInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  String _profileTitle(Map<String, dynamic>? profile) {
    final title = profile?['current_title'];
    if (title is String && title.trim().isNotEmpty) {
      return title.trim();
    }
    return 'Starter';
  }

  int _profileLevel(Map<String, dynamic>? profile) {
    final level = _coerceInt(profile?['prestige_level']);
    return level <= 0 ? 1 : level;
  }

  int _profileXp(Map<String, dynamic>? profile) {
    final stats = profile?['stats'] as Map<String, dynamic>?;
    return _coerceInt(stats?['execution_points']);
  }

  int _profileCurrentStreak(Map<String, dynamic>? profile) {
    final stats = profile?['stats'] as Map<String, dynamic>?;
    return _coerceInt(stats?['current_streak']);
  }

  bool _scoreVisible(Map<String, dynamic>? profile) {
    return profile?['accountability_score_visible'] == true;
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
            'Friends',
            style: TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Search people, preview their accountability identity, and build your circle without losing context.',
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
                  label: 'Search Results',
                  value: '${_searchResults.length}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search username or handle',
              hintStyle: const TextStyle(color: Colors.white70),
              prefixIcon: const Icon(
                Icons.search,
                color: Color(0xFF9A9AA3),
              ),
              suffixIcon: _searchController.text.trim().isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _searchController.clear();
                        _runSearch('');
                      },
                      icon: const Icon(
                        Icons.close,
                        color: Color(0xFF9A9AA3),
                      ),
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF101013),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityLine(Map<String, dynamic> profile, {required bool isFriend}) {
    final title = _profileTitle(profile);
    final level = _profileLevel(profile);
    final xp = _profileXp(profile);
    final streak = _profileCurrentStreak(profile);
    final showScore = _scoreVisible(profile) || isFriend;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF4FC3F7),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          showScore
              ? 'Lv $level • $xp XP • Streak $streak'
              : 'Lv $level • Streak $streak',
          style: const TextStyle(
            color: Color(0xFF9A9AA3),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildFriendCard(Map<String, dynamic> friend) {
    final otherProfile = friend['other_profile'] as Map<String, dynamic>?;
    final username = (otherProfile?['username'] ?? 'Unknown').toString();
    final publicHandle = (otherProfile?['public_handle'] ?? '').toString();
    final otherUserId = friend['other_user_id']?.toString() ?? '';

    return GestureDetector(
      onTap: otherProfile == null
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FriendProfileScreen(
                    userId: otherUserId,
                    isFriend: true,
                  ),
                ),
              );
            },
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF101013),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF232329)),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF17171A),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF232329)),
              ),
              child: Center(
                child: Text(
                  username.isNotEmpty ? username[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    style: const TextStyle(
                      color: Color(0xFFF5F5F5),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    publicHandle.isNotEmpty ? '@$publicHandle' : otherUserId,
                    style: const TextStyle(
                      color: Color(0xFF9A9AA3),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (otherProfile != null)
                    _buildIdentityLine(otherProfile, isFriend: true),
                ],
              ),
            ),
            Column(
              children: [
                OutlinedButton(
                  onPressed: () => _removeFriend(friend),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF3A3A42)),
                    foregroundColor: const Color(0xFFF5F5F5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Remove'),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tap to view',
                  style: TextStyle(
                    color: Color(0xFF7C7C84),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultCard(Map<String, dynamic> profile) {
    final username = (profile['username'] ?? 'Unknown').toString();
    final publicHandle = (profile['public_handle'] ?? '').toString();
    final userId = profile['id'].toString();

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
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FriendProfileScreen(
                    userId: userId,
                    isFriend: false,
                  ),
                ),
              );
            },
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF17171A),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF232329)),
              ),
              child: Center(
                child: Text(
                  username.isNotEmpty ? username[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FriendProfileScreen(
                      userId: userId,
                      isFriend: false,
                    ),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    style: const TextStyle(
                      color: Color(0xFFF5F5F5),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    publicHandle.isNotEmpty ? '@$publicHandle' : userId,
                    style: const TextStyle(
                      color: Color(0xFF9A9AA3),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildIdentityLine(profile, isFriend: false),
                ],
              ),
            ),
          ),
          Column(
            children: [
              ElevatedButton(
                onPressed: () => _sendRequest(userId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5F5F5),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Add',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap to view',
                style: TextStyle(
                  color: Color(0xFF7C7C84),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsSection() {
    if (_isLoadingFriends) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF17171A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF232329)),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFFF5F5F5)),
        ),
      );
    }

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
            'Your circle',
            subtitle: 'Accepted accountability partners with identity preview.',
          ),
          if (_friends.isEmpty)
            const Text(
              'You have no friends added yet.',
              style: TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 13,
              ),
            ),
          ..._friends.map(_buildFriendCard),
        ],
      ),
    );
  }

  Widget _buildSearchSection() {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      return const SizedBox.shrink();
    }

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
            'Search results',
            subtitle:
                'Preview title, level, and accountability identity before adding.',
          ),
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFF5F5F5)),
              ),
            ),
          if (!_isSearching && _searchResults.isEmpty)
            const Text(
              'No users found for that search.',
              style: TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 13,
              ),
            ),
          if (!_isSearching) ..._searchResults.map(_buildSearchResultCard),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null && _friends.isEmpty && !_isLoadingFriends) {
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
      onRefresh: _refreshEverything,
      color: const Color(0xFFF5F5F5),
      backgroundColor: const Color(0xFF17171A),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          _buildTopCard(),
          const SizedBox(height: 18),
          _buildFriendsSection(),
          _buildSearchSection(),
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.only(top: 18),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFF5F5F5)),
              ),
            ),
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
          'Friends',
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