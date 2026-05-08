import 'dart:async';
import 'dart:io';

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
    final rawForeground = raw['foregroundAppIdentifier']?.toString();

    return DeviceRuntimeSnapshot(
      foregroundAppIdentifier:
          (rawForeground == null || rawForeground.trim().isEmpty)
              ? null
              : rawForeground.trim(),
      isScreenOff: raw['isScreenOff'] == true,
      monitoringActive: raw['monitoringActive'] == true,
      timestampMillis: _coerceInt(raw['timestampMillis']) ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory DeviceRuntimeSnapshot.fallback({
    String? foregroundAppIdentifier,
    bool isScreenOff = false,
    bool monitoringActive = false,
  }) {
    return DeviceRuntimeSnapshot(
      foregroundAppIdentifier: foregroundAppIdentifier,
      isScreenOff: isScreenOff,
      monitoringActive: monitoringActive,
      timestampMillis: DateTime.now().millisecondsSinceEpoch,
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
  bool _monitoringRequested = false;

  bool get _supportsNativeRuntime => !kIsWeb && Platform.isAndroid;

  Stream<DeviceRuntimeSnapshot> runtimeStream() {
    if (!_supportsNativeRuntime) {
      return _streamController.stream;
    }

    _ensureNativeSubscription();
    return _streamController.stream;
  }

  DeviceRuntimeSnapshot? get lastSnapshot => _lastSnapshot;

  Future<bool> hasUsageAccess() async {
    if (!_supportsNativeRuntime) {
      debugPrint(
        'DeviceRuntimeService.hasUsageAccess skipped: unsupported platform.',
      );
      return false;
    }

    try {
      final result = await _methodChannel.invokeMethod<bool>('hasUsageAccess');
      return result == true;
    } on MissingPluginException {
      debugPrint(
        'DeviceRuntimeService.hasUsageAccess missing plugin on this target.',
      );
      return false;
    } on PlatformException catch (e) {
      debugPrint('DeviceRuntimeService.hasUsageAccess error: ${e.message}');
      return false;
    } catch (e, st) {
      debugPrint('DeviceRuntimeService.hasUsageAccess unexpected error: $e');
      debugPrint('$st');
      return false;
    }
  }

  Future<void> openUsageAccessSettings() async {
    if (!_supportsNativeRuntime) {
      throw Exception(
        'Usage access settings are available on Android only.',
      );
    }

    try {
      await _methodChannel.invokeMethod<void>('openUsageAccessSettings');
    } on MissingPluginException {
      throw Exception(
        'Usage access settings are not available on this platform.',
      );
    } on PlatformException catch (e) {
      throw Exception(
        e.message ?? 'Failed to open usage access settings.',
      );
    }
  }

  Future<bool> isMonitoringActive() async {
    if (!_supportsNativeRuntime) {
      return false;
    }

    try {
      final result =
          await _methodChannel.invokeMethod<bool>('isMonitoringActive');
      return result == true;
    } on MissingPluginException {
      debugPrint(
        'DeviceRuntimeService.isMonitoringActive missing plugin on this target.',
      );
      return false;
    } on PlatformException catch (e) {
      debugPrint('DeviceRuntimeService.isMonitoringActive error: ${e.message}');
      return false;
    } catch (e, st) {
      debugPrint('DeviceRuntimeService.isMonitoringActive unexpected error: $e');
      debugPrint('$st');
      return false;
    }
  }

  Future<DeviceRuntimeSnapshot?> getCurrentSnapshot() async {
    if (!_supportsNativeRuntime) {
      return _lastSnapshot ??
          DeviceRuntimeSnapshot.fallback(
            foregroundAppIdentifier: 'unsupported_platform',
            isScreenOff: false,
            monitoringActive: false,
          );
    }

    try {
      final result =
          await _methodChannel.invokeMethod<dynamic>('getCurrentSnapshot');

      if (result is Map) {
        final snapshot = DeviceRuntimeSnapshot.fromMap(result);
        _lastSnapshot = snapshot;
        return snapshot;
      }

      return _lastSnapshot;
    } on MissingPluginException {
      debugPrint(
        'DeviceRuntimeService.getCurrentSnapshot missing plugin on this target.',
      );
      return _lastSnapshot;
    } on PlatformException catch (e) {
      debugPrint('DeviceRuntimeService.getCurrentSnapshot error: ${e.message}');
      return _lastSnapshot;
    } catch (e, st) {
      debugPrint('DeviceRuntimeService.getCurrentSnapshot unexpected error: $e');
      debugPrint('$st');
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
    if (!_supportsNativeRuntime) {
      throw Exception(
        'Live app monitoring is supported on Android only. '
        'Use an Android device or Android emulator.',
      );
    }

    final cleanedAllowedApps = allowedAppIdentifiers
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    try {
      if (_monitoringRequested) {
        try {
          await stopMonitoring();
        } catch (_) {}
      }

      await _methodChannel.invokeMethod<void>('startMonitoring', {
        'allowedAppIdentifiers': cleanedAllowedApps,
        'allowScreenOff': allowScreenOff,
        'pollIntervalMs': pollIntervalMs < 500 ? 500 : pollIntervalMs,
        'focusSessionId': focusSessionId,
        'habitId': habitId,
        'logId': logId,
        'graceSeconds': graceSeconds,
      });

      _monitoringRequested = true;
      _ensureNativeSubscription();
    } on MissingPluginException {
      throw Exception(
        'Device runtime monitoring is not available on this target.',
      );
    } on PlatformException catch (e) {
      throw Exception(
        e.message ?? 'Failed to start background monitoring.',
      );
    } catch (e, st) {
      debugPrint('DeviceRuntimeService.startMonitoring unexpected error: $e');
      debugPrint('$st');
      throw Exception('Failed to start background monitoring.');
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
    if (!_supportsNativeRuntime) {
      throw Exception(
        'Live app monitoring is supported on Android only.',
      );
    }

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
    } on MissingPluginException {
      throw Exception(
        'Device runtime monitoring is not available on this target.',
      );
    } on PlatformException catch (e) {
      throw Exception(
        e.message ?? 'Failed to update monitoring config.',
      );
    } catch (e, st) {
      debugPrint(
        'DeviceRuntimeService.updateMonitoringConfig unexpected error: $e',
      );
      debugPrint('$st');
      throw Exception('Failed to update monitoring config.');
    }
  }

  Future<void> stopMonitoring() async {
    _monitoringRequested = false;

    if (!_supportsNativeRuntime) {
      return;
    }

    try {
      await _methodChannel.invokeMethod<void>('stopMonitoring');
    } on MissingPluginException {
      debugPrint(
        'DeviceRuntimeService.stopMonitoring missing plugin on this target.',
      );
    } on PlatformException catch (e) {
      debugPrint('DeviceRuntimeService.stopMonitoring error: ${e.message}');
    } catch (e, st) {
      debugPrint('DeviceRuntimeService.stopMonitoring unexpected error: $e');
      debugPrint('$st');
    }
  }

  Future<void> showMonitoringNotification({
    required String title,
    required String body,
  }) async {
    if (!_supportsNativeRuntime) return;

    try {
      await _methodChannel.invokeMethod<void>('showMonitoringNotification', {
        'title': title,
        'body': body,
      });
    } on MissingPluginException {
      debugPrint(
        'DeviceRuntimeService.showMonitoringNotification missing plugin.',
      );
    } on PlatformException catch (e) {
      debugPrint(
        'DeviceRuntimeService.showMonitoringNotification error: ${e.message}',
      );
    } catch (e, st) {
      debugPrint(
        'DeviceRuntimeService.showMonitoringNotification unexpected error: $e',
      );
      debugPrint('$st');
    }
  }

  Future<void> showGracePeriodNotification({
    required int remainingSeconds,
    String? foregroundAppIdentifier,
    String? reason,
  }) async {
    if (!_supportsNativeRuntime) return;

    try {
      await _methodChannel.invokeMethod<void>('showGracePeriodNotification', {
        'remainingSeconds': remainingSeconds,
        'foregroundAppIdentifier': foregroundAppIdentifier,
        'reason': reason,
      });
    } on MissingPluginException {
      debugPrint(
        'DeviceRuntimeService.showGracePeriodNotification missing plugin.',
      );
    } on PlatformException catch (e) {
      debugPrint(
        'DeviceRuntimeService.showGracePeriodNotification error: ${e.message}',
      );
    } catch (e, st) {
      debugPrint(
        'DeviceRuntimeService.showGracePeriodNotification unexpected error: $e',
      );
      debugPrint('$st');
    }
  }

  Future<void> showFailureNotification({
    String? reason,
  }) async {
    if (!_supportsNativeRuntime) return;

    try {
      await _methodChannel.invokeMethod<void>('showFailureNotification', {
        'reason': reason,
      });
    } on MissingPluginException {
      debugPrint(
        'DeviceRuntimeService.showFailureNotification missing plugin.',
      );
    } on PlatformException catch (e) {
      debugPrint(
        'DeviceRuntimeService.showFailureNotification error: ${e.message}',
      );
    } catch (e, st) {
      debugPrint(
        'DeviceRuntimeService.showFailureNotification unexpected error: $e',
      );
      debugPrint('$st');
    }
  }

  Future<void> showRecoveryNotification({
    String? foregroundAppIdentifier,
  }) async {
    if (!_supportsNativeRuntime) return;

    try {
      await _methodChannel.invokeMethod<void>('showRecoveryNotification', {
        'foregroundAppIdentifier': foregroundAppIdentifier,
      });
    } on MissingPluginException {
      debugPrint(
        'DeviceRuntimeService.showRecoveryNotification missing plugin.',
      );
    } on PlatformException catch (e) {
      debugPrint(
        'DeviceRuntimeService.showRecoveryNotification error: ${e.message}',
      );
    } catch (e, st) {
      debugPrint(
        'DeviceRuntimeService.showRecoveryNotification unexpected error: $e',
      );
      debugPrint('$st');
    }
  }

  void _ensureNativeSubscription() {
    if (!_supportsNativeRuntime) return;
    if (_isSubscribedToNativeEvents) return;

    try {
      _nativeSubscription?.cancel();

      _nativeSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          try {
            if (event is Map) {
              final snapshot = DeviceRuntimeSnapshot.fromMap(event);
              _lastSnapshot = snapshot;
              if (!_streamController.isClosed) {
                _streamController.add(snapshot);
              }
            }
          } catch (e, st) {
            debugPrint(
              'DeviceRuntimeService native event parse error: $e',
            );
            debugPrint('$st');
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('DeviceRuntimeService native stream error: $error');
          debugPrint('$stackTrace');
          if (!_streamController.isClosed) {
            _streamController.addError(error, stackTrace);
          }
          _isSubscribedToNativeEvents = false;
        },
      );

      _isSubscribedToNativeEvents = true;
    } catch (e, st) {
      debugPrint(
        'DeviceRuntimeService failed to subscribe to native events: $e',
      );
      debugPrint('$st');
      _isSubscribedToNativeEvents = false;
    }
  }

  Future<void> dispose() async {
    await _nativeSubscription?.cancel();
    _nativeSubscription = null;
    _isSubscribedToNativeEvents = false;
    _monitoringRequested = false;
  }
}