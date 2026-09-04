import "package:flutter/material.dart";

import "src/ui/home_screen.dart";

void main() {
  runApp(const HarnessApp());
}

/// Example and diagnostic harness for `custom_webview_plugin`.
class HarnessApp extends StatelessWidget {
  /// Creates the app.
  const HarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "WebView Harness",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E7A72)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
