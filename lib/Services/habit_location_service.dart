import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HabitLocationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Duration _locationLockDuration = Duration(days: 14);

  String get _userId {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('No authenticated user found.');
    }
    return user.id;
  }

  bool habitRequiresLocation(String verificationType) {
    final normalized = verificationType.trim();
    return normalized == 'location' ||
        normalized == 'location_partner' ||
        normalized == 'location_focus' ||
        normalized == 'location_focus_partner';
  }

  Future<Map<String, dynamic>?> fetchHabitLocationConfig({
    required String habitId,
  }) async {
    final response = await _supabase
        .from('habit_location_configs')
        .select('''
          habit_location_config_id,
          habit_id,
          user_id,
          label,
          latitude,
          longitude,
          radius_meters,
          active,
          created_at,
          updated_at
        ''')
        .eq('habit_id', habitId)
        .eq('active', true)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<void> upsertHabitLocationConfig({
    required String habitId,
    required String label,
    required double latitude,
    required double longitude,
    required int radiusMeters,
  }) async {
    final userId = _userId;

    if (label.trim().isEmpty) {
      throw Exception('Location label is required.');
    }

    if (radiusMeters < 25 || radiusMeters > 5000) {
      throw Exception('Radius must be between 25 and 5000 meters.');
    }

    final existing = await fetchHabitLocationConfig(habitId: habitId);

    if (existing == null) {
      await _supabase.from('habit_location_configs').insert({
        'habit_id': habitId,
        'user_id': userId,
        'label': label.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'radius_meters': radiusMeters,
        'active': true,
      });
      return;
    }

    await _assertLocationEditAllowed(existing);

    await _supabase
        .from('habit_location_configs')
        .update({
          'label': label.trim(),
          'latitude': latitude,
          'longitude': longitude,
          'radius_meters': radiusMeters,
          'active': true,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('habit_location_config_id', existing['habit_location_config_id']);
  }

  Future<void> removeHabitLocationConfig({
    required String habitId,
  }) async {
    final existing = await fetchHabitLocationConfig(habitId: habitId);
    if (existing == null) return;

    await _assertLocationEditAllowed(existing);

    await _supabase
        .from('habit_location_configs')
        .delete()
        .eq('habit_id', habitId);
  }

  Future<Map<String, dynamic>> requireHabitLocationConfig({
    required String habitId,
  }) async {
    final config = await fetchHabitLocationConfig(habitId: habitId);

    if (config == null) {
      throw Exception(
        'This habit requires a pinned verification location before it can be completed.',
      );
    }

    return config;
  }

  Future<Map<String, dynamic>> checkLocationEligibility({
    required String habitId,
    required double currentLatitude,
    required double currentLongitude,
  }) async {
    final config = await requireHabitLocationConfig(habitId: habitId);

    final targetLatitude = _coerceDouble(config['latitude']);
    final targetLongitude = _coerceDouble(config['longitude']);
    final radiusMeters = _coerceDouble(config['radius_meters']);

    if (targetLatitude == null ||
        targetLongitude == null ||
        radiusMeters == null) {
      throw Exception('Pinned location config is incomplete.');
    }

    final distanceMeters = Geolocator.distanceBetween(
      currentLatitude,
      currentLongitude,
      targetLatitude,
      targetLongitude,
    );

    final insideRadius = distanceMeters <= radiusMeters;

    return {
      'allowed': insideRadius,
      'distance_meters': distanceMeters,
      'radius_meters': radiusMeters,
      'label': (config['label'] ?? 'Pinned location').toString(),
      'latitude': targetLatitude,
      'longitude': targetLongitude,
    };
  }

  Future<void> assertLocationEligible({
    required String habitId,
    required double currentLatitude,
    required double currentLongitude,
  }) async {
    final result = await checkLocationEligibility(
      habitId: habitId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
    );

    final allowed = result['allowed'] == true;
    if (allowed) return;

    final label = (result['label'] ?? 'Pinned location').toString();
    final distanceMeters = _coerceDouble(result['distance_meters']) ?? 0;
    final radiusMeters = _coerceDouble(result['radius_meters']) ?? 0;

    throw Exception(
      'You must be within ${radiusMeters.toStringAsFixed(0)}m of $label. '
      'Current distance: ${distanceMeters.toStringAsFixed(1)}m.',
    );
  }

  String? locationLockMessage(Map<String, dynamic>? config) {
    if (config == null) return null;

    final lockedUntil = _lockedUntil(config);
    if (lockedUntil == null) return null;

    final now = DateTime.now();
    if (!lockedUntil.isAfter(now)) return null;

    final remaining = lockedUntil.difference(now).inDays;
    final daysText = remaining <= 0 ? 'less than 1 day' : '$remaining day(s)';

    return 'Pinned location is locked for 14 days. Remaining lock: $daysText.';
  }

  Future<void> _assertLocationEditAllowed(Map<String, dynamic> existing) async {
    final lockedUntil = _lockedUntil(existing);
    if (lockedUntil == null) return;

    final now = DateTime.now();
    if (!lockedUntil.isAfter(now)) return;

    final remainingDays = lockedUntil.difference(now).inDays;
    final daysText =
        remainingDays <= 0 ? 'less than 1 day' : '$remainingDays day(s)';

    throw Exception(
      'This pinned location is locked. Remaining lock: $daysText.',
    );
  }

  DateTime? _lockedUntil(Map<String, dynamic> config) {
    final anchor = _coerceDateTime(config['updated_at']) ??
        _coerceDateTime(config['created_at']);
    if (anchor == null) return null;
    return anchor.add(_locationLockDuration);
  }

  DateTime? _coerceDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  double? _coerceDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}