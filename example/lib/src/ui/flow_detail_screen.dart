import "package:flutter/material.dart";

import "../config/web_flows.dart";
import "../service/flow_bench.dart";

/// Everything recorded for one measured flow.
///
/// The list rows are deliberately terse, so this is where the evidence lives: the exact URL that
/// was loaded, the API status and body, and the phase breakdown. A failed flow is the common case
/// here — several endpoints answer 404 or 500 for reasons outside the plugin — so the raw body
/// matters as much as the timings.
class FlowDetailScreen extends StatelessWidget {
  /// Creates the screen.
  const FlowDetailScreen({required this.result, super.key});

  /// The measurement.
  final FlowResult result;

  @override
  Widget build(BuildContext context) {
    final WebFlow f = result.flow;
    return Scaffold(
      appBar: AppBar(title: Text(f.label)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _section(context, "Flow"),
          _kv("id", f.id),
          _kv("method", f.method.name.toUpperCase()),
          _kv("host", f.host == FlowHost.superApp ? "SuperApp services" : "Trader API"),
          _kv("path", f.path),
          _kv("arm", result.arm.name),
          if (f.needsApiKey) _kv("needs XApiKey", "yes"),
          if (f.note != null) _kv("note", f.note!),

          const SizedBox(height: 20),
          _section(context, "API leg"),
          if (result.fetch == null)
            _kv("skipped", "captured arm replays a stored URL, so no API call was made")
          else ...<Widget>[
            _kv("status", "${result.fetch!.statusCode}"),
            _kv("connect", _ms(result.fetch!.connectMicros)),
            _kv("ttfb", _ms(result.fetch!.ttfbMicros)),
            _kv("total", _ms(result.fetch!.totalMicros)),
            _kv("bytes", "${result.fetch!.bytes}"),
          ],

          const SizedBox(height: 20),
          _section(context, "Page load"),
          _kv("started", result.pageStartedMs == null
              ? "—"
              : "${result.pageStartedMs!.toStringAsFixed(1)} ms"),
          _kv("finished", result.pageFinishedMs == null
              ? "—"
              : "${result.pageFinishedMs!.toStringAsFixed(1)} ms"),
          _kv("api + page", result.totalMs == null
              ? "—"
              : "${result.totalMs!.toStringAsFixed(1)} ms"),

          if (result.error != null) ...<Widget>[
            const SizedBox(height: 20),
            _section(context, "Failure"),
            SelectableText(result.error!,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error)),
          ],

          if (result.url != null) ...<Widget>[
            const SizedBox(height: 20),
            _section(context, "URL loaded"),
            SelectableText(result.url!,
                style: const TextStyle(fontFamily: "monospace", fontSize: 11)),
          ],

          if (result.fetch != null && result.fetch!.rawBody.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            _section(context, "Raw response"),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(result.fetch!.rawBody,
                  style: const TextStyle(fontFamily: "monospace", fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }

  static String _ms(int? micros) =>
      micros == null ? "—" : "${(micros / 1000).toStringAsFixed(1)} ms";

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1)),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
                width: 110,
                child: Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey))),
            Expanded(
                child: SelectableText(v, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );
}
