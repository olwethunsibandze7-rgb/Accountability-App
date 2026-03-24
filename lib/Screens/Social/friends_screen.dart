import 'package:achievr_app/Services/friends_service.dart';
import 'package:flutter/material.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final FriendsService _friendsService = FriendsService();

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _friends = [];

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final friends = await _friendsService.fetchAcceptedFriendProfiles();

      if (!mounted) return;

      setState(() {
        _friends = friends;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Failed to load friends.\n$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _removeFriendship(String friendshipId) async {
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

  Widget _buildFriendCard(Map<String, dynamic> friendship) {
    final otherProfile = friendship['other_profile'] as Map<String, dynamic>?;
    final otherUserId = friendship['other_user_id'].toString();
    final username = (otherProfile?['username'] ?? 'Unknown').toString();

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
          Container(
            width: 42,
            height: 42,
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
                  otherUserId,
                  style: const TextStyle(
                    color: Color(0xFF7C7C84),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _removeFriendship(friendship['friendship_id'].toString()),
            child: const Text(
              'Remove',
              style: TextStyle(color: Color(0xFFFF8A80)),
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

    return RefreshIndicator(
      onRefresh: _loadFriends,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Friends',
                  style: TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _friends.isEmpty
                      ? 'You do not have any accepted friends yet.'
                      : 'You currently have ${_friends.length} accepted friend connection${_friends.length == 1 ? '' : 's'}.',
                  style: const TextStyle(
                    color: Color(0xFFB3B3BB),
                    height: 1.45,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Accepted connections',
            style: TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_friends.isEmpty)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF17171A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF232329)),
              ),
              child: const Text(
                'No friends yet. Start by sending or accepting a request.',
                style: TextStyle(
                  color: Color(0xFF9A9AA3),
                  fontSize: 13,
                ),
              ),
            ),
          ..._friends.map(_buildFriendCard),
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