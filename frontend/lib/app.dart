import 'package:flutter/material.dart';

import 'screens/splash_gate.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: "Ankit's Agent",
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF111816),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFC7F06C),
            onPrimary: Color(0xFF172010),
            secondary: Color(0xFF84DCC6),
            surface: Color(0xFF1B2622),
            onSurface: Color(0xFFF1F4EC),
            error: Color(0xFFFFB4AB),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF202C27),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          ),
        ),
        home: const SplashGate(),
      );
}
