import 'package:achievr_app/Services/friends_service.dart';
import 'package:achievr_app/Services/verification_service.dart';
import 'package:flutter/material.dart';

class VerificationSettingsScreen extends StatefulWidget {
  const VerificationSettingsScreen({super.key});

  @override
  State<VerificationSettingsScreen> createState() =>
      _VerificationSettingsScreenState();
}

class _VerificationSettingsScreenState
    extends State<VerificationSettingsScreen> {
  final VerificationService _verificationService = VerificationService();
  final FriendsService _friendsService = FriendsService();

  bool _isLoading = true;
  String? _error;

  List<Map<String, dynamic>> _habits = [];
  List<Map<String, dynamic>> _friends = [];

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
      final habits = await _verificationService.fetchMyActiveHabitsForVerification();
      final friends = await _friendsService.fetchAcceptedFriendProfiles();

      if (!mounted) return;

      setState(() {
        _habits = habits;
        _friends = friends;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Failed to load verification settings.\n$e';
        _isLoading = false;
      });
    }
  }

  String _friendNameFromUserId(String? userId) {
    if (userId == null) return 'No verifier';

    for (final friend in _friends) {
      final otherProfile = friend['other_profile'] as Map<String, dynamic>?;
      final otherUserId = friend['other_user_id']?.toString();

      if (otherUserId == userId) {
        return (otherProfile?['username'] ?? 'Unknown').toString();
      }
    }

    return 'Unknown';
  }

  Future<void> _changeVerificationType(
    String habitId,
    String newType,
  ) async {
    try {
      await _verificationService.updateHabitVerificationType(
        habitId: habitId,
        verificationType: newType,
      );

      if (newType == 'manual') {
        await _verificationService.removeVerifierFromHabit(habitId: habitId);
      }

      await _loadData();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification updated to $newType.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update verification: $e')),
      );
    }
  }

  Future<void> _pickVerifierForHabit(String habitId) async {
    if (_friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a friend first before assigning a verifier.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<String>(
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
                  'Choose Verifier',
                  style: TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                ..._friends.map((friend) {
                  final otherProfile =
                      friend['other_profile'] as Map<String, dynamic>?;
                  final otherUserId = friend['other_user_id'].toString();
                  final username = (otherProfile?['username'] ?? 'Unknown').toString();

                  return Container(
                    margin: const EdgeInsets.only(top: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101013),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF232329)),
                    ),
                    child: ListTile(
                      onTap: () => Navigator.pop(context, otherUserId),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF17171A),
                        child: Text(
                          username.isNotEmpty ? username[0].toUpperCase() : 'U',
                          style: const TextStyle(color: Color(0xFFF5F5F5)),
                        ),
                      ),
                      title: Text(
                        username,
                        style: const TextStyle(
                          color: Color(0xFFF5F5F5),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        otherUserId,
                        style: const TextStyle(
                          color: Color(0xFF7C7C84),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) return;

    try {
      await _verificationService.assignVerifierToHabit(
        habitId: habitId,
        verifierUserId: selected,
      );

      await _verificationService.updateHabitVerificationType(
        habitId: habitId,
        verificationType: 'partner',
      );

      await _loadData();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verifier assigned.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to assign verifier: $e')),
      );
    }
  }

  Widget _buildHabitCard(Map<String, dynamic> habit) {
    final goal = habit['goal'] as Map<String, dynamic>?;
    final verifier = habit['verifier'] as Map<String, dynamic>?;
    final verificationType = (habit['verification_type'] ?? 'manual').toString();
    final verifierUserId = verifier?['verifier_user_id']?.toString();

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
            (habit['title'] ?? 'Untitled Habit').toString(),
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Goal: ${(goal?['title'] ?? 'Unknown Goal').toString()}',
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: verificationType,
            dropdownColor: const Color(0xFF17171A),
            style: const TextStyle(color: Color(0xFFF5F5F5)),
            decoration: InputDecoration(
              labelText: 'Verification method',
              labelStyle: const TextStyle(color: Color(0xFF9A9AA3)),
              filled: true,
              fillColor: const Color(0xFF17171A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'manual', child: Text('Manual')),
              DropdownMenuItem(value: 'partner', child: Text('Partner')),
            ],
            onChanged: (value) {
              if (value == null) return;
              _changeVerificationType(habit['habit_id'].toString(), value);
            },
          ),
          const SizedBox(height: 12),
          if (verificationType == 'partner') ...[
            Text(
              'Assigned verifier: ${_friendNameFromUserId(verifierUserId)}',
              style: const TextStyle(
                color: Color(0xFFB3B3BB),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickVerifierForHabit(habit['habit_id'].toString()),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF3A3A42)),
                      foregroundColor: const Color(0xFFF5F5F5),
                    ),
                    child: const Text('Choose Verifier'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      try {
                        await _verificationService.removeVerifierFromHabit(
                          habitId: habit['habit_id'].toString(),
                        );
                        await _loadData();

                        if (!mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Verifier removed.')),
                        );
                      } catch (e) {
                        if (!mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to remove verifier: $e')),
                        );
                      }
                    },
                    child: const Text(
                      'Remove',
                      style: TextStyle(color: Color(0xFFFF8A80)),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Verification Settings',
                  style: TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _friends.isEmpty
                      ? 'You have no accepted friends yet. Manual verification still works, but partner verification needs at least one friend.'
                      : 'Choose how each habit gets verified, and assign a partner where needed.',
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
          if (_habits.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF17171A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF232329)),
              ),
              child: const Text(
                'No active habits found.',
                style: TextStyle(
                  color: Color(0xFF9A9AA3),
                  fontSize: 13,
                ),
              ),
            ),
          ..._habits.map(_buildHabitCard),
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