import 'dart:collection';
import '../models/log_entry.dart';

/// Bridge-side rolling buffer of normalized log lines with a monotonic cursor.
///
/// Continuously fed by the VM-service stream ingestion; read by the `get_logs`
/// tool via [logsSince]. Bounded so a chatty app cannot exhaust memory.
class LiveBuffer {
  LiveBuffer({this.maxLogs = 2000});

  final int maxLogs;
  final Queue<LogEntry> _logs = Queue<LogEntry>();
  int _seq = 0;

  /// Stores [draft] (its [LogEntry.seq] is overwritten) and returns the stored
  /// entry with its assigned seq.
  LogEntry addLog(LogEntry draft) {
    final entry = draft.withSeq(_seq++);
    _logs.addLast(entry);
    while (_logs.length > maxLogs) {
      _logs.removeFirst();
    }
    return entry;
  }

  /// The seq the next [addLog] will assign. Callers persist this as a cursor.
  int get nextSeq => _seq;

  /// Entries with `seq >= sinceSeq`, optionally filtered by level/substring,
  /// returning at most [limit] (the most recent ones when truncated).
  List<LogEntry> logsSince(
    int sinceSeq, {
    LogLevel? minLevel,
    String? grep,
    int limit = 200,
  }) {
    Iterable<LogEntry> it = _logs.where((e) => e.seq >= sinceSeq);
    if (minLevel != null) {
      it = it.where((e) => e.level.index >= minLevel.index);
    }
    if (grep != null && grep.isNotEmpty) {
      final needle = grep.toLowerCase();
      it = it.where((e) => e.message.toLowerCase().contains(needle));
    }
    final list = it.toList(growable: false);
    if (list.length > limit) {
      return list.sublist(list.length - limit);
    }
    return list;
  }
}
