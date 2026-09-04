import "package:flutter/material.dart";

import "../recorder.dart";

/// The stamped event log, newest last.
class LogTab extends StatelessWidget {
  /// Creates the tab.
  const LogTab({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: HarnessRecorder.instance,
      builder: (BuildContext context, _) {
        final List<LogEntry> entries = HarnessRecorder.instance.entries;
        if (entries.isEmpty) {
          return const Center(child: Text("No events yet — load a URL."));
        }
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: <Widget>[
                  Text("${entries.length} events",
                      style: Theme.of(context).textTheme.labelLarge),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: HarnessRecorder.instance.reset,
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text("Clear"),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int i) {
                  final LogEntry e = entries[i];
                  return ListTile(
                    dense: true,
                    leading: Text(
                      e.elapsedMs.toStringAsFixed(1),
                      style: const TextStyle(fontFamily: "monospace", fontSize: 11),
                    ),
                    title: Text(e.label,
                        style: TextStyle(fontSize: 13, color: _color(context, e.kind))),
                    subtitle: e.detail == null ? null : Text(e.detail!, maxLines: 3),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Color? _color(BuildContext context, EntryKind kind) => switch (kind) {
        EntryKind.error => Theme.of(context).colorScheme.error,
        EntryKind.defect => Colors.orange.shade800,
        EntryKind.message => Theme.of(context).colorScheme.primary,
        EntryKind.action => Theme.of(context).colorScheme.outline,
        EntryKind.lifecycle => null,
      };
}
