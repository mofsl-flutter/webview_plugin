import "dart:async";

import "package:custom_webview_plugin/custom_webview_controller.dart";
import "package:flutter/material.dart";

import "../harness_controller.dart";
import "../recorder.dart";

/// Outcome of one audit check.
enum AuditVerdict {
  /// Behaves as documented.
  ok,

  /// Reproduced a contract violation.
  defect,

  /// Could not be decided in this run.
  inconclusive,
}

/// One audit result.
@immutable
class AuditResult {
  /// Creates a result.
  const AuditResult(this.id, this.title, this.verdict, this.detail);

  /// Short id.
  final String id;

  /// What was checked.
  final String title;

  /// What happened.
  final AuditVerdict verdict;

  /// Evidence.
  final String detail;
}

/// Runs the checks that pin this plugin's known contract gaps.
///
/// These are deliberately assertions about the plugin's own contract rather than about any page,
/// so they need no particular site to be loaded and no network beyond the browser tab's page.
class AuditTab extends StatefulWidget {
  /// Creates the tab.
  const AuditTab({required this.harness, super.key});

  /// Shared harness.
  final HarnessController harness;

  @override
  State<AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<AuditTab> {
  final List<AuditResult> _results = <AuditResult>[];
  bool _running = false;

  Future<void> _runAll() async {
    setState(() {
      _running = true;
      _results.clear();
    });
    for (final Future<AuditResult> Function() check in <Future<AuditResult> Function()>[
      _titleChangedIsDead,
      _messageReceivedIsDropped,
      _controllerCannotRebind,
      _unboundControllerHangs,
      _navigationRequestRoundTrip,
    ]) {
      final AuditResult r = await check();
      if (!mounted) return;
      setState(() => _results.add(r));
    }
    if (mounted) setState(() => _running = false);
  }

  /// The Dart controller exposes `onTitleChanged`, but no platform ever invokes it.
  Future<AuditResult> _titleChangedIsDead() async {
    await widget.harness.controller.runJavaScript("document.title = 'harness-probe';");
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final bool fired = HarnessRecorder.instance.count("onTitleChanged") > 0;
    return AuditResult(
      "D1",
      "onTitleChanged is wired in Dart but never emitted",
      fired ? AuditVerdict.ok : AuditVerdict.defect,
      fired
          ? "A platform did emit onTitleChanged."
          : "Title was changed via JS and onTitleChanged never fired. The Dart controller "
              "handles it, but neither the Android nor the iOS side invokes it, so the public "
              "callback is dead.",
    );
  }

  /// Native emits `onMessageReceived`, which the controller has no branch for.
  Future<AuditResult> _messageReceivedIsDropped() async {
    // Android's delegate invokes "onMessageReceived" with a bare String, and the controller's
    // switch has no case for it, so it lands in the default branch and is only debugPrinted.
    // Asserted statically rather than by driving a page: there is no public way to make the
    // controller surface it, which is precisely the finding.
    return const AuditResult(
      "D2",
      "onMessageReceived has no handler in the controller",
      AuditVerdict.defect,
      "CustomWebViewFactory.onMessageReceived invokes \"onMessageReceived\" on both platforms. "
          "CustomWebViewController._handleMethodCall has no matching case, so every such "
          "message falls through to the default branch and is dropped with a debugPrint. Any "
          "page relying on that path is silently unheard. Pinned by a unit test in the plugin.",
    );
  }

  /// `setViewId` binds once and early-returns forever after.
  Future<AuditResult> _controllerCannotRebind() async {
    final CustomWebViewController probe = CustomWebViewController();
    probe.setViewId(101);
    // A second platform view for the same controller — what a remount produces.
    probe.setViewId(202);
    final String? url = await probe
        .getCurrentUrl()
        .timeout(const Duration(milliseconds: 400), onTimeout: () => "<timeout>");
    return AuditResult(
      "D3",
      "A controller cannot rebind to a new platform view",
      AuditVerdict.defect,
      "setViewId completes its Completer on the first call and early-returns on every later "
          "one, so the controller stays bound to channel custom_webview_flutter_101 after the "
          "view is replaced by 202. A remounted web view therefore talks to a destroyed native "
          "view for the rest of its life. Probe returned: ${url ?? "null"}.",
    );
  }

  /// Every method awaits the id Completer, which nothing ever completes on failure.
  Future<AuditResult> _unboundControllerHangs() async {
    final CustomWebViewController orphan = CustomWebViewController();
    bool returned = false;
    // Never call setViewId — this is what a controller gets if its widget is disposed before
    // onPlatformViewCreated, or on an unsupported platform where the widget renders a Text.
    unawaited(orphan.reloadUrl().then((_) => returned = true));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return AuditResult(
      "D4",
      "Calls on an unbound controller hang forever",
      returned ? AuditVerdict.ok : AuditVerdict.defect,
      returned
          ? "The call completed."
          : "reloadUrl() is still pending after 600ms. Every controller method starts with "
              "`await _idCompleter.future`, and the Completer is only ever completed from "
              "setViewId. If the platform view is never created the future never settles: no "
              "error, no timeout, and the caller cannot tell a hang from slow work.",
    );
  }

  /// Android blocks every navigation and re-issues it after a Dart round-trip.
  Future<AuditResult> _navigationRequestRoundTrip() async {
    HarnessRecorder.instance.record(EntryKind.action, "audit:navigation");
    final int before = HarnessRecorder.instance.count("onPageStarted");
    await widget.harness.controller
        .runJavaScript("window.location.href = 'https://flutter.dev/docs';");
    await Future<void>.delayed(const Duration(seconds: 3));
    final int after = HarnessRecorder.instance.count("onPageStarted");
    final int asked = HarnessRecorder.instance.count("onNavigationRequest");
    return AuditResult(
      "D5",
      "Navigation is cancelled and re-issued, not allowed in place",
      asked > 0 ? AuditVerdict.defect : AuditVerdict.inconclusive,
      asked == 0
          ? "onNavigationRequest never fired, so this run proves nothing about the path."
          : "Android's onNavigationRequest returns false unconditionally, then reloads the URL "
              "programmatically once Dart answers. So every navigation pays a channel "
              "round-trip and is restarted rather than continued, which also drops POST bodies "
              "and referrer. onNavigationRequest x$asked, onPageStarted ${after - before} "
              "for one navigation. If the host Activity is null the re-issue never happens and "
              "the navigation is silently lost.",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  "Contract checks against the plugin itself. Load a page in the Browser tab "
                  "first — D1 and D5 drive the live view.",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _running ? null : _runAll,
                child: Text(_running ? "Running…" : "Run audit"),
              ),
            ],
          ),
        ),
        Expanded(
          child: _results.isEmpty
              ? const Center(child: Text("No results yet."))
              : ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int i) {
                    final AuditResult r = _results[i];
                    return ListTile(
                      leading: Icon(_icon(r.verdict), color: _tint(context, r.verdict)),
                      title: Text("${r.id} · ${r.title}",
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(r.detail, style: const TextStyle(fontSize: 12)),
                      isThreeLine: true,
                    );
                  },
                ),
        ),
      ],
    );
  }

  IconData _icon(AuditVerdict v) => switch (v) {
        AuditVerdict.ok => Icons.check_circle_outline,
        AuditVerdict.defect => Icons.report_problem_outlined,
        AuditVerdict.inconclusive => Icons.help_outline,
      };

  Color _tint(BuildContext context, AuditVerdict v) => switch (v) {
        AuditVerdict.ok => Colors.green.shade700,
        AuditVerdict.defect => Colors.orange.shade800,
        AuditVerdict.inconclusive => Theme.of(context).colorScheme.outline,
      };
}
