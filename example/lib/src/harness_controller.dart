import "dart:async";

import "package:custom_webview_plugin/custom_webview_controller.dart";
import "package:flutter/foundation.dart";

import "recorder.dart";

/// Name of the JavaScript channel the harness installs for its own probes.
const String kHarnessChannel = "HarnessBridge";

/// Phase timings for one load, in milliseconds since the load was requested.
@immutable
class LoadTiming {
  /// Creates a timing record.
  const LoadTiming({
    required this.url,
    this.started,
    this.firstProgress,
    this.progressComplete,
    this.finished,
    this.firstMessage,
    this.error,
  });

  /// URL that was requested.
  final String url;

  /// `onPageStarted`.
  final double? started;

  /// First `onProgress`.
  final double? firstProgress;

  /// First `onProgress` reporting 100.
  final double? progressComplete;

  /// `onPageFinished` or `pageLoaded`, whichever arrived first.
  final double? finished;

  /// First message on any JavaScript channel.
  final double? firstMessage;

  /// `onReceivedError` text, when one arrived.
  final String? error;

  /// Whether the load reached a terminal signal.
  bool get isComplete => finished != null || error != null;
}

/// Wires a [CustomWebViewController]'s callbacks into the recorder and derives load timings.
///
/// Every callback is stamped on arrival. Nothing here changes plugin behaviour — the harness only
/// observes, so a timing it cannot produce is a signal the plugin never delivered the event.
class HarnessController {
  /// Creates a harness around a fresh controller.
  HarnessController() {
    controller
      ..onPageStarted = _onPageStarted
      ..onPageFinished = _onPageFinished
      ..onProgress = _onProgress
      ..onWebResourceError = _onError
      ..onJsAlert = _onJsAlert
      ..onTitleChanged = _onTitleChanged
      ..onJavascriptChannelMessageReceived = _onChannelMessage
      ..onNavigationRequest = _onNavigationRequest;
  }

  /// The controller under test.
  final CustomWebViewController controller = CustomWebViewController();

  final HarnessRecorder _log = HarnessRecorder.instance;

  /// Set false to make [CustomWebViewController.onNavigationRequest] block every navigation.
  bool allowNavigation = true;

  String _url = "";
  double? _started;
  double? _firstProgress;
  double? _progressComplete;
  double? _finished;
  double? _firstMessage;
  String? _error;

  /// Notifies whenever a timing field changes.
  final ValueNotifier<LoadTiming?> timing = ValueNotifier<LoadTiming?>(null);

  void _publish() {
    timing.value = LoadTiming(
      url: _url,
      started: _started,
      firstProgress: _firstProgress,
      progressComplete: _progressComplete,
      finished: _finished,
      firstMessage: _firstMessage,
      error: _error,
    );
  }

  /// Clears timings and restarts the clock, then requests [url].
  Future<void> load(String url, {bool disableCache = false}) async {
    _url = url;
    _started = null;
    _firstProgress = null;
    _progressComplete = null;
    _finished = null;
    _firstMessage = null;
    _error = null;
    _log
      ..reset()
      ..record(EntryKind.action, "loadUrl", url);
    _publish();
    await controller.loadUrl(
      url,
      javaScriptChannelNames: <String>[kHarnessChannel],
      // Default is true, which routes through the native chart branch. Anything being measured
      // wants the plain path, so this is explicit rather than inherited.
      isChart: false,
      disableCache: disableCache,
    );
  }

  double _now() => _log.elapsedMs;

  void _onPageStarted(String url) {
    _log.record(EntryKind.lifecycle, "onPageStarted", url);
    _started ??= _now();
    _publish();
  }

  void _onPageFinished(String url) {
    // Native emits both `onPageFinished` (with a url) and `pageLoaded` (with null arguments, so
    // the url arrives empty); the controller funnels both into this one callback.
    _log.record(EntryKind.lifecycle, "onPageFinished", url.isEmpty ? "<empty url>" : url);
    _finished ??= _now();
    _publish();
  }

  void _onProgress(int progress) {
    _log.record(EntryKind.lifecycle, "onProgress", "$progress%");
    _firstProgress ??= _now();
    if (progress >= 100) _progressComplete ??= _now();
    _publish();
  }

  void _onError(String error) {
    _log.record(EntryKind.error, "onReceivedError", error);
    _error = error;
    _publish();
  }

  void _onJsAlert(String? url, String? message) {
    _log.record(EntryKind.lifecycle, "onJsAlert", "$message @ $url");
  }

  void _onTitleChanged(String title) {
    // Reaching this is itself notable: neither platform emits onTitleChanged today.
    _log.record(EntryKind.defect, "onTitleChanged", "fired unexpectedly: $title");
  }

  void _onChannelMessage(String channel, String message) {
    _log.record(EntryKind.message, "channel:$channel", message);
    _firstMessage ??= _now();
    _publish();
  }

  FutureOr<bool> _onNavigationRequest(String url) {
    _log.record(
      EntryKind.lifecycle,
      "onNavigationRequest",
      "${allowNavigation ? "allow" : "block"} $url",
    );
    return allowNavigation;
  }
}
