import 'package:achievr_app/Providers/focus_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'Screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://lqfqkjyjrwizzxullulo.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxxZnFranlqcndpenp4dWxsdWxvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE4OTg2MjcsImV4cCI6MjA4NzQ3NDYyN30.pDrtRRZpDFyfoZZGW16FBdPshcUDQZxNTLD4MsLFYkA',
  );

  runApp(
    const ProviderScope(
      child: AchievrApp(),
    ),
  );
}

class AchievrApp extends ConsumerWidget {
  const AchievrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focusState = ref.watch(focusSessionCoordinatorProvider).state;

    return MaterialApp(
      title: 'Achievr',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (focusState.hasLiveSession)
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10, right: 12),
                    child: _GlobalFocusPill(
                      isGrace: focusState.status == 'grace',
                      validFocusSeconds: focusState.validFocusSeconds,
                      graceRemainingSeconds:
                          (focusState.graceSecondsAllowed -
                                      focusState.graceSecondsUsed) <
                                  0
                              ? 0
                              : (focusState.graceSecondsAllowed -
                                  focusState.graceSecondsUsed),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      home: const HomeScreen(),
    );
  }
}

class _GlobalFocusPill extends StatelessWidget {
  final bool isGrace;
  final int validFocusSeconds;
  final int graceRemainingSeconds;

  const _GlobalFocusPill({
    required this.isGrace,
    required this.validFocusSeconds,
    required this.graceRemainingSeconds,
  });

  String _formatSeconds(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    final hours = safe ~/ 3600;
    final minutes = (safe % 3600) ~/ 60;
    final seconds = safe % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final color =
        isGrace ? const Color(0xFFFFB300) : const Color(0xFFFF3B30);

    final text = isGrace
        ? 'Grace ${_formatSeconds(graceRemainingSeconds)}'
        : _formatSeconds(validFocusSeconds);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xDD111214),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}