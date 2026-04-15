import 'dart:math';

import 'package:achievr_app/Services/focus_engine_models.dart';
import 'package:geolocator/geolocator.dart';

class FocusSessionEngineResult {
  final FocusEngineState state;
  final List<FocusSessionEvent> events;

  const FocusSessionEngineResult({
    required this.state,
    required this.events,
  });
}

class FocusSessionEngine {
  static const Set<String> _achievrAppIds = {
    'com.example.achievr_app',
    'com.achievr.app',
    'achievr',
  };

  final FocusPolicy policy;
  final FocusLocationTarget? locationTarget;

  FocusEngineState _state;

  FocusEngineState get state => _state;

  FocusSessionEngine({
    required this.policy,
    required DateTime startedAt,
    this.locationTarget,
  }) : _state = FocusEngineState.initial(startedAt).copyWith(
          phase: FocusSessionPhase.arming,
          startedAt: startedAt,
          lastAccountingAt: startedAt,
          phaseEnteredAt: startedAt,
        );

  static String? normalizeAppId(String? appId) {
    final value = appId?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  FocusContextEvaluation evaluateContext(FocusRuntimeSnapshot snapshot) {
    final normalizedForeground = normalizeAppId(snapshot.foregroundAppId);

    final isAchievr =
        normalizedForeground != null && _achievrAppIds.contains(normalizedForeground);

    final isAllowedApp = snapshot.isScreenOff
        ? policy.allowScreenOff
        : isAchievr ||
            (normalizedForeground != null &&
                policy.allowedAppIds
                    .map((e) => e.trim().toLowerCase())
                    .contains(normalizedForeground));

    final isScreenOffAllowed = !snapshot.isScreenOff || policy.allowScreenOff;

    bool isLocationAllowed = true;
    if (policy.requiresLocation) {
      if (locationTarget == null ||
          snapshot.latitude == null ||
          snapshot.longitude == null) {
        isLocationAllowed = false;
      } else {
        final distance = Geolocator.distanceBetween(
          snapshot.latitude!,
          snapshot.longitude!,
          locationTarget!.latitude,
          locationTarget!.longitude,
        );
        isLocationAllowed = distance <= locationTarget!.radiusMeters;
      }
    }

    if (!isScreenOffAllowed) {
      return const FocusContextEvaluation(
        isAllowed: false,
        isAppAllowed: false,
        isLocationAllowed: true,
        isScreenOffAllowed: false,
        reason: FocusViolationReason.screenOffNotAllowed,
        reasonMessage: 'Screen off is not allowed.',
      );
    }

    if (!isAllowedApp) {
      return const FocusContextEvaluation(
        isAllowed: false,
        isAppAllowed: false,
        isLocationAllowed: true,
        isScreenOffAllowed: true,
        reason: FocusViolationReason.appNotAllowed,
        reasonMessage: 'You left the allowed app.',
      );
    }

    if (!isLocationAllowed) {
      return const FocusContextEvaluation(
        isAllowed: false,
        isAppAllowed: true,
        isLocationAllowed: false,
        isScreenOffAllowed: true,
        reason: FocusViolationReason.locationNotAllowed,
        reasonMessage: 'You left the required location.',
      );
    }

    return const FocusContextEvaluation(
      isAllowed: true,
      isAppAllowed: true,
      isLocationAllowed: true,
      isScreenOffAllowed: true,
      reason: FocusViolationReason.none,
      reasonMessage: null,
    );
  }

  FocusSessionEngineResult start(FocusRuntimeSnapshot snapshot) {
    final now = snapshot.capturedAt;
    final evaluation = evaluateContext(snapshot);
    final events = <FocusSessionEvent>[];

    _state = _state.copyWith(
      phase: FocusSessionPhase.running,
      phaseEnteredAt: now,
      lastAccountingAt: now,
      appAllowed: evaluation.isAppAllowed,
      locationAllowed: evaluation.isLocationAllowed,
      screenOffAllowed: evaluation.isScreenOffAllowed,
      isCurrentlyAllowed: evaluation.isAllowed,
      activeViolationReason: evaluation.reason,
      activeViolationMessage: evaluation.reasonMessage,
      foregroundAppId: normalizeAppId(snapshot.foregroundAppId),
      isScreenOff: snapshot.isScreenOff,
    );

    events.add(
      FocusSessionEvent(
        type: FocusEventType.sessionStarted,
        occurredAt: now,
        phaseBefore: FocusSessionPhase.arming,
        phaseAfter: FocusSessionPhase.running,
        reason: FocusViolationReason.none,
        message: 'Focus session started.',
        foregroundAppId: _state.foregroundAppId,
        metadata: null,
      ),
    );

    return FocusSessionEngineResult(state: _state, events: events);
  }

  FocusSessionEngineResult hydrateFromServer({
    required DateTime now,
    required FocusRuntimeSnapshot snapshot,
    required FocusSessionPhase phase,
    required int validFocusSeconds,
    required int graceSecondsUsed,
    required int appViolationCount,
    required int locationViolationCount,
    int screenOffViolationCount = 0,
    DateTime? startedAt,
    DateTime? phaseEnteredAt,
    DateTime? pendingViolationStartedAt,
  }) {
    final evaluation = evaluateContext(snapshot);

    _state = FocusEngineState(
      phase: phase,
      startedAt: startedAt ?? now,
      lastAccountingAt: now,
      phaseEnteredAt: phaseEnteredAt ?? now,
      pendingViolationStartedAt: pendingViolationStartedAt,
      validFocusSeconds: max(0, validFocusSeconds),
      graceSecondsUsed: max(0, graceSecondsUsed),
      appViolationCount: max(0, appViolationCount),
      locationViolationCount: max(0, locationViolationCount),
      screenOffViolationCount: max(0, screenOffViolationCount),
      appAllowed: evaluation.isAppAllowed,
      locationAllowed: evaluation.isLocationAllowed,
      screenOffAllowed: evaluation.isScreenOffAllowed,
      isCurrentlyAllowed: evaluation.isAllowed,
      activeViolationReason: evaluation.reason,
      activeViolationMessage: evaluation.reasonMessage,
      foregroundAppId: normalizeAppId(snapshot.foregroundAppId),
      isScreenOff: snapshot.isScreenOff,
      thresholdMet: validFocusSeconds >= policy.requiredValidSeconds,
      isTerminal: phase == FocusSessionPhase.completed ||
          phase == FocusSessionPhase.failed ||
          phase == FocusSessionPhase.abandoned,
    );

    return FocusSessionEngineResult(
      state: _state,
      events: const [],
    );
  }

  FocusSessionPhase mapServerStatusToPhase(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'running':
        return FocusSessionPhase.running;
      case 'grace':
        return FocusSessionPhase.grace;
      case 'completed':
        return FocusSessionPhase.completed;
      case 'failed':
      case 'invalidated':
        return FocusSessionPhase.failed;
      case 'abandoned':
        return FocusSessionPhase.abandoned;
      case 'paused':
        return FocusSessionPhase.violationDebounce;
      default:
        return FocusSessionPhase.arming;
    }
  }

  FocusSessionEngineResult tick(FocusRuntimeSnapshot snapshot) {
    final now = snapshot.capturedAt;
    final evaluation = evaluateContext(snapshot);
    final events = <FocusSessionEvent>[];

    final elapsed = max(0, now.difference(_state.lastAccountingAt).inSeconds);

    var next = _state.copyWith(
      lastAccountingAt: now,
      appAllowed: evaluation.isAppAllowed,
      locationAllowed: evaluation.isLocationAllowed,
      screenOffAllowed: evaluation.isScreenOffAllowed,
      isCurrentlyAllowed: evaluation.isAllowed,
      activeViolationReason: evaluation.reason,
      activeViolationMessage: evaluation.reasonMessage,
      foregroundAppId: normalizeAppId(snapshot.foregroundAppId),
      isScreenOff: snapshot.isScreenOff,
    );

    switch (_state.phase) {
      case FocusSessionPhase.idle:
      case FocusSessionPhase.arming:
        return FocusSessionEngineResult(state: next, events: events);

      case FocusSessionPhase.running:
        if (evaluation.isAllowed) {
          next = next.copyWith(
            validFocusSeconds: _state.validFocusSeconds + elapsed,
            thresholdMet:
                (_state.validFocusSeconds + elapsed) >= policy.requiredValidSeconds,
          );
        } else {
          next = next.copyWith(
            validFocusSeconds: _state.validFocusSeconds + elapsed,
            thresholdMet:
                (_state.validFocusSeconds + elapsed) >= policy.requiredValidSeconds,
            phase: FocusSessionPhase.violationDebounce,
            phaseEnteredAt: now,
            pendingViolationStartedAt: now,
          );

          events.add(
            FocusSessionEvent(
              type: FocusEventType.violationDebounceStarted,
              occurredAt: now,
              phaseBefore: FocusSessionPhase.running,
              phaseAfter: FocusSessionPhase.violationDebounce,
              reason: evaluation.reason,
              message: evaluation.reasonMessage,
              foregroundAppId: next.foregroundAppId,
              metadata: null,
            ),
          );
        }
        break;

      case FocusSessionPhase.violationDebounce:
        if (evaluation.isAllowed) {
          next = next.copyWith(
            phase: FocusSessionPhase.running,
            phaseEnteredAt: now,
            clearPendingViolationStartedAt: true,
            clearActiveViolationMessage: true,
            activeViolationReason: FocusViolationReason.none,
          );

          events.add(
            FocusSessionEvent(
              type: FocusEventType.returnedToRunning,
              occurredAt: now,
              phaseBefore: FocusSessionPhase.violationDebounce,
              phaseAfter: FocusSessionPhase.running,
              reason: FocusViolationReason.none,
              message: 'Returned before debounce expired.',
              foregroundAppId: next.foregroundAppId,
              metadata: null,
            ),
          );
        } else {
          final pendingSince = _state.pendingViolationStartedAt ?? now;
          final debounceElapsed = now.difference(pendingSince).inSeconds;

          if (debounceElapsed >= policy.violationDebounceSeconds) {
            var appViolations = _state.appViolationCount;
            var locationViolations = _state.locationViolationCount;
            var screenOffViolations = _state.screenOffViolationCount;

            if (evaluation.reason == FocusViolationReason.appNotAllowed) {
              appViolations += 1;
            } else if (evaluation.reason ==
                FocusViolationReason.locationNotAllowed) {
              locationViolations += 1;
            } else if (evaluation.reason ==
                FocusViolationReason.screenOffNotAllowed) {
              screenOffViolations += 1;
            }

            next = next.copyWith(
              phase: FocusSessionPhase.grace,
              phaseEnteredAt: now,
              appViolationCount: appViolations,
              locationViolationCount: locationViolations,
              screenOffViolationCount: screenOffViolations,
            );

            events.add(
              FocusSessionEvent(
                type: FocusEventType.graceStarted,
                occurredAt: now,
                phaseBefore: FocusSessionPhase.violationDebounce,
                phaseAfter: FocusSessionPhase.grace,
                reason: evaluation.reason,
                message: evaluation.reasonMessage,
                foregroundAppId: next.foregroundAppId,
                metadata: null,
              ),
            );
          }
        }
        break;

      case FocusSessionPhase.grace:
        if (evaluation.isAllowed) {
          next = next.copyWith(
            phase: FocusSessionPhase.running,
            phaseEnteredAt: now,
            graceSecondsUsed: _state.graceSecondsUsed,
            clearPendingViolationStartedAt: true,
            clearActiveViolationMessage: true,
            activeViolationReason: FocusViolationReason.none,
          );

          events.add(
            FocusSessionEvent(
              type: FocusEventType.runningResumed,
              occurredAt: now,
              phaseBefore: FocusSessionPhase.grace,
              phaseAfter: FocusSessionPhase.running,
              reason: FocusViolationReason.none,
              message: 'Returned to allowed context.',
              foregroundAppId: next.foregroundAppId,
              metadata: null,
            ),
          );
        } else {
          final newGraceUsed = _state.graceSecondsUsed + elapsed;

          if (newGraceUsed >= policy.graceSeconds) {
            next = next.copyWith(
              graceSecondsUsed: newGraceUsed,
              phase: FocusSessionPhase.failed,
              phaseEnteredAt: now,
              isTerminal: true,
            );

            events.add(
              FocusSessionEvent(
                type: FocusEventType.sessionFailed,
                occurredAt: now,
                phaseBefore: FocusSessionPhase.grace,
                phaseAfter: FocusSessionPhase.failed,
                reason: evaluation.reason,
                message: 'Grace expired.',
                foregroundAppId: next.foregroundAppId,
                metadata: null,
              ),
            );
          } else {
            next = next.copyWith(
              graceSecondsUsed: newGraceUsed,
            );
          }
        }
        break;

      case FocusSessionPhase.completed:
      case FocusSessionPhase.failed:
      case FocusSessionPhase.abandoned:
        return FocusSessionEngineResult(state: _state, events: events);
    }

    _state = next;
    return FocusSessionEngineResult(state: _state, events: events);
  }

  FocusSessionEngineResult complete(DateTime now) {
    final before = _state.phase;

    _state = _state.copyWith(
      phase: FocusSessionPhase.completed,
      phaseEnteredAt: now,
      thresholdMet: _state.validFocusSeconds >= policy.requiredValidSeconds,
      isTerminal: true,
    );

    return FocusSessionEngineResult(
      state: _state,
      events: [
        FocusSessionEvent(
          type: FocusEventType.sessionCompleted,
          occurredAt: now,
          phaseBefore: before,
          phaseAfter: FocusSessionPhase.completed,
          reason: FocusViolationReason.none,
          message: 'Session completed.',
          foregroundAppId: _state.foregroundAppId,
          metadata: null,
        ),
      ],
    );
  }

  FocusSessionEngineResult abandon(DateTime now) {
    final before = _state.phase;

    _state = _state.copyWith(
      phase: FocusSessionPhase.abandoned,
      phaseEnteredAt: now,
      isTerminal: true,
    );

    return FocusSessionEngineResult(
      state: _state,
      events: [
        FocusSessionEvent(
          type: FocusEventType.sessionAbandoned,
          occurredAt: now,
          phaseBefore: before,
          phaseAfter: FocusSessionPhase.abandoned,
          reason: FocusViolationReason.none,
          message: 'Session abandoned.',
          foregroundAppId: _state.foregroundAppId,
          metadata: null,
        ),
      ],
    );
  }
}