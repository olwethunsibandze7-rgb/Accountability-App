import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Blocked hours for each day
final blockedHoursProvider =
    StateNotifierProvider<BlockedHoursNotifier, Map<String, Set<int>>>(
  (ref) => BlockedHoursNotifier(),
);

class BlockedHoursNotifier extends StateNotifier<Map<String, Set<int>>> {
  BlockedHoursNotifier()
      : super({
          'Monday': <int>{},
          'Tuesday': <int>{},
          'Wednesday': <int>{},
          'Thursday': <int>{},
          'Friday': <int>{},
          'Saturday': <int>{},
        });

  void toggle(String day, int hour) {
    final updated = <String, Set<int>>{
      for (final entry in state.entries) entry.key: Set<int>.from(entry.value),
    };

    final hours = updated[day] ?? <int>{};

    if (hours.contains(hour)) {
      hours.remove(hour);
    } else {
      hours.add(hour);
    }

    updated[day] = hours;
    state = updated;
  }

  void setAll(Map<String, Set<int>> newState) {
    state = {
      for (final entry in newState.entries)
        entry.key: Set<int>.from(entry.value),
    };
  }

  void reset() {
    state = {
      'Monday': <int>{},
      'Tuesday': <int>{},
      'Wednesday': <int>{},
      'Thursday': <int>{},
      'Friday': <int>{},
      'Saturday': <int>{},
    };
  }
}

/// Selected goal template codes state
final selectedGoalsProvider =
    StateNotifierProvider<SelectedGoalsNotifier, Set<String>>(
  (ref) => SelectedGoalsNotifier(),
);

class SelectedGoalsNotifier extends StateNotifier<Set<String>> {
  SelectedGoalsNotifier() : super(<String>{});

  void toggle(String goalCode, {int maxGoals = 2}) {
    final updated = Set<String>.from(state);

    if (updated.contains(goalCode)) {
      updated.remove(goalCode);
    } else if (updated.length < maxGoals) {
      updated.add(goalCode);
    }

    state = updated;
  }

  void setAll(Iterable<String> goalCodes) {
    state = Set<String>.from(goalCodes);
  }

  bool isSelected(String goalCode) {
    return state.contains(goalCode);
  }

  void reset() {
    state = <String>{};
  }
}

/// Global loading state
final loadingProvider = StateProvider<bool>((ref) => false);