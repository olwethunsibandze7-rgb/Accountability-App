import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../Widgets/primary_button.dart';
import 'goal_selection_screen.dart';

class GoalSetupIntroScreen extends StatelessWidget {
  const GoalSetupIntroScreen({super.key});

  Future<void> _beginSelection(BuildContext context) async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user != null) {
      try {
        await Supabase.instance.client
            .from('profiles')
            .update({
              'onboarding_step': 1,
            })
            .eq('id', user.id);
      } catch (e) {
        debugPrint('Error updating onboarding step: $e');
      }
    }

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const GoalSelectionScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'You will define 2 goals.\n\n'
                'These goals will be enforced.\n'
                'Failure will be recorded.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  height: 1.5,
                  color: Color(0xFFF5F5F5),
                ),
              ),
              const SizedBox(height: 48),
              PrimaryButton(
                text: 'Begin Selection',
                onPressed: () => _beginSelection(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}