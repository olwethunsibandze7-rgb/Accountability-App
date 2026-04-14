// ignore_for_file: use_build_context_synchronously

import 'package:achievr_app/Services/habit_location_service.dart';
import 'package:achievr_app/Services/location_runtime_service.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class SetHabitLocationScreen extends StatefulWidget {
  final String habitId;
  final String habitTitle;
  final String verificationType;

  const SetHabitLocationScreen({
    super.key,
    required this.habitId,
    required this.habitTitle,
    required this.verificationType,
  });

  @override
  State<SetHabitLocationScreen> createState() => _SetHabitLocationScreenState();
}

class _SetHabitLocationScreenState extends State<SetHabitLocationScreen> {
  final HabitLocationService _habitLocationService = HabitLocationService();
  final LocationRuntimeService _locationRuntimeService =
      LocationRuntimeService();

  final TextEditingController _labelController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _isFetchingCurrentLocation = false;

  String? _error;

  double? _latitude;
  double? _longitude;
  double? _accuracy;
  int _radiusMeters = 120;

  Map<String, dynamic>? _existingConfig;

  static const List<int> _radiusOptions = [50, 75, 100, 120, 150, 200, 250, 500];

  @override
  void initState() {
    super.initState();
    _loadExistingConfig();
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  bool get _requiresLocation {
    return widget.verificationType == 'location' ||
        widget.verificationType == 'location_partner' ||
        widget.verificationType == 'location_focus' ||
        widget.verificationType == 'location_focus_partner';
  }

  String? get _lockMessage =>
      _habitLocationService.locationLockMessage(_existingConfig);

  bool get _isLocked => _lockMessage != null;

  Future<void> _loadExistingConfig() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final config = await _habitLocationService.fetchHabitLocationConfig(
        habitId: widget.habitId,
      );

      if (!mounted) return;

      if (config != null) {
        _labelController.text = (config['label'] ?? '').toString();

        final lat = _coerceDouble(config['latitude']);
        final lng = _coerceDouble(config['longitude']);
        final radius = _coerceInt(config['radius_meters']);

        setState(() {
          _existingConfig = config;
          _latitude = lat;
          _longitude = lng;
          _radiusMeters = radius ?? 120;
          _isLoading = false;
        });
      } else {
        setState(() {
          _existingConfig = null;
          _labelController.text = _defaultLabelForHabit();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Failed to load pinned location.\n$e';
        _isLoading = false;
      });
    }
  }

  String _defaultLabelForHabit() {
    final lower = widget.habitTitle.toLowerCase();

    if (lower.contains('gym')) return 'My Gym';
    if (lower.contains('library')) return 'Library';
    if (lower.contains('church')) return 'Church';
    if (lower.contains('mosque')) return 'Mosque';
    if (lower.contains('school')) return 'School';
    if (lower.contains('campus')) return 'Campus';
    if (lower.contains('office')) return 'Office';

    return widget.habitTitle;
  }

  Future<void> _pickCurrentLocation() async {
    if (_isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_lockMessage!)),
      );
      return;
    }

    try {
      setState(() {
        _isFetchingCurrentLocation = true;
        _error = null;
      });

      final enabled = await _locationRuntimeService.isServiceEnabled();
      if (!enabled) {
        throw Exception('Location services are disabled.');
      }

      var permission = await _locationRuntimeService.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _locationRuntimeService.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied forever. Open app settings.');
      }

      final position = await _locationRuntimeService.getCurrentPosition();

      if (!mounted) return;

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _accuracy = position.accuracy;
        _isFetchingCurrentLocation = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current location captured.')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isFetchingCurrentLocation = false;
        _error = 'Could not get current location.\n$e';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not get current location: $e')),
      );
    }
  }

  Future<bool> _confirmFirstPin() async {
    if (_existingConfig != null) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17171A),
          title: const Text(
            'Confirm training location',
            style: TextStyle(color: Color(0xFFF5F5F5)),
          ),
          content: const Text(
            'Make sure you are currently at the real training location for this habit. Once pinned, this location cannot be changed or removed for 14 days.',
            style: TextStyle(
              color: Color(0xFFB3B3BB),
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Pin location',
                style: TextStyle(color: Color(0xFFF5F5F5)),
              ),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<void> _save() async {
    if (_isLocked) {
      setState(() {
        _error = _lockMessage;
      });
      return;
    }

    final label = _labelController.text.trim();

    if (label.isEmpty) {
      setState(() {
        _error = 'Please enter a label for this place.';
      });
      return;
    }

    if (_latitude == null || _longitude == null) {
      setState(() {
        _error = 'Please capture a location before saving.';
      });
      return;
    }

    final confirmed = await _confirmFirstPin();
    if (!confirmed) return;

    try {
      setState(() {
        _isSaving = true;
        _error = null;
      });

      await _habitLocationService.upsertHabitLocationConfig(
        habitId: widget.habitId,
        label: label,
        latitude: _latitude!,
        longitude: _longitude!,
        radiusMeters: _radiusMeters,
      );

      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pinned location saved.')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _error = 'Failed to save pinned location.\n$e';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save location: $e')),
      );
    }
  }

  Future<void> _remove() async {
    if (_isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_lockMessage!)),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17171A),
          title: const Text(
            'Remove pinned location?',
            style: TextStyle(color: Color(0xFFF5F5F5)),
          ),
          content: const Text(
            'This habit will no longer have a verification location configured.',
            style: TextStyle(color: Color(0xFFB3B3BB)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Remove',
                style: TextStyle(color: Color(0xFFFF8A80)),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      setState(() {
        _isDeleting = true;
        _error = null;
      });

      await _habitLocationService.removeHabitLocationConfig(
        habitId: widget.habitId,
      );

      if (!mounted) return;

      setState(() {
        _isDeleting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pinned location removed.')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isDeleting = false;
        _error = 'Failed to remove pinned location.\n$e';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove location: $e')),
      );
    }
  }

  int? _coerceInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString());
  }

  double? _coerceDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Widget _buildInfoCard() {
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
          Text(
            widget.habitTitle,
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _requiresLocation
                ? 'This habit uses location-based verification. Pin the place where this task is valid, like your gym, library, or office.'
                : 'This habit does not currently require location verification.',
            style: const TextStyle(
              color: Color(0xFFB3B3BB),
              height: 1.4,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF101013),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF232329)),
            ),
            child: Text(
              _lockMessage ??
                  'Make sure you are currently at the real training location. Once pinned, this location cannot be changed or removed for 14 days.',
              style: const TextStyle(
                color: Color(0xFFFFD166),
                height: 1.35,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
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
          const Text(
            'Pinned location',
            style: TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _labelController,
            enabled: !_isLocked,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Place label',
              hintText: 'Example: My Gym',
              labelStyle: const TextStyle(color: Color(0xFFB3B3BB)),
              hintStyle: const TextStyle(color: Color(0xFF6F6F76)),
              filled: true,
              fillColor: const Color(0xFF101013),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF232329)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF232329)),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF232329)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFF5F5F5)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Radius',
            style: TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _radiusOptions.map((radius) {
              final selected = _radiusMeters == radius;

              return GestureDetector(
                onTap: _isLocked
                    ? null
                    : () {
                        setState(() {
                          _radiusMeters = radius;
                        });
                      },
                child: Opacity(
                  opacity: _isLocked ? 0.55 : 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFF5F5F5)
                          : const Color(0xFF101013),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFFF5F5F5)
                            : const Color(0xFF232329),
                      ),
                    ),
                    child: Text(
                      '${radius}m',
                      style: TextStyle(
                        color: selected ? Colors.black : const Color(0xFFF5F5F5),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF101013),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF232329)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Captured coordinates',
                  style: TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Latitude: ${_latitude?.toStringAsFixed(6) ?? 'Not set'}',
                  style: const TextStyle(color: Color(0xFFB3B3BB)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Longitude: ${_longitude?.toStringAsFixed(6) ?? 'Not set'}',
                  style: const TextStyle(color: Color(0xFFB3B3BB)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Accuracy: ${_accuracy != null ? '${_accuracy!.toStringAsFixed(1)}m' : 'Unknown'}',
                  style: const TextStyle(color: Color(0xFFB3B3BB)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  (_isFetchingCurrentLocation || _isLocked) ? null : _pickCurrentLocation,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF5F5F5),
                side: const BorderSide(color: Color(0xFF3A3A42)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _isFetchingCurrentLocation
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: Text(
                _isFetchingCurrentLocation
                    ? 'Getting current location...'
                    : _isLocked
                        ? 'Location locked'
                        : 'Use Current Location',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_isSaving || _isDeleting || _isLocked) ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF5F5F5),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              _isSaving
                  ? 'Saving...'
                  : _existingConfig == null
                      ? 'Save Pinned Location'
                      : 'Update Pinned Location',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: (_isSaving || _isDeleting || _isLocked) ? null : _remove,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF8A80),
              side: const BorderSide(color: Color(0xFFFF8A80)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              _isDeleting
                  ? 'Removing...'
                  : _isLocked
                      ? 'Pinned location locked'
                      : 'Remove Pinned Location',
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
        title: const Text('Set Verification Location'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFF5F5F5)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              children: [
                _buildInfoCard(),
                const SizedBox(height: 16),
                _buildFormCard(),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0x22E57373),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE57373)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFFF8A80),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _buildActions(),
              ],
            ),
    );
  }
}