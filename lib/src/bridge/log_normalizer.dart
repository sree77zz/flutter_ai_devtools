import 'dart:convert';
import 'package:vm_service/vm_service.dart' as vm;
import '../models/log_entry.dart';

/// Converts a vm_service [vm.Event] into a [LogEntry] draft (seq = 0), or null
/// if the event carries no log payload. [source] disambiguates the originating
/// stream (Stdout vs Stderr vs Logging), which the event itself does not encode.
LogEntry? normalizeVmEvent(vm.Event e, {required LogSource source}) {
  switch (e.kind) {
    case vm.EventKind.kWriteEvent:
      final raw = e.bytes;
      if (raw == null) return null;
      final text = utf8.decode(base64.decode(raw)).trimRight();
      if (text.trim().isEmpty) return null;
      return LogEntry(
        seq: 0,
        timestamp: DateTime.now(),
        level: source == LogSource.stderr ? LogLevel.error : LogLevel.info,
        source: source,
        message: text,
      );
    case vm.EventKind.kLogging:
      final rec = e.logRecord;
      if (rec == null) return null;
      return LogEntry(
        seq: 0,
        timestamp: DateTime.now(),
        level: _levelFromInt(rec.level ?? 0),
        source: LogSource.developerLog,
        message: rec.message?.valueAsString ?? '',
        loggerName: rec.loggerName?.valueAsString,
        error: rec.error?.valueAsString,
        stackTrace: rec.stackTrace?.valueAsString,
      );
    default:
      return null;
  }
}

/// Maps `dart:logging` numeric levels onto [LogLevel]:
/// >=900 (SEVERE/SHOUT) → error, >=700 (WARNING) → warning,
/// >=500 (INFO) → info, else debug.
LogLevel _levelFromInt(int level) {
  if (level >= 900) return LogLevel.error;
  if (level >= 700) return LogLevel.warning;
  if (level >= 500) return LogLevel.info;
  return LogLevel.debug;
}
