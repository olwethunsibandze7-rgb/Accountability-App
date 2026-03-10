import 'package:flutter/material.dart';

class FocusMode extends StatelessWidget {
  final List<dynamic> habits;

  const FocusMode({super.key, required this.habits});

  @override
  Widget build(BuildContext context) {
    // your focus mode UI here
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Center(
        child: Text('Focus Mode Active', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}