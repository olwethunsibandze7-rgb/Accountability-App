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

  Future<Map<String, dynamic>?> fetchProfileBasic(String userId) async {
    final response = await _supabase
        .from('profiles')
        .select('id, username')
        .eq('id', userId)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<List<Map<String, dynamic>>> searchUsersByUsername(String query) async {
    final userId = _userId;
    final trimmed = query.trim();

    if (trimmed.isEmpty) return [];

    final response = await _supabase
        .from('profiles')
        .select('id, username')
        .ilike('username', '%$trimmed%')
        .neq('id', userId)
        .limit(20);

    return List<Map<String, dynamic>>.from(response);
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
    final otherProfile = await fetchProfileBasic(otherUserId);

    return {
      ...friendship,
      'other_user_id': otherUserId,
      'other_profile': otherProfile,
    };
  }

  Future<List<Map<String, dynamic>>> enrichFriendships(
    List<Map<String, dynamic>> friendships,
  ) async {
    final results = <Map<String, dynamic>>[];

    for (final friendship in friendships) {
      results.add(await enrichFriendshipWithOtherProfile(friendship));
    }

    return results;
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
    await _supabase.from('friendships').delete().eq('friendship_id', friendshipId);
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