import 'dart:async';

import 'package:achievr_app/Services/friends_service.dart';
import 'package:flutter/material.dart';

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final FriendsService _friendsService = FriendsService();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounce;
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _results = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
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
        _results = [];
        _isLoading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await _friendsService.searchUsersByUsername(trimmed);

      if (!mounted) return;

      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Failed to search users.\n$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _sendRequest(String userId) async {
    try {
      await _friendsService.sendFriendRequest(addresseeUserId: userId);

      if (!mounted) return;

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

  Widget _buildResultCard(Map<String, dynamic> profile) {
    final username = (profile['username'] ?? 'Unknown').toString();
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
                  userId,
                  style: const TextStyle(
                    color: Color(0xFF7C7C84),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
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
        ],
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
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
                'Add Friend',
                style: TextStyle(
                  color: Color(0xFFF5F5F5),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Search by username and send a friend request to build your accountability circle.',
                style: TextStyle(
                  color: Color(0xFFB3B3BB),
                  height: 1.45,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search username',
                  hintStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF9A9AA3)),
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
        ),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFFF5F5F5)),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB3B3BB)),
            ),
          ),
        if (!_isLoading && _searchController.text.trim().isNotEmpty && _results.isEmpty && _error == null)
          Container(
            margin: const EdgeInsets.only(top: 18),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF17171A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF232329)),
            ),
            child: const Text(
              'No users found for that search.',
              style: TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 13,
              ),
            ),
          ),
        ..._results.map(_buildResultCard),
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
          'Add Friend',
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