import "package:flutter/foundation.dart";

/// One named combination of plugin toggles, executed N times.
///
/// An arm exists so a measurement is reproducible and comparable. The earlier live-vs-captured
/// comparison was confounded because cold and warm page state leaked in as an uncontrolled
/// variable — whichever ran first paid the cold cost. Making warmth an explicit part of the arm
/// ([resetCacheBeforeEach], [freshViewPerRepeat]) is what stops that recurring.
@immutable
class RunArm {
  /// Creates an arm.
  const RunArm({
    this.name = "default",
    this.disableCache = false,
    this.resetCacheBeforeEach = false,
    this.clearCookiesBeforeEach = false,
    this.zoomEnabled = true,
    this.enableMultipleWindows = true,
    this.userAgent,
    this.repeats = 1,
    this.freshViewPerRepeat = false,
  });

  /// Label shown in results.
  final String name;

  /// Passed to `loadUrl`, setting `WebSettings.cacheMode` to `LOAD_NO_CACHE`.
  ///
  /// **Android only** — iOS never reads this argument, so an iOS A/B on it measures nothing. It is
  /// also sticky: a later load that omits it resets the WebView to `LOAD_DEFAULT`.
  final bool disableCache;

  /// Calls `CustomWebViewPlugin.resetCache()` before each repeat.
  ///
  /// Asymmetric across platforms: iOS clears everything including the HTTP cache and genuinely
  /// awaits completion; Android clears cookies and WebStorage but **not** the HTTP cache, and
  /// returns before removal is guaranteed. To force a cold HTTP fetch on Android use
  /// [disableCache] instead.
  final bool resetCacheBeforeEach;

  /// Calls `CustomWebViewCookieManager.clearCookies()` before each repeat.
  final bool clearCookiesBeforeEach;

  /// Passed explicitly on every load.
  ///
  /// Must be explicit: Dart sends null when omitted and Android's `handleLoadUrl` then defaults it
  /// to **false**, so an omitted value silently disables zoom rather than leaving it alone.
  final bool zoomEnabled;

  /// Passed explicitly on every load, for the same reason as [zoomEnabled].
  ///
  /// Means different things per platform: Android gates real popup creation, iOS only gates
  /// gesture-free `window.open`, and iOS's `loadUrl` ignores it entirely.
  final bool enableMultipleWindows;

  /// Custom user agent, or null for the platform default. The one knob both platforms implement
  /// identically.
  final String? userAgent;

  /// How many times to run each flow under this arm.
  final int repeats;

  /// Tear the platform view down and mount a fresh one between repeats.
  ///
  /// This is the pre-warm decomposition arm. Roughly a second elapses between requesting the first
  /// load and `onPageStarted`, and it is not yet known how much of that is process-level Chromium
  /// initialisation — paid once per process — versus per-WebView creation. If the lead-in collapses
  /// on the second repeat it is the former, and pre-warming this plugin would buy nothing.
  ///
  /// Also exercises the controller's inability to rebind (a controller binds to one platform view
  /// for life), so each repeat needs a fresh controller, not a reused one.
  final bool freshViewPerRepeat;

  /// A copy with the given fields replaced.
  RunArm copyWith({
    String? name,
    bool? disableCache,
    bool? resetCacheBeforeEach,
    bool? clearCookiesBeforeEach,
    bool? zoomEnabled,
    bool? enableMultipleWindows,
    String? userAgent,
    int? repeats,
    bool? freshViewPerRepeat,
  }) =>
      RunArm(
        name: name ?? this.name,
        disableCache: disableCache ?? this.disableCache,
        resetCacheBeforeEach: resetCacheBeforeEach ?? this.resetCacheBeforeEach,
        clearCookiesBeforeEach: clearCookiesBeforeEach ?? this.clearCookiesBeforeEach,
        zoomEnabled: zoomEnabled ?? this.zoomEnabled,
        enableMultipleWindows: enableMultipleWindows ?? this.enableMultipleWindows,
        userAgent: userAgent ?? this.userAgent,
        repeats: repeats ?? this.repeats,
        freshViewPerRepeat: freshViewPerRepeat ?? this.freshViewPerRepeat,
      );

  /// Short description of what differs from defaults, for the results header.
  String get summary {
    final List<String> on = <String>[
      if (disableCache) "no-cache",
      if (resetCacheBeforeEach) "reset",
      if (clearCookiesBeforeEach) "no-cookies",
      if (!zoomEnabled) "zoom off",
      if (!enableMultipleWindows) "multi-window off",
      if (userAgent != null && userAgent!.isNotEmpty) "custom UA",
      if (freshViewPerRepeat) "fresh view",
    ];
    return on.isEmpty ? "defaults" : on.join(" · ");
  }
}
