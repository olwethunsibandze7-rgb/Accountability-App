import 'package:flutter/material.dart';

class VerificationPanel extends StatelessWidget {
  final List<dynamic> verifications;

  const VerificationPanel({super.key, required this.verifications});

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
            'Pending Verifications',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...verifications.map((v) => Text(
                '${v["habit"]} - ${v["status"]}',
                style: const TextStyle(color: Colors.white70),
              )),
        ],
      ),
    );
  }
}