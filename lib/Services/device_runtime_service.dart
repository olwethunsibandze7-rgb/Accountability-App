import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class DeviceRuntimeSnapshot {
  final String? foregroundAppIdentifier;
  final bool isScreenOff;
  final bool monitoringActive;
  final int timestampMillis;

  const DeviceRuntimeSnapshot({
    required this.foregroundAppIdentifier,
    required this.isScreenOff,
    required this.monitoringActive,
    required this.timestampMillis,
  });

  factory DeviceRuntimeSnapshot.fromMap(Map<dynamic, dynamic> raw) {
    return DeviceRuntimeSnapshot(
      foregroundAppIdentifier:
          raw['foregroundAppIdentifier']?.toString().trim().isEmpty == true
              ? null
              : raw['foregroundAppIdentifier']?.toString(),
      isScreenOff: raw['isScreenOff'] == true,
      monitoringActive: raw['monitoringActive'] == true,
      timestampMillis: _coerceInt(raw['timestampMillis']) ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'foregroundAppIdentifier': foregroundAppIdentifier,
      'isScreenOff': isScreenOff,
      'monitoringActive': monitoringActive,
      'timestampMillis': timestampMillis,
    };
  }

  DeviceRuntimeSnapshot copyWith({
    String? foregroundAppIdentifier,
    bool? isScreenOff,
    bool? monitoringActive,
    int? timestampMillis,
  }) {
    return DeviceRuntimeSnapshot(
      foregroundAppIdentifier:
          foregroundAppIdentifier ?? this.foregroundAppIdentifier,
      isScreenOff: isScreenOff ?? this.isScreenOff,
      monitoringActive: monitoringActive ?? this.monitoringActive,
      timestampMillis: timestampMillis ?? this.timestampMillis,
    );
  }

  static int? _coerceInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString());
  }

  @override
  String toString() {
    return 'DeviceRuntimeSnapshot('
        'foregroundAppIdentifier: $foregroundAppIdentifier, '
        'isScreenOff: $isScreenOff, '
        'monitoringActive: $monitoringActive, '
        'timestampMillis: $timestampMillis'
        ')';
  }
}

class DeviceRuntimeService {
  DeviceRuntimeService._internal();

  static final DeviceRuntimeService _instance =
      DeviceRuntimeService._internal();

  factory DeviceRuntimeService() => _instance;

  static const MethodChannel _methodChannel =
      MethodChannel('achievr/device_runtime_method');

  static const EventChannel _eventChannel =
      EventChannel('achievr/device_runtime_events');

  final StreamController<DeviceRuntimeSnapshot> _streamController =
      StreamController<DeviceRuntimeSnapshot>.broadcast();

  StreamSubscription<dynamic>? _nativeSubscription;

  DeviceRuntimeSnapshot? _lastSnapshot;
  bool _isSubscribedToNativeEvents = false;

  Stream<DeviceRuntimeSnapshot> runtimeStream() {
    _ensureNativeSubscription();
    return _streamController.stream;
  }

  DeviceRuntimeSnapshot? get lastSnapshot => _lastSnapshot;

  Future<bool> hasUsageAccess() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('hasUsageAccess');
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('DeviceRuntimeService.hasUsageAccess error: ${e.message}');
      return false;
    }
  }

  Future<void> openUsageAccessSettings() async {
    try {
      await _methodChannel.invokeMethod<void>('openUsageAccessSettings');
    } on PlatformException catch (e) {
      throw Exception(
        e.message ?? 'Failed to open usage access settings.',
      );
    }
  }

  Future<bool> isMonitoringActive() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('isMonitoringActive');
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('DeviceRuntimeService.isMonitoringActive error: ${e.message}');
      return false;
    }
  }

  Future<DeviceRuntimeSnapshot?> getCurrentSnapshot() async {
    try {
      final result =
          await _methodChannel.invokeMethod<dynamic>('getCurrentSnapshot');

      if (result is Map) {
        final snapshot = DeviceRuntimeSnapshot.fromMap(result);
        _lastSnapshot = snapshot;
        return snapshot;
      }

      return _lastSnapshot;
    } on PlatformException catch (e) {
      debugPrint('DeviceRuntimeService.getCurrentSnapshot error: ${e.message}');
      return _lastSnapshot;
    }
  }

  Future<void> startMonitoring({
    required List<String> allowedAppIdentifiers,
    required bool allowScreenOff,
    int pollIntervalMs = 1000,
    String? focusSessionId,
    String? habitId,
    String? logId,
    int? graceSeconds,
  }) async {
    final cleanedAllowedApps = allowedAppIdentifiers
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    try {
      await _methodChannel.invokeMethod<void>('startMonitoring', {
        'allowedAppIdentifiers': cleanedAllowedApps,
        'allowScreenOff': allowScreenOff,
        'pollIntervalMs': pollIntervalMs < 500 ? 500 : pollIntervalMs,
        'focusSessionId': focusSessionId,
        'habitId': habitId,
        'logId': logId,
        'graceSeconds': graceSeconds,
      });

      _ensureNativeSubscription();
    } on PlatformException catch (e) {
      throw Exception(
        e.message ?? 'Failed to start background monitoring.',
      );
    }
  }

  Future<void> updateMonitoringConfig({
    required List<String> allowedAppIdentifiers,
    required bool allowScreenOff,
    int pollIntervalMs = 1000,
    String? focusSessionId,
    String? habitId,
    String? logId,
    int? graceSeconds,
  }) async {
    final cleanedAllowedApps = allowedAppIdentifiers
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    try {
      await _methodChannel.invokeMethod<void>('updateMonitoringConfig', {
        'allowedAppIdentifiers': cleanedAllowedApps,
        'allowScreenOff': allowScreenOff,
        'pollIntervalMs': pollIntervalMs < 500 ? 500 : pollIntervalMs,
        'focusSessionId': focusSessionId,
        'habitId': habitId,
        'logId': logId,
        'graceSeconds': graceSeconds,
      });
    } on PlatformException catch (e) {
      throw Exception(
        e.message ?? 'Failed to update monitoring config.',
      );
    }
  }

  Future<void> stopMonitoring() async {
    try {
      await _methodChannel.invokeMethod<void>('stopMonitoring');
    } on PlatformException catch (e) {
      debugPrint('DeviceRuntimeService.stopMonitoring error: ${e.message}');
    }
  }

  Future<void> showMonitoringNotification({
    required String title,
    required String body,
  }) async {
    try {
      await _methodChannel.invokeMethod<void>('showMonitoringNotification', {
        'title': title,
        'body': body,
      });
    } on PlatformException catch (e) {
      debugPrint(
        'DeviceRuntimeService.showMonitoringNotification error: ${e.message}',
      );
    }
  }

  Future<void> showGracePeriodNotification({
    required int remainingSeconds,
    String? foregroundAppIdentifier,
    String? reason,
  }) async {
    try {
      await _methodChannel.invokeMethod<void>('showGracePeriodNotification', {
        'remainingSeconds': remainingSeconds,
        'foregroundAppIdentifier': foregroundAppIdentifier,
        'reason': reason,
      });
    } on PlatformException catch (e) {
      debugPrint(
        'DeviceRuntimeService.showGracePeriodNotification error: ${e.message}',
      );
    }
  }

  Future<void> showFailureNotification({
    String? reason,
  }) async {
    try {
      await _methodChannel.invokeMethod<void>('showFailureNotification', {
        'reason': reason,
      });
    } on PlatformException catch (e) {
      debugPrint(
        'DeviceRuntimeService.showFailureNotification error: ${e.message}',
      );
    }
  }

  Future<void> showRecoveryNotification({
    String? foregroundAppIdentifier,
  }) async {
    try {
      await _methodChannel.invokeMethod<void>('showRecoveryNotification', {
        'foregroundAppIdentifier': foregroundAppIdentifier,
      });
    } on PlatformException catch (e) {
      debugPrint(
        'DeviceRuntimeService.showRecoveryNotification error: ${e.message}',
      );
    }
  }

  void _ensureNativeSubscription() {
    if (_isSubscribedToNativeEvents) return;

    _nativeSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final snapshot = DeviceRuntimeSnapshot.fromMap(event);
          _lastSnapshot = snapshot;
          if (!_streamController.isClosed) {
            _streamController.add(snapshot);
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_streamController.isClosed) {
          _streamController.addError(error, stackTrace);
        }
      },
    );

    _isSubscribedToNativeEvents = true;
  }

  Future<void> dispose() async {
    await _nativeSubscription?.cancel();
    _nativeSubscription = null;
    _isSubscribedToNativeEvents = false;
  }
}