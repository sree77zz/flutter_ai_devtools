import 'package:meta/meta.dart';

/// Severity of a captured log line. Ordered: debug < info < warning < error.
enum LogLevel { debug, info, warning, error }

/// Where a log line came from.
enum LogSource { stdout, stderr, developerLog, flutter }

/// One normalized log record in the live console buffer.
@immutable
class LogEntry {
  const LogEntry({
    required this.seq,
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.loggerName,
    this.error,
    this.stackTrace,
  });

  /// Monotonic cursor assigned by [LiveBuffer]. Drafts use 0 until stored.
  final int seq;
  final DateTime timestamp;
  final LogLevel level;
  final LogSource source;
  final String message;
  final String? loggerName;
  final String? error;
  final String? stackTrace;

  LogEntry withSeq(int newSeq) => LogEntry(
        seq: newSeq,
        timestamp: timestamp,
        level: level,
        source: source,
        message: message,
        loggerName: loggerName,
        error: error,
        stackTrace: stackTrace,
      );

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'ts': timestamp.toIso8601String(),
        'level': level.name,
        'source': source.name,
        'message': message,
        if (loggerName != null) 'logger': loggerName,
        if (error != null) 'error': error,
        if (stackTrace != null) 'stack': stackTrace,
      };
}
