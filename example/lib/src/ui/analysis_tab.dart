import "package:flutter/material.dart";

import "../config/endpoints.dart";
import "../config/web_flows.dart";
import "../harness_controller.dart";
import "../model/run_arm.dart";
import "../service/flow_bench.dart";
import "../service/token_api.dart";
import "../service/url_api.dart";
import "flow_detail_screen.dart";
import "flow_picker.dart";

/// Authenticates, runs the flow catalog through both arms, and shows the split.
class AnalysisTab extends StatefulWidget {
  /// Creates the tab.
  const AnalysisTab({
    required this.harness,
    required this.harnessOf,
    this.onRemountView,
    super.key,
  });

  /// Shared harness.
  final HarnessController harness;

  /// Resolves the live harness, which the fresh-view arm replaces between repeats.
  final HarnessController Function() harnessOf;

  /// Tears the platform view down and mounts a fresh one, for the fresh-view arm.
  final Future<void> Function()? onRemountView;

  @override
  State<AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends State<AnalysisTab> {
  final TextEditingController _client = TextEditingController(
    text: kDefaultClientCode,
  );
  final TextEditingController _userType = TextEditingController(
    text: kDefaultUserType,
  );
  final TextEditingController _appId = TextEditingController(
    text: kDefaultAppId,
  );

  /// Product key for the flows that need one (Refer & Earn). Runtime-entered on purpose: the
  /// app keeps this in a committed .env, and it should not be copied into this repo.
  final TextEditingController _apiKey = TextEditingController(
    // Passed at launch with --dart-define=XAPIKEY=... so the key never has to be typed on the
    // device and never lands in the repo.
    text: const String.fromEnvironment("XAPIKEY"),
  );

  /// Flows a run will cover. Defaults to Refer & Earn, the one flow confirmed working end to end.
  final Set<String> _selected = <String>{"referEarn"};

  /// Toggle combination the next run uses.
  RunArm _arm = const RunArm();
  bool _togglesOpen = false;
  final TextEditingController _ua = TextEditingController();

  String _status = "Not authenticated.";
  String? _token;
  FlowBench? _bench;
  bool _running = false;

  Future<void> _authenticate() async {
    setState(() => _status = "Requesting token…");
    final TokenResult r = await TokenApi().fetch(
      clientCode: _client.text.trim(),
      userType: _userType.text.trim(),
      appId: _appId.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _token = r.token;
        final JwtClaims? c = JwtClaims.decode(r.token!);
        _status =
            "Token ok in ${(r.totalMicros / 1000).toStringAsFixed(0)}ms"
            "${c == null ? "" : " · ${c.uniqueName} · aud expires ${c.remaining?.inMinutes}m"}";
        _bench = FlowBench(
          harnessOf: widget.harnessOf,
          api: UrlApi(
            token: r.token!,
            appId: _appId.text.trim(),
            apiKey: _apiKey.text.trim(),
          ),
        );
      } else {
        _token = null;
        _status = "Auth failed: ${r.error} — ${r.rawBody}";
      }
    });
  }

  Future<void> _run(BenchArm arm) async {
    final FlowBench? bench = _bench;
    if (bench == null) return;
    final List<WebFlow> flows = kWebFlows
        .where((WebFlow f) => _selected.contains(f.id))
        .toList();
    if (flows.isEmpty) return;
    setState(() => _running = true);
    await bench.run(
      flows,
      arm,
      runArm: _arm.copyWith(userAgent: _ua.text.trim()),
      remountView: widget.onRemountView,
      onProgress: () {
        if (mounted) setState(() {});
      },
    );
    if (mounted) setState(() => _running = false);
  }

  Future<void> _pickFlows() async {
    final Set<String>? picked = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute<Set<String>>(
        builder: (BuildContext _) => FlowPicker(selected: _selected),
      ),
    );
    if (picked != null && mounted) {
      setState(
        () => _selected
          ..clear()
          ..addAll(picked),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<FlowResult> results = _bench?.results ?? <FlowResult>[];
    // One scroll view for the whole tab, header and results together.
    //
    // A Column of Flexible header + Expanded results does not work here: expanding the arm panel
    // makes the header taller than its share, and the two children split the space regardless of
    // need — first overflowing, then clipping the panel while an empty results area sat below it.
    // Making the page itself scroll means expanding simply makes it longer.
    return ListView(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: _field(_client, "Client code")),
                  const SizedBox(width: 8),
                  SizedBox(width: 90, child: _field(_userType, "User type")),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _authenticate,
                    child: const Text("Auth"),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _field(_appId, "AppId"),
              const SizedBox(height: 8),
              _field(_apiKey, "XApiKey (Refer & Earn only — optional)"),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _status,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _running ? null : _pickFlows,
                      icon: const Icon(Icons.checklist, size: 18),
                      label: Text(
                        _selected.length == 1
                            ? kWebFlows
                                  .firstWhere(
                                    (WebFlow f) => f.id == _selected.first,
                                    orElse: () => kWebFlows.first,
                                  )
                                  .label
                            : "${_selected.length} flows selected",
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _toggles(),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _token == null || _running
                          ? null
                          : () => _run(BenchArm.live),
                      child: const Text("Run live (API + page)"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _running || (_bench?.capturedUrls.isEmpty ?? true)
                          ? null
                          : () => _run(BenchArm.captured),
                      child: const Text("Run captured (page only)"),
                    ),
                  ),
                  if (_running) ...<Widget>[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _bench?.cancel,
                      icon: const Icon(Icons.stop_circle_outlined),
                      tooltip: "Stop",
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "Authenticate, pick an arm, then run. The live arm fetches each page URL and "
              "loads it; the captured arm replays the same URL without the API call.\n\n"
              "Note the two arms also differ in page warmth, so their difference is not the "
              "API cost — the API leg is reported directly in each row.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          for (final FlowResult r in results) ...<Widget>[
            _row(r),
            const Divider(height: 1),
          ],
      ],
    );
  }

  Widget _toggles() => Card(
    margin: EdgeInsets.zero,
    child: ExpansionTile(
      initiallyExpanded: _togglesOpen,
      onExpansionChanged: (bool v) => setState(() => _togglesOpen = v),
      title: Text(
        "Arm: ${_arm.summary}",
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        "${_arm.repeats} repeat${_arm.repeats == 1 ? "" : "s"}",
        style: const TextStyle(fontSize: 11),
      ),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
      children: <Widget>[
        _sw(
          "Disable cache on load",
          "Android only — iOS ignores this argument entirely",
          _arm.disableCache,
          (bool v) => _arm = _arm.copyWith(disableCache: v),
        ),
        _sw(
          "Reset cache before each repeat",
          "Asymmetric: iOS clears the HTTP cache, Android clears only cookies + WebStorage",
          _arm.resetCacheBeforeEach,
          (bool v) => _arm = _arm.copyWith(resetCacheBeforeEach: v),
        ),
        _sw(
          "Clear cookies before each repeat",
          "Clear-all only; no per-domain control",
          _arm.clearCookiesBeforeEach,
          (bool v) => _arm = _arm.copyWith(clearCookiesBeforeEach: v),
        ),
        _sw(
          "Zoom enabled",
          "iOS is one-way: once disabled it cannot be re-enabled on that view",
          _arm.zoomEnabled,
          (bool v) => _arm = _arm.copyWith(zoomEnabled: v),
        ),
        _sw(
          "Multiple windows",
          "Means different things per platform; iOS drops it on loadUrl",
          _arm.enableMultipleWindows,
          (bool v) => _arm = _arm.copyWith(enableMultipleWindows: v),
        ),
        _sw(
          "Fresh platform view per repeat",
          "Decomposes the ~1s pre-page lead-in: does it collapse on repeat 2?",
          _arm.freshViewPerRepeat,
          (bool v) => _arm = _arm.copyWith(freshViewPerRepeat: v),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _field(_ua, "Custom user agent (blank = default)"),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: TextFormField(
                  initialValue: "${_arm.repeats}",
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Repeats",
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (String v) => setState(
                    () => _arm = _arm.copyWith(repeats: int.tryParse(v) ?? 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _sw(
    String title,
    String subtitle,
    bool value,
    void Function(bool) apply,
  ) => SwitchListTile(
    dense: true,
    value: value,
    onChanged: _running ? null : (bool v) => setState(() => apply(v)),
    title: Text(title, style: const TextStyle(fontSize: 13)),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
  );

  Widget _field(TextEditingController c, String label) => TextField(
    controller: c,
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(),
    ),
    style: const TextStyle(fontSize: 12),
  );

  Widget _row(FlowResult r) {
    void open() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => FlowDetailScreen(result: r),
      ),
    );
    String ms(double? v) => v == null ? "—" : "${v.toStringAsFixed(0)}ms";
    final bool failed = !r.ok;
    return ListTile(
      dense: true,
      onTap: open,
      trailing: const Icon(Icons.chevron_right, size: 18),
      leading: Icon(
        failed ? Icons.error_outline : Icons.check_circle_outline,
        size: 18,
        color: failed
            ? Theme.of(context).colorScheme.error
            : Colors.green.shade700,
      ),
      title: Text(
        "${r.flow.label}  ·  ${r.arm.name}"
        "${r.runArm.repeats > 1 ? "  #${r.repeat + 1}" : ""}",
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        failed
            ? (r.error ?? "failed")
            : "api ${ms(r.fetch?.totalMs)} · page ${ms(r.pageMs)} · total ${ms(r.totalMs)}"
                  "${r.fetch == null ? "" : " · ${r.fetch!.statusCode}"}",
        style: const TextStyle(fontFamily: "monospace", fontSize: 11),
      ),
      isThreeLine: failed,
    );
  }
}
