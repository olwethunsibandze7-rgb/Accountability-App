import 'package:supabase_flutter/supabase_flutter.dart';

class FriendsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String get _userId {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('No authenticated user found.');
    }
    return user.id;
  }

  int _coerceInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  Future<Map<String, dynamic>?> fetchProfileBasic(String userId) async {
    final response = await _supabase
        .from('profiles')
        .select('id, username, public_handle')
        .eq('id', userId)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>?> fetchSocialProfileByUserId(String userId) async {
    final profileRow = await _supabase
        .from('profiles')
        .select('''
          id,
          username,
          public_handle,
          current_title,
          prestige_level,
          accountability_score_visible
        ''')
        .eq('id', userId)
        .maybeSingle();

    if (profileRow == null) return null;

    final statsRow = await _supabase
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
        .eq('user_id', userId)
        .maybeSingle();

    final recentBadges = await _supabase
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
        .eq('user_id', userId)
        .order('awarded_at', ascending: false)
        .limit(6);

    final allBadges = await _supabase
        .from('user_badges')
        .select('user_badge_id')
        .eq('user_id', userId);

    return {
      ...Map<String, dynamic>.from(profileRow),
      'stats': statsRow == null ? null : Map<String, dynamic>.from(statsRow),
      'recent_badges': List<Map<String, dynamic>>.from(recentBadges),
      'badge_count': List<Map<String, dynamic>>.from(allBadges).length,
    };
  }

  Future<Map<String, Map<String, dynamic>>> fetchSocialProfilesByUserIds(
    List<String> userIds,
  ) async {
    final ids = userIds.where((e) => e.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};

    final profilesFuture = _supabase
        .from('profiles')
        .select('''
          id,
          username,
          public_handle,
          current_title,
          prestige_level,
          accountability_score_visible
        ''')
        .inFilter('id', ids);

    final statsFuture = _supabase
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
        .inFilter('user_id', ids);

    final badgesFuture = _supabase
        .from('user_badges')
        .select('''
          user_id,
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
        .inFilter('user_id', ids)
        .order('awarded_at', ascending: false);

    final results = await Future.wait([
      profilesFuture,
      statsFuture,
      badgesFuture,
    ]);

    final profileRows = List<Map<String, dynamic>>.from(results[0] as List);
    final statsRows = List<Map<String, dynamic>>.from(results[1] as List);
    final badgeRows = List<Map<String, dynamic>>.from(results[2] as List);

    final statsMap = <String, Map<String, dynamic>>{
      for (final row in statsRows) row['user_id'].toString(): row,
    };

    final badgeMap = <String, List<Map<String, dynamic>>>{};
    final badgeCountMap = <String, int>{};

    for (final row in badgeRows) {
      final userId = row['user_id']?.toString();
      if (userId == null || userId.isEmpty) continue;

      badgeMap.putIfAbsent(userId, () => []);
      if (badgeMap[userId]!.length < 6) {
        badgeMap[userId]!.add(row);
      }
      badgeCountMap[userId] = (badgeCountMap[userId] ?? 0) + 1;
    }

    final combined = <String, Map<String, dynamic>>{};
    for (final profile in profileRows) {
      final id = profile['id'].toString();
      combined[id] = {
        ...profile,
        'stats': statsMap[id],
        'recent_badges': badgeMap[id] ?? <Map<String, dynamic>>[],
        'badge_count': _coerceInt(badgeCountMap[id]),
      };
    }

    return combined;
  }

  Future<List<Map<String, dynamic>>> searchUsersByUsername(String query) async {
    final trimmed = query.trim();

    if (trimmed.isEmpty) return [];

    final response = await _supabase.rpc(
      'search_profiles',
      params: {'search_text': trimmed},
    );

    final base = List<Map<String, dynamic>>.from(response);
    final ids = base
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    final enriched = await fetchSocialProfilesByUserIds(ids);

    return base.map((row) {
      final id = row['id']?.toString() ?? '';
      return {
        ...row,
        ...(enriched[id] ?? <String, dynamic>{}),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> fetchAllFriendships() async {
    final userId = _userId;

    final response = await _supabase
        .from('friendships')
        .select('''
          friendship_id,
          requester_id,
          addressee_id,
          status,
          created_at,
          responded_at
        ''')
        .or('requester_id.eq.$userId,addressee_id.eq.$userId')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> fetchPendingRequestsReceived() async {
    final userId = _userId;

    final response = await _supabase
        .from('friendships')
        .select('''
          friendship_id,
          requester_id,
          addressee_id,
          status,
          created_at,
          responded_at
        ''')
        .eq('addressee_id', userId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> fetchPendingRequestsSent() async {
    final userId = _userId;

    final response = await _supabase
        .from('friendships')
        .select('''
          friendship_id,
          requester_id,
          addressee_id,
          status,
          created_at,
          responded_at
        ''')
        .eq('requester_id', userId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> fetchAcceptedFriends() async {
    final userId = _userId;

    final response = await _supabase
        .from('friendships')
        .select('''
          friendship_id,
          requester_id,
          addressee_id,
          status,
          created_at,
          responded_at
        ''')
        .eq('status', 'accepted')
        .or('requester_id.eq.$userId,addressee_id.eq.$userId')
        .order('responded_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> enrichFriendshipWithOtherProfile(
    Map<String, dynamic> friendship,
  ) async {
    final userId = _userId;
    final requesterId = friendship['requester_id'].toString();
    final addresseeId = friendship['addressee_id'].toString();

    final otherUserId = requesterId == userId ? addresseeId : requesterId;
    final otherProfile = await fetchSocialProfileByUserId(otherUserId);

    return {
      ...friendship,
      'other_user_id': otherUserId,
      'other_profile': otherProfile,
    };
  }

  Future<List<Map<String, dynamic>>> enrichFriendships(
    List<Map<String, dynamic>> friendships,
  ) async {
    final userId = _userId;
    final otherIds = friendships.map((friendship) {
      final requesterId = friendship['requester_id'].toString();
      final addresseeId = friendship['addressee_id'].toString();
      return requesterId == userId ? addresseeId : requesterId;
    }).toList();

    final socialProfiles = await fetchSocialProfilesByUserIds(otherIds);

    return friendships.map((friendship) {
      final requesterId = friendship['requester_id'].toString();
      final addresseeId = friendship['addressee_id'].toString();
      final otherUserId = requesterId == userId ? addresseeId : requesterId;

      return {
        ...friendship,
        'other_user_id': otherUserId,
        'other_profile': socialProfiles[otherUserId],
      };
    }).toList();
  }

  Future<void> sendFriendRequest({
    required String addresseeUserId,
  }) async {
    final userId = _userId;

    if (addresseeUserId == userId) {
      throw Exception('You cannot add yourself as a friend.');
    }

    final existing = await _supabase
        .from('friendships')
        .select('friendship_id, requester_id, addressee_id, status')
        .or(
          'and(requester_id.eq.$userId,addressee_id.eq.$addresseeUserId),'
          'and(requester_id.eq.$addresseeUserId,addressee_id.eq.$userId)',
        )
        .maybeSingle();

    if (existing != null) {
      throw Exception(
        'A friendship or request already exists between these users.',
      );
    }

    await _supabase.from('friendships').insert({
      'requester_id': userId,
      'addressee_id': addresseeUserId,
      'status': 'pending',
    });
  }

  Future<void> acceptFriendRequest({
    required String friendshipId,
  }) async {
    await _supabase
        .from('friendships')
        .update({
          'status': 'accepted',
          'responded_at': DateTime.now().toIso8601String(),
        })
        .eq('friendship_id', friendshipId);
  }

  Future<void> declineFriendRequest({
    required String friendshipId,
  }) async {
    await _supabase
        .from('friendships')
        .update({
          'status': 'declined',
          'responded_at': DateTime.now().toIso8601String(),
        })
        .eq('friendship_id', friendshipId);
  }

  Future<void> removeFriendship({
    required String friendshipId,
  }) async {
    await _supabase
        .from('friendships')
        .delete()
        .eq('friendship_id', friendshipId);
  }

  Future<List<Map<String, dynamic>>> fetchAcceptedFriendProfiles() async {
    final friendships = await fetchAcceptedFriends();
    return enrichFriendships(friendships);
  }

  Future<List<Map<String, dynamic>>> fetchPendingReceivedProfiles() async {
    final requests = await fetchPendingRequestsReceived();
    return enrichFriendships(requests);
  }

  Future<List<Map<String, dynamic>>> fetchPendingSentProfiles() async {
    final requests = await fetchPendingRequestsSent();
    return enrichFriendships(requests);
  }

  Future<List<String>> fetchAcceptedFriendUserIds() async {
    final userId = _userId;
    final friendships = await fetchAcceptedFriends();

    return friendships.map((friendship) {
      final requesterId = friendship['requester_id'].toString();
      final addresseeId = friendship['addressee_id'].toString();
      return requesterId == userId ? addresseeId : requesterId;
    }).toList();
  }
}