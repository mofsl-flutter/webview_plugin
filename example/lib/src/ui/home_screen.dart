import "package:flutter/material.dart";

import "../harness_controller.dart";
import "analysis_tab.dart";
import "audit_tab.dart";
import "browser_tab.dart";
import "log_tab.dart";

/// Shell hosting the three harness tabs over one shared web view.
class HomeScreen extends StatefulWidget {
  /// Creates the shell.
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HarnessController _harness = HarnessController();
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("WebView Harness"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 16, right: 16),
            child: Text(
              "custom_webview_plugin · one controller, one native view",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
      // IndexedStack, not a swap: the controller binds to a platform-view id exactly once and
      // cannot rebind, so unmounting the web view would leave every later call pointing at a
      // destroyed native view. Keeping it mounted is a workaround for that, not a preference.
      body: IndexedStack(
        index: _tab,
        children: <Widget>[
          BrowserTab(harness: _harness),
          AnalysisTab(harness: _harness),
          AuditTab(harness: _harness),
          const LogTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (int i) => setState(() => _tab = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.public), label: "Browser"),
          NavigationDestination(icon: Icon(Icons.speed), label: "Analysis"),
          NavigationDestination(icon: Icon(Icons.rule), label: "Audit"),
          NavigationDestination(icon: Icon(Icons.list_alt), label: "Log"),
        ],
      ),
    );
  }
}
