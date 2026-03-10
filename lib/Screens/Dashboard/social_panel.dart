import 'package:flutter/material.dart';

class SocialPanel extends StatelessWidget {
  final List<dynamic> partnerships;
  final List<dynamic> goals;

  const SocialPanel({super.key, required this.partnerships, required this.goals});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Social Accountability',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...partnerships.map((p) => Text(
                '${p["partner"]} is tracking "${p["goal"]}"',
                style: const TextStyle(color: Colors.white70),
              )),
        ],
      ),
    );
  }
}