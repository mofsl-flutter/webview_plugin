import "package:flutter/material.dart";

import "../config/endpoints.dart";
import "../config/web_flows.dart";
import "../harness_controller.dart";
import "../service/flow_bench.dart";
import "../service/token_api.dart";
import "../service/url_api.dart";
import "flow_detail_screen.dart";
import "flow_picker.dart";

/// Authenticates, runs the flow catalog through both arms, and shows the split.
class AnalysisTab extends StatefulWidget {
  /// Creates the tab.
  const AnalysisTab({required this.harness, super.key});

  /// Shared harness.
  final HarnessController harness;

  @override
  State<AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends State<AnalysisTab> {
  final TextEditingController _client = TextEditingController(text: kDefaultClientCode);
  final TextEditingController _userType = TextEditingController(text: kDefaultUserType);
  final TextEditingController _appId = TextEditingController(text: kDefaultAppId);

  /// Product key for the flows that need one (Refer & Earn). Runtime-entered on purpose: the
  /// app keeps this in a committed .env, and it should not be copied into this repo.
  final TextEditingController _apiKey = TextEditingController(
    // Passed at launch with --dart-define=XAPIKEY=... so the key never has to be typed on the
    // device and never lands in the repo.
    text: const String.fromEnvironment("XAPIKEY"),
  );

  /// Flows a run will cover. Defaults to Refer & Earn, the one flow confirmed working end to end.
  final Set<String> _selected = <String>{"referEarn"};

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
        _status = "Token ok in ${(r.totalMicros / 1000).toStringAsFixed(0)}ms"
            "${c == null ? "" : " · ${c.uniqueName} · aud expires ${c.remaining?.inMinutes}m"}";
        _bench = FlowBench(
          harness: widget.harness,
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
    final List<WebFlow> flows =
        kWebFlows.where((WebFlow f) => _selected.contains(f.id)).toList();
    if (flows.isEmpty) return;
    setState(() => _running = true);
    await bench.run(flows, arm, onProgress: () {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() => _running = false);
  }

  Future<void> _pickFlows() async {
    final Set<String>? picked = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute<Set<String>>(
        builder: (BuildContext _) => FlowPicker(selected: _selected),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selected
        ..clear()
        ..addAll(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<FlowResult> results = _bench?.results ?? <FlowResult>[];
    return Column(
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
                  FilledButton(onPressed: _authenticate, child: const Text("Auth")),
                ],
              ),
              const SizedBox(height: 8),
              _field(_appId, "AppId"),
              const SizedBox(height: 8),
              _field(_apiKey, "XApiKey (Refer & Earn only — optional)"),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_status, style: Theme.of(context).textTheme.bodySmall),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _running ? null : _pickFlows,
                      icon: const Icon(Icons.checklist, size: 18),
                      label: Text(_selected.length == 1
                          ? kWebFlows
                              .firstWhere((WebFlow f) => f.id == _selected.first,
                                  orElse: () => kWebFlows.first)
                              .label
                          : "${_selected.length} flows selected"),
                    ),
                  ),
                ],
              ),
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
                      onPressed: _running || (_bench?.capturedUrls.isEmpty ?? true)
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
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      "Authenticate, then run the live arm to fetch each page URL and load it.\n"
                      "The captured arm replays the same URLs without the API call, so the "
                      "difference is what the URL API costs.",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int i) => _row(results[i]),
                ),
        ),
      ],
    );
  }

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
      title: Text("${r.flow.label}  ·  ${r.arm.name}",
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
