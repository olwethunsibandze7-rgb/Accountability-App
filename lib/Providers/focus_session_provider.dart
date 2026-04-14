import 'package:achievr_app/Services/focus_session_coordinator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final focusSessionCoordinatorProvider =
    ChangeNotifierProvider<FocusSessionCoordinator>((ref) {
  final coordinator = FocusSessionCoordinator();
  ref.onDispose(coordinator.dispose);
  return coordinator;
});