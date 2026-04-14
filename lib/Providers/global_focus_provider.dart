import 'package:achievr_app/Services/global_focus_session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final globalFocusControllerProvider =
    ChangeNotifierProvider<GlobalFocusSessionController>((ref) {
  final controller = GlobalFocusSessionController();
  ref.onDispose(controller.dispose);
  return controller;
});