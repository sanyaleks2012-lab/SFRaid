import 'package:flutter/material.dart';

import 'ui/start/start_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const RaidForgeApp());
}

class RaidForgeApp extends StatelessWidget {
  const RaidForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SF2 Raid Forge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
      ),
      builder: (context, child) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: child,
        ),
      ),
      home: const StartScreen(),
    );
  }
}
