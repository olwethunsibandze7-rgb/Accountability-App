import 'package:flutter/foundation.dart';

enum FocusSessionPhase {
  idle,
  arming,
  running,
  violationDebounce,
  grace,
  completed,
  failed,
  abandoned,
}

enum FocusViolationReason {
  none,
  appNotAllowed,
  locationNotAllowed,
  screenOffNotAllowed,
}

enum FocusEventType {
  sessionStarted,
  runningResumed,
  violationDebounceStarted,
  graceStarted,
  returnedToRunning,
  appViolationCommitted,
  locationViolationCommitted,
  screenOffViolationCommitted,
  sessionCompleted,
  sessionFailed,
  sessionAbandoned,
  syncCheckpoint,
}

@immutable
class FocusPolicy {
  final Set<String> allowedAppIds;
  final bool allowScreenOff;
  final bool requiresLocation;
  final int violationDebounceSeconds;
  final int graceSeconds;
  final int requiredValidSeconds;

  const FocusPolicy({
    required this.allowedAppIds,
    required this.allowScreenOff,
    required this.requiresLocation,
    required this.violationDebounceSeconds,
    required this.graceSeconds,
    required this.requiredValidSeconds,
  });

  FocusPolicy copyWith({
    Set<String>? allowedAppIds,
    bool? allowScreenOff,
    bool? requiresLocation,
    int? violationDebounceSeconds,
    int? graceSeconds,
    int? requiredValidSeconds,
  }) {
    return FocusPolicy(
      allowedAppIds: allowedAppIds ?? this.allowedAppIds,
      allowScreenOff: allowScreenOff ?? this.allowScreenOff,
      requiresLocation: requiresLocation ?? this.requiresLocation,
      violationDebounceSeconds:
          violationDebounceSeconds ?? this.violationDebounceSeconds,
      graceSeconds: graceSeconds ?? this.graceSeconds,
      requiredValidSeconds: requiredValidSeconds ?? this.requiredValidSeconds,
    );
  }
}

@immutable
class FocusRuntimeSnapshot {
  final DateTime capturedAt;
  final String? foregroundAppId;
  final bool isScreenOff;
  final double? latitude;
  final double? longitude;

  const FocusRuntimeSnapshot({
    required this.capturedAt,
    required this.foregroundAppId,
    required this.isScreenOff,
    required this.latitude,
    required this.longitude,
  });

  FocusRuntimeSnapshot copyWith({
    DateTime? capturedAt,
    String? foregroundAppId,
    bool? isScreenOff,
    double? latitude,
    double? longitude,
  }) {
    return FocusRuntimeSnapshot(
      capturedAt: capturedAt ?? this.capturedAt,
      foregroundAppId: foregroundAppId ?? this.foregroundAppId,
      isScreenOff: isScreenOff ?? this.isScreenOff,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}

@immutable
class FocusLocationTarget {
  final double latitude;
  final double longitude;
  final double radiusMeters;

  const FocusLocationTarget({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });
}

@immutable
class FocusContextEvaluation {
  final bool isAllowed;
  final bool isAppAllowed;
  final bool isLocationAllowed;
  final bool isScreenOffAllowed;
  final FocusViolationReason reason;
  final String? reasonMessage;

  const FocusContextEvaluation({
    required this.isAllowed,
    required this.isAppAllowed,
    required this.isLocationAllowed,
    required this.isScreenOffAllowed,
    required this.reason,
    required this.reasonMessage,
  });

  factory FocusContextEvaluation.allowed() {
    return const FocusContextEvaluation(
      isAllowed: true,
      isAppAllowed: true,
      isLocationAllowed: true,
      isScreenOffAllowed: true,
      reason: FocusViolationReason.none,
      reasonMessage: null,
    );
  }
}

@immutable
class FocusSessionEvent {
  final FocusEventType type;
  final DateTime occurredAt;
  final FocusSessionPhase phaseBefore;
  final FocusSessionPhase phaseAfter;
  final FocusViolationReason reason;
  final String? message;
  final String? foregroundAppId;
  final Map<String, dynamic>? metadata;

  const FocusSessionEvent({
    required this.type,
    required this.occurredAt,
    required this.phaseBefore,
    required this.phaseAfter,
    required this.reason,
    required this.message,
    required this.foregroundAppId,
    required this.metadata,
  });
}

@immutable
class FocusEngineState {
  final FocusSessionPhase phase;
  final DateTime startedAt;
  final DateTime lastAccountingAt;
  final DateTime phaseEnteredAt;
  final DateTime? pendingViolationStartedAt;

  final int validFocusSeconds;
  final int graceSecondsUsed;

  final int appViolationCount;
  final int locationViolationCount;
  final int screenOffViolationCount;

  final bool appAllowed;
  final bool locationAllowed;
  final bool screenOffAllowed;
  final bool isCurrentlyAllowed;

  final FocusViolationReason activeViolationReason;
  final String? activeViolationMessage;

  final String? foregroundAppId;
  final bool isScreenOff;

  final bool thresholdMet;
  final bool isTerminal;

  const FocusEngineState({
    required this.phase,
    required this.startedAt,
    required this.lastAccountingAt,
    required this.phaseEnteredAt,
    required this.pendingViolationStartedAt,
    required this.validFocusSeconds,
    required this.graceSecondsUsed,
    required this.appViolationCount,
    required this.locationViolationCount,
    required this.screenOffViolationCount,
    required this.appAllowed,
    required this.locationAllowed,
    required this.screenOffAllowed,
    required this.isCurrentlyAllowed,
    required this.activeViolationReason,
    required this.activeViolationMessage,
    required this.foregroundAppId,
    required this.isScreenOff,
    required this.thresholdMet,
    required this.isTerminal,
  });

  factory FocusEngineState.initial(DateTime now) {
    return FocusEngineState(
      phase: FocusSessionPhase.idle,
      startedAt: now,
      lastAccountingAt: now,
      phaseEnteredAt: now,
      pendingViolationStartedAt: null,
      validFocusSeconds: 0,
      graceSecondsUsed: 0,
      appViolationCount: 0,
      locationViolationCount: 0,
      screenOffViolationCount: 0,
      appAllowed: true,
      locationAllowed: true,
      screenOffAllowed: true,
      isCurrentlyAllowed: true,
      activeViolationReason: FocusViolationReason.none,
      activeViolationMessage: null,
      foregroundAppId: null,
      isScreenOff: false,
      thresholdMet: false,
      isTerminal: false,
    );
  }

  FocusEngineState copyWith({
    FocusSessionPhase? phase,
    DateTime? startedAt,
    DateTime? lastAccountingAt,
    DateTime? phaseEnteredAt,
    DateTime? pendingViolationStartedAt,
    bool clearPendingViolationStartedAt = false,
    int? validFocusSeconds,
    int? graceSecondsUsed,
    int? appViolationCount,
    int? locationViolationCount,
    int? screenOffViolationCount,
    bool? appAllowed,
    bool? locationAllowed,
    bool? screenOffAllowed,
    bool? isCurrentlyAllowed,
    FocusViolationReason? activeViolationReason,
    String? activeViolationMessage,
    bool clearActiveViolationMessage = false,
    String? foregroundAppId,
    bool? isScreenOff,
    bool? thresholdMet,
    bool? isTerminal,
  }) {
    return FocusEngineState(
      phase: phase ?? this.phase,
      startedAt: startedAt ?? this.startedAt,
      lastAccountingAt: lastAccountingAt ?? this.lastAccountingAt,
      phaseEnteredAt: phaseEnteredAt ?? this.phaseEnteredAt,
      pendingViolationStartedAt: clearPendingViolationStartedAt
          ? null
          : (pendingViolationStartedAt ?? this.pendingViolationStartedAt),
      validFocusSeconds: validFocusSeconds ?? this.validFocusSeconds,
      graceSecondsUsed: graceSecondsUsed ?? this.graceSecondsUsed,
      appViolationCount: appViolationCount ?? this.appViolationCount,
      locationViolationCount:
          locationViolationCount ?? this.locationViolationCount,
      screenOffViolationCount:
          screenOffViolationCount ?? this.screenOffViolationCount,
      appAllowed: appAllowed ?? this.appAllowed,
      locationAllowed: locationAllowed ?? this.locationAllowed,
      screenOffAllowed: screenOffAllowed ?? this.screenOffAllowed,
      isCurrentlyAllowed: isCurrentlyAllowed ?? this.isCurrentlyAllowed,
      activeViolationReason:
          activeViolationReason ?? this.activeViolationReason,
      activeViolationMessage: clearActiveViolationMessage
          ? null
          : (activeViolationMessage ?? this.activeViolationMessage),
      foregroundAppId: foregroundAppId ?? this.foregroundAppId,
      isScreenOff: isScreenOff ?? this.isScreenOff,
      thresholdMet: thresholdMet ?? this.thresholdMet,
      isTerminal: isTerminal ?? this.isTerminal,
    );
  }
}