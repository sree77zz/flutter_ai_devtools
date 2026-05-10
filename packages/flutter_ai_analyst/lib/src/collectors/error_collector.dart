import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/runtime_store.dart';
import '../models/error_report.dart';
import '../models/runtime_event.dart';
import 'base_collector.dart';

/// Captures Flutter and platform errors, deduplicates, and persists them in
/// [RuntimeStore].
///
/// Hooks:
/// - [FlutterError.onError] — framework errors (overflow, null widgets, …)
/// - [PlatformDispatcher.instance.onError] — unhandled async/isolate errors
class ErrorCollector extends BaseCollector {
  ErrorCollector({
    required super.eventBus,
    required super.config,
    required RuntimeStore store,
  }) : _store = store;

  final RuntimeStore _store;
  final _uuid = const Uuid();

  FlutterExceptionHandler? _previousFlutterHandler;
  // PlatformDispatcher.onError typedef lives in dart:ui; use the raw signature.
  bool Function(Object, StackTrace)? _previousPlatformHandler;

  @override
  String get id => 'error_collector';

  @override
  Future<void> onStart() async {
    _previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = _handleFlutterError;

    _previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = _handlePlatformError;
  }

  @override
  Future<void> onStop() async {
    FlutterError.onError = _previousFlutterHandler;
    PlatformDispatcher.instance.onError = _previousPlatformHandler ?? (_,__) => false;
  }

  void _handleFlutterError(FlutterErrorDetails details) {
    // Forward to the previous handler first (keeps DevTools working).
    _previousFlutterHandler?.call(details);

    final message = details.exceptionAsString();
    final stack = details.stack?.toString();
    final report = ErrorReport(
      id: _stableId(message),
      capturedAt: DateTime.now(),
      category: ErrorCategory.flutter,
      message: message,
      stackTrace: stack,
      context: {
        'library': details.library ?? 'unknown',
        'context': details.context?.toString(),
      },
      isFatal: false,
    );
    _publish(report);
  }

  bool _handlePlatformError(Object error, StackTrace stack) {
    final message = error.toString();
    final report = ErrorReport(
      id: _stableId(message),
      capturedAt: DateTime.now(),
      category: ErrorCategory.platform,
      message: message,
      stackTrace: stack.toString(),
      isFatal: true,
    );
    _publish(report);
    return _previousPlatformHandler?.call(error, stack) ?? false;
  }

  void _publish(ErrorReport report) {
    _store.addError(report);
    eventBus.publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.flutterError,
      timestamp: report.capturedAt,
      source: id,
      severity: report.isFatal ? EventSeverity.critical : EventSeverity.error,
      payload: report.toJson(),
    ));
    log.error('Captured ${report.category.name} error: ${report.message}');
  }

  /// Stable ID for deduplication — first 64 chars of the message.
  String _stableId(String message) {
    final normalized = message.trim().replaceAll(RegExp(r'\s+'), ' ');
    final key = normalized.length > 64 ? normalized.substring(0, 64) : normalized;
    return key.hashCode.toUnsigned(32).toRadixString(16);
  }
}
