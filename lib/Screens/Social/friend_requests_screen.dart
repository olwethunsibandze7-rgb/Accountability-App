import 'package:achievr_app/Services/friends_service.dart';
import 'package:flutter/material.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen>
    with SingleTickerProviderStateMixin {
  final FriendsService _friendsService = FriendsService();

  late TabController _tabController;

  bool _isLoading = true;
  String? _error;

  List<Map<String, dynamic>> _received = [];
  List<Map<String, dynamic>> _sent = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final received = await _friendsService.fetchPendingReceivedProfiles();
      final sent = await _friendsService.fetchPendingSentProfiles();

      if (!mounted) return;

      setState(() {
        _received = received;
        _sent = sent;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Failed to load requests.\n$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _accept(String friendshipId) async {
    try {
      await _friendsService.acceptFriendRequest(friendshipId: friendshipId);
      await _loadRequests();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend request accepted.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept request: $e')),
      );
    }
  }

  Future<void> _decline(String friendshipId) async {
    try {
      await _friendsService.declineFriendRequest(friendshipId: friendshipId);
      await _loadRequests();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend request declined.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to decline request: $e')),
      );
    }
  }

  Widget _buildRequestCard(
    Map<String, dynamic> request, {
    required bool received,
  }) {
    final otherProfile = request['other_profile'] as Map<String, dynamic>?;
    final username = (otherProfile?['username'] ?? 'Unknown').toString();
    final otherUserId = request['other_user_id'].toString();

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
            received ? 'Incoming request' : 'Sent request',
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            username,
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 13,
              fontWeight: FontWeight.w600,
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
          const SizedBox(height: 12),
          if (received)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        _decline(request['friendship_id'].toString()),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF3A3A42)),
                      foregroundColor: const Color(0xFFF5F5F5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        _accept(request['friendship_id'].toString()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF5F5F5),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Accept',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            )
          else
            const Text(
              'Awaiting response.',
              style: TextStyle(
                color: Color(0xFFB3B3BB),
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabContent(
    List<Map<String, dynamic>> items, {
    required bool received,
  }) {
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF17171A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF232329)),
            ),
            child: Text(
              received
                  ? 'No incoming requests right now.'
                  : 'No pending requests sent right now.',
              style: const TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: items
          .map((item) => _buildRequestCard(item, received: received))
          .toList(),
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
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          decoration: BoxDecoration(
            color: const Color(0xFF17171A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF232329)),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: const Color(0xFF101013),
              borderRadius: BorderRadius.circular(12),
            ),
            labelColor: const Color(0xFFF5F5F5),
            unselectedLabelColor: const Color(0xFF7C7C84),
            dividerColor: Colors.transparent,
            tabs: [
              Tab(text: 'Received (${_received.length})'),
              Tab(text: 'Sent (${_sent.length})'),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadRequests,
            color: const Color(0xFFF5F5F5),
            backgroundColor: const Color(0xFF17171A),
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTabContent(_received, received: true),
                _buildTabContent(_sent, received: false),
              ],
            ),
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
          'Friend Requests',
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