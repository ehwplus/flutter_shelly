import 'package:flutter/material.dart';

import 'home_page.dart';

class ShellyExampleApp extends StatelessWidget {
  const ShellyExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    const title = 'Shelly Energy Demo';
    return MaterialApp(
      title: title,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const HomePage(title: title),
    );
  }
}
