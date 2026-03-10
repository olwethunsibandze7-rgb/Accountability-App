import 'package:flutter/material.dart';

class HabitPanel extends StatelessWidget {
  final List<dynamic> habits;
  final List<dynamic> habitLogs;

  const HabitPanel({super.key, required this.habits, required this.habitLogs});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today\'s Habits',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...habits.map((h) => Text(
                '${h["title"]} - ${h["status"]}',
                style: const TextStyle(color: Colors.white70),
              )),
        ],
      ),
    );
  }
}