import 'dart:async';

import 'package:flutter/services.dart';

class DeviceRuntimeSnapshot {
  final String? foregroundAppIdentifier;
  final bool isScreenOff;
  final DateTime timestamp;

  DeviceRuntimeSnapshot({
    required this.foregroundAppIdentifier,
    required this.isScreenOff,
    required this.timestamp,
  });

  factory DeviceRuntimeSnapshot.fromMap(Map<dynamic, dynamic> map) {
    return DeviceRuntimeSnapshot(
      foregroundAppIdentifier: map['foregroundAppIdentifier']?.toString(),
      isScreenOff: map['isScreenOff'] == true,
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class DeviceRuntimeService {
  static const MethodChannel _methodChannel =
      MethodChannel('achievr/device_runtime_methods');

  static const EventChannel _eventChannel =
      EventChannel('achievr/device_runtime_events');

  Stream<DeviceRuntimeSnapshot>? _stream;

  Future<bool> hasUsageAccess() async {
    final result = await _methodChannel.invokeMethod<bool>('hasUsageAccess');
    return result ?? false;
  }

  Future<void> openUsageAccessSettings() async {
    await _methodChannel.invokeMethod('openUsageAccessSettings');
  }

  Future<void> startMonitoring({
    required List<String> allowedAppIdentifiers,
    required bool allowScreenOff,
    required int pollIntervalMs,
  }) async {
    await _methodChannel.invokeMethod('startMonitoring', {
      'allowedAppIdentifiers': allowedAppIdentifiers,
      'allowScreenOff': allowScreenOff,
      'pollIntervalMs': pollIntervalMs,
    });
  }

  Future<void> stopMonitoring() async {
    await _methodChannel.invokeMethod('stopMonitoring');
  }

  Stream<DeviceRuntimeSnapshot> runtimeStream() {
    _stream ??= _eventChannel.receiveBroadcastStream().map((event) {
      return DeviceRuntimeSnapshot.fromMap(Map<dynamic, dynamic>.from(event));
    });
    return _stream!;
  }
}