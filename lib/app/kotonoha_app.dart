import 'package:flutter/material.dart';

import '../screens/home_screen.dart';

class KotonohaApp extends StatelessWidget {
  const KotonohaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KOTONOHA',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4C7A3D)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
