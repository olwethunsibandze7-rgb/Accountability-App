import 'package:achievr_app/Services/focus_session_runtime_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final focusRuntimeControllerProvider =
    ChangeNotifierProvider<FocusSessionRuntimeController>((ref) {
  final controller = FocusSessionRuntimeController();
  ref.onDispose(controller.dispose);
  return controller;
});