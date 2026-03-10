import 'package:flutter/material.dart';

class CompliancePanel extends StatelessWidget {
  final List<dynamic> habitLogs;

  const CompliancePanel({super.key, required this.habitLogs});

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
            'Compliance Overview',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Completed: ${habitLogs.where((h) => h["status"] == "done").length} / ${habitLogs.length}',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}