import "dart:async";

import "../config/web_flows.dart";
import "../harness_controller.dart";
import "../recorder.dart";
import "url_api.dart";

/// Which arm produced a measurement.
enum BenchArm {
  /// Fetch the URL from its API, then load it. The real user cost.
  live,

  /// Load a URL captured earlier, skipping the API. Page cost only.
  captured,
}

/// One measured flow.
class FlowResult {
  /// Creates a result.
  FlowResult({
    required this.flow,
    required this.arm,
    this.fetch,
    this.pageStartedMs,
    this.pageFinishedMs,
    this.url,
    this.error,
  });

  /// Which flow.
  final WebFlow flow;

  /// Which arm.
  final BenchArm arm;

  /// API leg, when [arm] is [BenchArm.live].
  final UrlFetch? fetch;

  /// Page load phases, milliseconds from the load request.
  final double? pageStartedMs;

  /// When the page reported finished.
  final double? pageFinishedMs;

  /// URL that was loaded.
  final String? url;

  /// Why this flow produced no page timing.
  final String? error;

  /// API leg duration, 0 for the captured arm.
  double get apiMs => fetch?.totalMs ?? 0;

  /// Page load duration.
  double? get pageMs => pageFinishedMs;

  /// API + page, the number a user actually waits.
  double? get totalMs => pageFinishedMs == null ? null : apiMs + pageFinishedMs!;

  /// Whether anything usable was measured.
  bool get ok => pageFinishedMs != null;
}

/// Runs each flow through both arms and records the split between API and page cost.
///
/// The point of two arms is that a slow flow has two possible causes and they need different
/// fixes: the URL API being slow, or the page itself being slow. One number cannot tell them
/// apart, so this measures the API leg separately and replays the same URL without it.
class FlowBench {
  /// Creates a bench.
  FlowBench({required this.harness, required this.api});

  /// Drives the web view and stamps its callbacks.
  final HarnessController harness;

  /// URL API client.
  final UrlApi api;

  /// URLs captured by the live arm, keyed by flow id, so the captured arm can replay them.
  final Map<String, String> capturedUrls = <String, String>{};

  /// Results, newest last.
  final List<FlowResult> results = <FlowResult>[];

  bool _cancelled = false;

  /// Stops a run after the current flow.
  void cancel() => _cancelled = true;

  /// Runs [flows] through [arm].
  ///
  /// [perFlowTimeout] is not optional in spirit: a controller whose platform view was never
  /// created never completes any call, so without a timeout one bad flow stalls the whole batch
  /// with no error. See defect D4.
  Future<void> run(
    List<WebFlow> flows,
    BenchArm arm, {
    Duration perFlowTimeout = const Duration(seconds: 25),
    void Function()? onProgress,
  }) async {
    _cancelled = false;
    for (final WebFlow flow in flows) {
      if (_cancelled) return;
      final FlowResult r = await _runOne(flow, arm, perFlowTimeout);
      results.add(r);
      onProgress?.call();
    }
  }

  Future<FlowResult> _runOne(WebFlow flow, BenchArm arm, Duration timeout) async {
    String? url;
    UrlFetch? fetch;

    if (arm == BenchArm.live) {
      fetch = await api.fetch(flow);
      if (!fetch.ok) {
        return FlowResult(
          flow: flow,
          arm: arm,
          fetch: fetch,
          error: "${fetch.error} — ${_snippet(fetch.rawBody)}",
        );
      }
      url = fetch.url;
      capturedUrls[flow.id] = url!;
    } else {
      url = capturedUrls[flow.id];
      if (url == null) {
        return FlowResult(
          flow: flow,
          arm: arm,
          error: "No captured URL. Run the live arm first, or paste one in.",
        );
      }
    }

    final Completer<void> finished = Completer<void>();
    void watch() {
      if (!finished.isCompleted &&
          (harness.timing.value?.finished != null ||
              harness.timing.value?.error != null)) {
        finished.complete();
      }
    }

    harness.timing.addListener(watch);
    try {
      await harness.load(url);
      await finished.future.timeout(timeout);
    } on TimeoutException {
      return FlowResult(
        flow: flow,
        arm: arm,
        fetch: fetch,
        url: url,
        error: "No terminal signal within ${timeout.inSeconds}s",
      );
    } finally {
      harness.timing.removeListener(watch);
    }

    final LoadTiming? t = harness.timing.value;
    HarnessRecorder.instance.record(
      EntryKind.action,
      "bench:${flow.id}:${arm.name}",
      "api ${fetch?.totalMs.toStringAsFixed(1) ?? "-"}ms page ${t?.finished?.toStringAsFixed(1) ?? "-"}ms",
    );
    return FlowResult(
      flow: flow,
      arm: arm,
      fetch: fetch,
      url: url,
      pageStartedMs: t?.started,
      pageFinishedMs: t?.finished,
      error: t?.error,
    );
  }

  static String _snippet(String body) =>
      body.length <= 80 ? body : "${body.substring(0, 80)}…";
}
