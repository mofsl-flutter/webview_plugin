import "package:custom_webview_plugin/custom_webview_plugin.dart";
import "package:flutter/material.dart";

import "../harness_controller.dart";
import "../recorder.dart";

/// A live web view plus every operation the controller exposes.
class BrowserTab extends StatefulWidget {
  /// Creates the tab.
  const BrowserTab({required this.harness, super.key});

  /// Shared harness.
  final HarnessController harness;

  @override
  State<BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends State<BrowserTab> {
  final TextEditingController _url =
      TextEditingController(text: "https://flutter.dev");
  final TextEditingController _script =
      TextEditingController(text: "document.title");
  String _result = "";
  bool _interactionEnabled = true;

  Future<void> _run(String label, Future<Object?> Function() op) async {
    HarnessRecorder.instance.record(EntryKind.action, label);
    try {
      final Object? value = await op();
      if (!mounted) return;
      setState(() => _result = "$label -> ${value ?? "ok"}");
    } catch (e) {
      if (!mounted) return;
      setState(() => _result = "$label threw: $e");
      HarnessRecorder.instance.record(EntryKind.error, "$label threw", "$e");
    }
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
                child: TextField(
                  controller: _url,
                  decoration: const InputDecoration(
                    labelText: "URL",
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _run("load", () => widget.harness.load(_url.text)),
                child: const Text("Load"),
              ),
            ],
          ),
        ),
        _TimingStrip(harness: widget.harness),
        Expanded(
          child: Stack(
            children: <Widget>[
              CustomWebViewWidget(
                controller: widget.harness.controller,
                javascriptChannelNames: const <String>[kHarnessChannel],
                // Explicit: the widget defaults isChart to true, which takes a different native
                // branch. Nothing here is a chart.
                isChart: false,
              ),
            ],
          ),
        ),
        if (_result.isNotEmpty)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(8),
            child: Text(_result, style: const TextStyle(fontFamily: "monospace", fontSize: 11)),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: <Widget>[
              _chip("reload", () => widget.harness.controller.reloadUrl()),
              _chip("canGoBack", () => widget.harness.controller.canGoBack()),
              _chip("goBack", () => widget.harness.controller.goBack()),
              _chip("currentUrl", () => widget.harness.controller.getCurrentUrl()),
              _chip("resetCache", CustomWebViewPlugin.resetCache),
              _chip(
                _interactionEnabled ? "lock touch" : "unlock touch",
                () {
                  _interactionEnabled = !_interactionEnabled;
                  return widget.harness.controller
                      .setUserInteractionEnabled(_interactionEnabled);
                },
              ),
              _chip(
                "userAgent",
                () => widget.harness.controller.setCustomUserAgent("HarnessUA/1.0"),
              ),
              _chip(
                "loadHtml",
                () => widget.harness.controller.loadHtmlData(
                  "<h2>Loaded from loadHtmlData</h2>"
                  "<button onclick=\"$kHarnessChannel.postMessage('tapped')\">post</button>",
                  javaScriptChannelNames: const <String>[kHarnessChannel],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _script,
                  decoration: const InputDecoration(
                    labelText: "JavaScript",
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _run(
                  "runJavaScript",
                  () => widget.harness.controller.runJavaScript(_script.text),
                ),
                child: const Text("Run"),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, Future<Object?> Function() op) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ActionChip(label: Text(label), onPressed: () => _run(label, op)),
      );
}

class _TimingStrip extends StatelessWidget {
  const _TimingStrip({required this.harness});

  final HarnessController harness;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LoadTiming?>(
      valueListenable: harness.timing,
      builder: (BuildContext context, LoadTiming? t, _) {
        if (t == null) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            _format(t),
            style: const TextStyle(fontFamily: "monospace", fontSize: 11),
          ),
        );
      },
    );
  }

  String _format(LoadTiming t) {
    String ms(double? v) => v == null ? "—" : "${v.toStringAsFixed(1)}ms";
    return "started ${ms(t.started)} · progress ${ms(t.firstProgress)} · "
        "100% ${ms(t.progressComplete)} · finished ${ms(t.finished)} · "
        "firstMsg ${ms(t.firstMessage)}${t.error == null ? "" : " · ERROR ${t.error}"}";
  }
}
