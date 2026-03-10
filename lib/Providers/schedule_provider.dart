import 'package:flutter_riverpod/flutter_riverpod.dart';

final blockedHoursProvider =
    StateNotifierProvider<BlockedHoursNotifier, Map<String, Set<int>>>(
  (ref) => BlockedHoursNotifier(),
);

class BlockedHoursNotifier extends StateNotifier<Map<String, Set<int>>> {
  BlockedHoursNotifier()
      : super({
          "Mon": <int>{},
          "Tue": <int>{},
          "Wed": <int>{},
          "Thu": <int>{},
          "Fri": <int>{},
          "Sat": <int>{},
        });

  void toggle(String day, int hour) {
    final currentSet = state[day] ?? <int>{};
    final newSet = Set<int>.from(currentSet);

    if (newSet.contains(hour)) {
      newSet.remove(hour);
    } else {
      newSet.add(hour);
    }

    state = {...state, day: newSet};
  }
}