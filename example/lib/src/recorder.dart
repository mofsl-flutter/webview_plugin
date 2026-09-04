import "package:flutter/foundation.dart";

/// How a recorded entry should be read.
enum EntryKind {
  /// A navigation or lifecycle callback from native.
  lifecycle,

  /// A message that arrived over a JavaScript channel.
  message,

  /// An error reported by native.
  error,

  /// An action the harness itself performed.
  action,

  /// A harness-detected contract violation.
  defect,
}

/// One stamped entry in the harness log.
@immutable
class LogEntry {
  /// Creates an entry.
  const LogEntry({
    required this.kind,
    required this.label,
    required this.elapsedMicros,
    this.detail,
  });

  /// How to read this entry.
  final EntryKind kind;

  /// Short name, usually the native method that produced it.
  final String label;

  /// Microseconds since the recorder's epoch, stamped on arrival.
  final int elapsedMicros;

  /// Payload or explanation.
  final String? detail;

  /// Milliseconds since the recorder's epoch, for display.
  double get elapsedMs => elapsedMicros / 1000.0;
}

/// Stamps and stores every callback the plugin delivers.
///
/// The plugin surfaces its native events as plain callbacks with no timestamp and no ordering
/// guarantee, so the only way to measure a load or to prove an event never arrived is to stamp on
/// arrival in Dart and keep the sequence. That is this class's whole job.
class HarnessRecorder extends ChangeNotifier {
  /// The shared instance.
  static final HarnessRecorder instance = HarnessRecorder._();

  HarnessRecorder._();

  final Stopwatch _clock = Stopwatch();
  final List<LogEntry> _entries = <LogEntry>[];

  /// Milliseconds since the recorder's epoch, right now.
  double get elapsedMs => _clock.elapsedMicroseconds / 1000.0;

  /// Every entry recorded since the last [reset], oldest first.
  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_entries);

  /// Restarts the clock and clears the log.
  void reset() {
    _entries.clear();
    _clock
      ..reset()
      ..start();
    notifyListeners();
  }

  /// Records one entry, stamped now.
  void record(EntryKind kind, String label, [String? detail]) {
    if (!_clock.isRunning) _clock.start();
    _entries.add(
      LogEntry(
        kind: kind,
        label: label,
        elapsedMicros: _clock.elapsedMicroseconds,
        detail: detail,
      ),
    );
    notifyListeners();
  }

  /// The first entry with [label], or null if it never arrived.
  LogEntry? first(String label) {
    for (final LogEntry e in _entries) {
      if (e.label == label) return e;
    }
    return null;
  }

  /// How many entries carry [label].
  int count(String label) => _entries.where((LogEntry e) => e.label == label).length;
}
