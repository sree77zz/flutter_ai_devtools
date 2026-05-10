import 'dart:developer' as dev;

/// Log level for [AnalystLogger].
enum LogLevel { debug, info, warning, error }

/// Thin structured logger used throughout the package.
///
/// Outputs via [dart:developer] so logs appear in IDE DevTools without
/// coupling to any third-party logging framework.
class AnalystLogger {
  AnalystLogger(this.name, {this.minimumLevel = LogLevel.info});

  final String name;
  LogLevel minimumLevel;

  static final _instances = <String, AnalystLogger>{};

  factory AnalystLogger.forName(String name) =>
      _instances.putIfAbsent(name, () => AnalystLogger(name));

  void debug(String message, [Object? error, StackTrace? stack]) =>
      _log(LogLevel.debug, message, error, stack);

  void info(String message, [Object? error, StackTrace? stack]) =>
      _log(LogLevel.info, message, error, stack);

  void warning(String message, [Object? error, StackTrace? stack]) =>
      _log(LogLevel.warning, message, error, stack);

  void error(String message, [Object? error, StackTrace? stack]) =>
      _log(LogLevel.error, message, error, stack);

  void _log(
    LogLevel level,
    String message,
    Object? error,
    StackTrace? stack,
  ) {
    if (level.index < minimumLevel.index) return;
    final prefix = '[flutter_ai_analyst][$name][${level.name.toUpperCase()}]';
    dev.log(
      '$prefix $message',
      name: 'flutter_ai_analyst',
      level: _devLevel(level),
      error: error,
      stackTrace: stack,
    );
  }

  int _devLevel(LogLevel l) => switch (l) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warning => 900,
        LogLevel.error => 1000,
      };
}
