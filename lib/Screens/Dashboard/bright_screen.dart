import 'package:flutter/material.dart';

class BrightScreen extends StatelessWidget {
  const BrightScreen({super.key});

  Widget _buildSectionTitle(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPromptCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFF5F5F5), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF9A9AA3),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputShell() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Ask Bright about your tasks, schedule, habits, or accountability system...',
              style: TextStyle(
                color: Color(0xFF7C7C84),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.arrow_upward_rounded,
              color: Colors.black,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bright',
            style: TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Your execution assistant for tasks, schedule decisions, goal clarity, and accountability guidance.',
            style: TextStyle(
              color: Color(0xFFB3B3BB),
              height: 1.45,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStartSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(
          'Start with Bright',
          subtitle:
              'This can begin as a guided assistant screen before you wire in the full AI flow.',
        ),
        _buildPromptCard(
          icon: Icons.play_arrow_rounded,
          title: 'What should I focus on right now?',
          subtitle:
              'Use Bright as a decision layer when you are not sure what deserves attention first.',
        ),
        const SizedBox(height: 10),
        _buildPromptCard(
          icon: Icons.schedule_outlined,
          title: 'Help me reorganize today',
          subtitle:
              'Ask Bright to reason about your schedule, missed tasks, and execution windows.',
        ),
        const SizedBox(height: 10),
        _buildPromptCard(
          icon: Icons.flag_outlined,
          title: 'Improve one of my goals',
          subtitle:
              'Bright can become the place where goals are refined instead of living as a separate permanent tab.',
        ),
        const SizedBox(height: 10),
        _buildPromptCard(
          icon: Icons.groups_outlined,
          title: 'Explain my accountability setup',
          subtitle:
              'Eventually Bright can answer questions about verifiers, friends, and social progress.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0C),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopCard(),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: _buildQuickStartSection(),
                ),
              ),
              const SizedBox(height: 14),
              _buildInputShell(),
            ],
          ),
        ),
      ),
    );
  }
}