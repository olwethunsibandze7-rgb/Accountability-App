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
        await Supabase.instance.client.from('profiles').update({
          'onboarding_step': 1,
        }).eq('id', user.id);
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

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: const Color(0xFFF5F5F5),
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFFB3B3BB),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFF5F5F5),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Text(
                'Build your accountability system.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFF5F5F5),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'You will choose 2 essential goal areas, define them clearly, and receive fixed habits with locked verification rules.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Color(0xFFB3B3BB),
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildStepChip('Choose 2 goals'),
                  _buildStepChip('Define why'),
                  _buildStepChip('Set constraints'),
                  _buildStepChip('Review schedule'),
                ],
              ),
              const SizedBox(height: 24),
              _buildInfoCard(
                icon: Icons.track_changes_outlined,
                title: 'Template-based goals',
                body:
                    'You will pick from core life goals like fitness, study, work, sleep, finance, and relationships.',
              ),
              const SizedBox(height: 12),
              _buildInfoCard(
                icon: Icons.verified_outlined,
                title: 'Locked verification rules',
                body:
                    'Habits come with fixed accountability rules such as focus mode, partner review, or location-gated verification.',
              ),
              const SizedBox(height: 12),
              _buildInfoCard(
                icon: Icons.schedule_outlined,
                title: 'Structured execution',
                body:
                    'You will block unavailable time, generate a weekly structure, and begin tracking immediately after setup.',
              ),
              const Spacer(),
              PrimaryButton(
                text: 'Begin Setup',
                onPressed: () => _beginSelection(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}