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

class AchievrApp extends StatelessWidget {
  const AchievrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Achievr',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}