import 'dart:async';

import 'analyst_logger.dart';

typedef ErrorCallback = void Function(Object error, StackTrace stack);

/// Central error handler for the plugin.
///
/// Wraps [Zone.current.handleUncaughtError] and forwards to registered
/// callbacks, allowing the rest of the architecture to react (e.g., emit
/// an ErrorReport) without tight coupling.
class AnalystErrorHandler {
  AnalystErrorHandler._();

  static final AnalystErrorHandler instance = AnalystErrorHandler._();

  final _log = AnalystLogger.forName('ErrorHandler');
  final _callbacks = <ErrorCallback>[];

  void addListener(ErrorCallback cb) => _callbacks.add(cb);
  void removeListener(ErrorCallback cb) => _callbacks.remove(cb);

  void handle(Object error, StackTrace stack) {
    _log.error('Unhandled error in analyst subsystem', error, stack);
    for (final cb in List.of(_callbacks)) {
      try {
        cb(error, stack);
      } catch (_) {
        // prevent callback errors from cascading
      }
    }
  }

  /// Runs [body] in a guarded zone; all uncaught errors route through [handle].
  ///
  /// Returns null if [body] throws synchronously (the error is routed to
  /// [handle] rather than propagated to the caller).
  T? runGuarded<T>(T Function() body) {
    return runZonedGuarded(body, handle);
  }
}
