import 'package:achievr_app/Services/friends_service.dart';
import 'package:achievr_app/Widgets/points_feedback.dart';
import 'package:flutter/material.dart';

class FriendProfileScreen extends StatefulWidget {
  final String userId;
  final bool isFriend;

  const FriendProfileScreen({
    super.key,
    required this.userId,
    required this.isFriend,
  });

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  final FriendsService _friendsService = FriendsService();

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profile = await _friendsService.fetchSocialProfileByUserId(
        widget.userId,
      );

      if (!mounted) return;

      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load profile.\n$e';
        _isLoading = false;
      });
    }
  }

  int _coerceInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  String get _username {
    final value = _profile?['username'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return 'Unknown';
  }

  String get _publicHandle {
    final value = _profile?['public_handle'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return '';
  }

  String get _title {
    final value = _profile?['current_title'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return 'Starter';
  }

  int get _level {
    final raw = _profile?['prestige_level'];
    final level = _coerceInt(raw);
    return level <= 0 ? 1 : level;
  }

  bool get _showScore {
    final visible = _profile?['accountability_score_visible'] == true;
    return visible || widget.isFriend;
  }

  Map<String, dynamic>? get _stats =>
      _profile?['stats'] as Map<String, dynamic>?;

  int get _xp => _coerceInt(_stats?['execution_points']);
  int get _currentStreak => _coerceInt(_stats?['current_streak']);
  int get _bestStreak => _coerceInt(_stats?['best_streak']);
  int get _totalCompleted => _coerceInt(_stats?['total_completed']);
  int get _totalFailed => _coerceInt(_stats?['total_failed']);
  int get _totalMissed => _coerceInt(_stats?['total_missed']);
  int get _cleanSessions => _coerceInt(_stats?['clean_sessions']);
  int get _badgeCount => _coerceInt(_profile?['badge_count']);
  List<Map<String, dynamic>> get _recentBadges =>
      List<Map<String, dynamic>>.from(_profile?['recent_badges'] ?? []);

  Widget _pill(String text, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: filled ? const Color(0xFFF5F5F5) : const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: filled ? const Color(0xFFF5F5F5) : const Color(0xFF232329),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: filled ? Colors.black : const Color(0xFFF5F5F5),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Container(
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
      ),
    );
  }

  Widget _badgeTile(Map<String, dynamic> badgeRow) {
    final badge = badgeRow['badge_definitions'] as Map<String, dynamic>?;
    final title = (badge?['title'] ?? 'Badge').toString();
    final rarity = (badge?['rarity'] ?? 'common').toString();

    final borderColor = rarity == 'rare'
        ? const Color(0xFFFFB74D)
        : rarity == 'uncommon'
            ? const Color(0xFF4FC3F7)
            : const Color(0xFF232329);

    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0B0C),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFF5F5F5)),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0B0C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0B0C),
          title: const Text('Profile'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFB3B3BB)),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0C),
        title: const Text('Profile'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        color: const Color(0xFFF5F5F5),
        backgroundColor: const Color(0xFF17171A),
        child: ListView(
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
                children: [
                  Container(
                    width: 76,
                    height: 76,
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
                          fontSize: 28,
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
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _publicHandle.isNotEmpty ? '@$_publicHandle' : _title,
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
                      _pill(_title, filled: true),
                      _pill('Lv $_level'),
                      if (_showScore) _pill('$_xp XP'),
                      _pill('Badges $_badgeCount'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _metric('Current Streak', _currentStreak.toString()),
                      const SizedBox(width: 10),
                      _metric('Best Streak', _bestStreak.toString()),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _metric('Done', _totalCompleted.toString()),
                      const SizedBox(width: 10),
                      _metric('Clean', _cleanSessions.toString()),
                    ],
                  ),
                  if (_showScore) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF101013),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF232329),
                              ),
                            ),
                            child: Column(
                              children: [
                                AnimatedPointsText(
                                  value: _xp,
                                  style: const TextStyle(
                                    color: Color(0xFFF5F5F5),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'XP',
                                  style: TextStyle(
                                    color: Color(0xFF9A9AA3),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _metric('Failed', _totalFailed.toString()),
                        const SizedBox(width: 10),
                        _metric('Missed', _totalMissed.toString()),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF101013),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF232329)),
                      ),
                      child: const Text(
                        'This user hides detailed score totals. Title, level, streak, and badge identity are still visible.',
                        style: TextStyle(
                          color: Color(0xFF9A9AA3),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
                  const Text(
                    'Recent badges',
                    style: TextStyle(
                      color: Color(0xFFF5F5F5),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Identity markers earned through consistency and verified performance.',
                    style: TextStyle(
                      color: Color(0xFF9A9AA3),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_recentBadges.isEmpty)
                    const Text(
                      'No badges unlocked yet.',
                      style: TextStyle(color: Color(0xFF9A9AA3)),
                    )
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _recentBadges.map(_badgeTile).toList(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}