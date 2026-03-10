import 'package:flutter/material.dart';

class HeroSection extends StatelessWidget {
  final List<dynamic> goals;
  final List<dynamic> habits;

  const HeroSection({
    super.key,
    required this.goals,
    required this.habits,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting
          Text(
            "Good Morning!",
            style: TextStyle(
              fontSize: screenWidth * 0.06, // responsive font
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),

          // Focus Summary
          Text(
            "Today you have ${habits.length} habits to complete",
            style: TextStyle(
              fontSize: screenWidth * 0.04,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 20),

          // Top Goals Horizontal List
          SizedBox(
            height: 130,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: goals.length,
              itemBuilder: (context, index) {
                final goal = goals[index];
                return Container(
                  width: 180,
                  margin: const EdgeInsets.only(right: 15),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal['title'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: (goal['progress'] ?? 0) / 100,
                        color: Colors.greenAccent,
                        backgroundColor: Colors.white12,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        "${goal['progress']}% complete",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}