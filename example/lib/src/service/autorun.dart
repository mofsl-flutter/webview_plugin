import "package:flutter/foundation.dart";

import "../config/endpoints.dart";
import "../config/web_flows.dart";
import "../harness_controller.dart";
import "../model/run_arm.dart";
import "flow_bench.dart";
import "launch_args.dart";
import "token_api.dart";
import "url_api.dart";

/// Tag every result line carries, so `adb logcat` can filter for them.
const String kResultTag = "HARNESSRESULT";

/// Runs the cache A/B headlessly and emits one line per measurement.
///
/// Emitted with [debugPrintSynchronously] rather than `debugPrint`: the latter throttles at about
/// 1 KB/s and silently drops and reorders lines, which quietly loses results in a long run.
///
/// Collect with:
///
///     adb logcat -c && adb shell am start -n com.custom.webview_harness/.MainActivity \
///       --es xapikey <key> --ez autorun true --ei repeats 5
///     adb logcat -d | grep HARNESSRESULT
class Autorun {
  /// Creates a runner.
  Autorun({required this.harnessOf, required this.remountView});

  /// Resolves the live harness.
  final HarnessController Function() harnessOf;

  /// Rebuilds the platform view, for arms that need a fresh one.
  final Future<void> Function() remountView;

  /// Authenticates, then runs each arm over the selected flows.
  ///
  /// The two arms are the cache A/B: identical except that one disables the HTTP cache on every
  /// load and clears storage between repeats, so the pair separates "page is genuinely slow" from
  /// "page was served warm". Running both in one launch matters — run separately, whichever went
  /// first pays the cold cost and the comparison is meaningless.
  Future<void> run(LaunchArgs args) async {
    final int repeats = args.repeats ?? 3;
    final List<String> wanted = args.flowIds.isEmpty
        ? <String>["referEarn"]
        : args.flowIds;
    final List<WebFlow> flows = kWebFlows
        .where((WebFlow f) => wanted.contains(f.id))
        .toList();

    _emit("start", "flows=${wanted.join("|")} repeats=$repeats");

    final TokenResult token = await TokenApi().fetch(
      clientCode: args.clientCode ?? kDefaultClientCode,
      userType: args.userType ?? kDefaultUserType,
      appId: args.appId ?? kDefaultAppId,
    );
    if (!token.ok) {
      _emit("auth", "FAILED ${token.error} ${token.rawBody}");
      _emit("__DONE__", "0 measurements");
      return;
    }
    _emit("auth", "ok ${(token.totalMicros / 1000).toStringAsFixed(0)}ms");

    final FlowBench bench = FlowBench(
      harnessOf: harnessOf,
      api: UrlApi(
        token: token.token!,
        appId: args.appId ?? kDefaultAppId,
        apiKey: args.xApiKey ?? "",
      ),
    );

    final List<RunArm> arms = <RunArm>[
      RunArm(name: "cache-on", repeats: repeats),
      RunArm(
        name: "cache-off",
        disableCache: true,
        resetCacheBeforeEach: true,
        clearCookiesBeforeEach: true,
        repeats: repeats,
      ),
    ];

    // Interleaved (A,B,A,B,...), not blocked (AAA,BBB).
    //
    // Blocking them looks tidier and is wrong: the second arm runs later, so anything that drifts
    // with time lands entirely on it. A blocked run of this exact A/B showed cache-off with a
    // *lower* page median than cache-on, which is backwards — the giveaway was the API leg, which
    // disableCache cannot touch at all, drifting from a 199 ms mean connect in the first half to
    // 450 ms in the second. Interleaving spreads that drift across both arms instead.
    int measured = 0;
    for (int cycle = 0; cycle < repeats; cycle++) {
      for (final RunArm arm in arms) {
        final int before = bench.results.length;
        await bench.run(
          flows,
          BenchArm.live,
          runArm: arm.copyWith(repeats: 1),
          remountView: remountView,
        );
        for (final FlowResult r in bench.results.skip(before)) {
          _emitResult(arm, r, cycle);
          measured++;
        }
      }
    }
    _emit("__DONE__", "$measured measurements");
  }

  void _emitResult(RunArm arm, FlowResult r, int cycle) {
    String ms(double? v) => v == null ? "-" : v.toStringAsFixed(1);
    debugPrintSynchronously(
      "$kResultTag\t${r.flow.id}\t${arm.name}\t${cycle + 1}"
      "\tapi=${ms(r.fetch?.totalMs)}"
      "\tconnect=${r.fetch?.connectMicros == null ? "-" : (r.fetch!.connectMicros! / 1000).toStringAsFixed(1)}"
      "\tpage=${ms(r.pageMs)}"
      "\ttotal=${ms(r.totalMs)}"
      "\tstatus=${r.fetch?.statusCode ?? "-"}"
      "\tok=${r.ok}"
      "\tnav=${r.navProbe ?? "-"}"
      "\tstarts=${r.startCount}\tfinishes=${r.finishCount}"
      "${r.error == null ? "" : "\terr=${r.error}"}",
    );
  }

  void _emit(String label, String detail) =>
      debugPrintSynchronously("$kResultTag\t$label\t$detail");
}
