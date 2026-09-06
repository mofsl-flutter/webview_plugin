import "package:flutter/material.dart";

import "../config/web_flows.dart";

/// Lets a run target one flow, or any subset, instead of the whole catalog.
///
/// Running all 45 takes minutes and most rows fail for account reasons, which buries the flow you
/// actually care about. Selecting is the normal case, not the exception.
class FlowPicker extends StatefulWidget {
  /// Creates the picker.
  const FlowPicker({required this.selected, super.key});

  /// Ids currently selected.
  final Set<String> selected;

  @override
  State<FlowPicker> createState() => _FlowPickerState();
}

class _FlowPickerState extends State<FlowPicker> {
  late final Set<String> _sel = <String>{...widget.selected};
  String _query = "";

  @override
  Widget build(BuildContext context) {
    final List<WebFlow> shown = kWebFlows
        .where((WebFlow f) =>
            _query.isEmpty ||
            f.label.toLowerCase().contains(_query) ||
            f.id.toLowerCase().contains(_query) ||
            f.path.toLowerCase().contains(_query))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text("Select flows (${_sel.length})"),
        actions: <Widget>[
          TextButton(
            onPressed: () => setState(() => _sel
              ..clear()
              ..addAll(kWebFlows.map((WebFlow f) => f.id))),
            child: const Text("All"),
          ),
          TextButton(
            onPressed: () => setState(_sel.clear),
            child: const Text("None"),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                labelText: "Filter",
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                border: OutlineInputBorder(),
              ),
              onChanged: (String v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (BuildContext context, int i) {
                final WebFlow f = shown[i];
                return CheckboxListTile(
                  dense: true,
                  value: _sel.contains(f.id),
                  onChanged: (bool? v) => setState(() {
                    if (v ?? false) {
                      _sel.add(f.id);
                    } else {
                      _sel.remove(f.id);
                    }
                  }),
                  title: Text(f.label, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    "${f.method.name.toUpperCase()}  ${f.path}",
                    style: const TextStyle(fontFamily: "monospace", fontSize: 10),
                  ),
                  secondary: f.needsApiKey
                      ? const Tooltip(message: "Needs XApiKey", child: Icon(Icons.key, size: 16))
                      : null,
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pop(_sel),
        icon: const Icon(Icons.check),
        label: Text("Use ${_sel.length}"),
      ),
    );
  }
}
