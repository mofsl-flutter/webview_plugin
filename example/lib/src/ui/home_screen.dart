import "package:flutter/material.dart";

import "../harness_controller.dart";
import "../service/autorun.dart";
import "../service/launch_args.dart";
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
  HarnessController _harness = HarnessController();
  int _tab = 0;
  bool _viewMounted = true;
  int _viewGeneration = 0;

  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame: autorun drives the web view, and the platform view does
    // not exist until this tree has been laid out once. Starting earlier means every call waits
    // on a controller whose view was never created — which never completes, and never errors.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutorun());
  }

  Future<void> _maybeAutorun() async {
    final LaunchArgs args = await LaunchArgs.read();
    if (!args.autorun || !mounted) return;
    // Give the platform view a moment to report creation before the first load.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    await Autorun(
      harnessOf: () => _harness,
      remountView: _remountView,
    ).run(args);
  }

  /// Tears the platform view down and mounts a fresh one, with a fresh controller.
  ///
  /// Both halves are required. Unmounting alone would leave the old controller bound to a
  /// destroyed native view, because setViewId completes once and early-returns on every later
  /// call — so the new view would simply be ignored.
  Future<void> _remountView() async {
    setState(() => _viewMounted = false);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() {
      _harness = HarnessController();
      _viewGeneration++;
      _viewMounted = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

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
          BrowserTab(
            key: ValueKey<int>(_viewGeneration),
            harness: _harness,
            viewMounted: _viewMounted,
          ),
          AnalysisTab(
            harness: _harness,
            harnessOf: () => _harness,
            onRemountView: _remountView,
          ),
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
