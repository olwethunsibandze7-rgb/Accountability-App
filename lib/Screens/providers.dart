import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Blocked hours for each day
final blockedHoursProvider = StateNotifierProvider<BlockedHoursNotifier, Map<String, Set<int>>>(
  (ref) => BlockedHoursNotifier(),
);

class BlockedHoursNotifier extends StateNotifier<Map<String, Set<int>>> {
  BlockedHoursNotifier()
      : super({
          'Mon': {},
          'Tue': {},
          'Wed': {},
          'Thu': {},
          'Fri': {},
          'Sat': {},
        });

  void toggle(String day, int hour) {
    final updated = Map<String, Set<int>>.from(state);
    final hours = Set<int>.from(updated[day]!);
    if (hours.contains(hour)) {
      hours.remove(hour);
    } else {
      hours.add(hour);
    }
    updated[day] = hours;
    state = updated;
  }

  void setAll(Map<String, Set<int>> newState) => state = newState;
}

/// Selected goals state
final selectedGoalsProvider = StateNotifierProvider<SelectedGoalsNotifier, Set<String>>(
  (ref) => SelectedGoalsNotifier(),
);

class SelectedGoalsNotifier extends StateNotifier<Set<String>> {
  SelectedGoalsNotifier() : super({});

  void toggle(String goal, {int maxGoals = 2}) {
    final updated = Set<String>.from(state);
    if (updated.contains(goal)) {
      updated.remove(goal);
    } else if (updated.length < maxGoals) {
      updated.add(goal);
    }
    state = updated;
  }

  void reset() => state = {};
}

/// Global loading state
final loadingProvider = StateProvider<bool>((ref) => false);