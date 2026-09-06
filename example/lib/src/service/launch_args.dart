import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

const MethodChannel _channel = MethodChannel("webview_harness/launch");

/// Values the harness can be launched with, so a run needs no rebuild and no typing.
///
///     adb shell am start -n com.custom.webview_harness/.MainActivity \
///       --es xapikey <key> --es clientcode T06794 --es usertype T
@immutable
class LaunchArgs {
  /// Creates a set of launch arguments.
  const LaunchArgs({
    this.xApiKey,
    this.clientCode,
    this.userType,
    this.appId,
    this.autorun = false,
    this.flows,
    this.repeats,
  });

  /// Product key for the flows that need one.
  final String? xApiKey;

  /// Client code to authenticate as.
  final String? clientCode;

  /// User type.
  final String? userType;

  /// Application id.
  final String? appId;

  /// Run headlessly on launch and emit results, with no taps.
  final bool autorun;

  /// Comma-separated flow ids to cover; null means the default single flow.
  final String? flows;

  /// Repeats per arm.
  final int? repeats;

  /// Flow ids to run, or an empty list when unspecified.
  List<String> get flowIds => (flows ?? "")
      .split(",")
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();

  /// Whether anything was supplied.
  bool get isEmpty =>
      xApiKey == null &&
      clientCode == null &&
      userType == null &&
      appId == null &&
      !autorun &&
      flows == null &&
      repeats == null;

  /// Reads the extras the app was launched with.
  ///
  /// Never throws: on a platform without the channel, or a launch with no extras, this returns an
  /// empty set and the UI keeps its defaults.
  static Future<LaunchArgs> read() async {
    try {
      final Map<Object?, Object?>? raw =
          await _channel.invokeMethod<Map<Object?, Object?>>("getLaunchArgs");
      return _parse(raw);
    } on MissingPluginException {
      return const LaunchArgs();
    } on PlatformException {
      return const LaunchArgs();
    }
  }

  /// Registers [onNewLaunch] for relaunches delivered to an already-running instance.
  ///
  /// A `singleTop` relaunch never re-runs [read], so without this a second `am start` carrying
  /// different extras would be silently ignored.
  static void listen(void Function(LaunchArgs) onNewLaunch) {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != "onNewIntent") return null;
      onNewLaunch(_parse(call.arguments as Map<Object?, Object?>?));
      return null;
    });
  }

  static LaunchArgs _parse(Map<Object?, Object?>? raw) {
    if (raw == null) return const LaunchArgs();
    String? get(String key) {
      final Object? v = raw[key];
      final String s = v?.toString().trim() ?? "";
      return s.isEmpty ? null : s;
    }

    final Object? autorunRaw = raw["autorun"];
    return LaunchArgs(
      xApiKey: get("xapikey"),
      clientCode: get("clientcode"),
      userType: get("usertype"),
      appId: get("appid"),
      autorun: autorunRaw is bool ? autorunRaw : autorunRaw?.toString() == "true",
      flows: get("flows"),
      repeats: int.tryParse(get("repeats") ?? ""),
    );
  }
}
