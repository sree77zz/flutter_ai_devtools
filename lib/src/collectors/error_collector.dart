// lib/src/collectors/error_collector.dart
import 'package:flutter/foundation.dart';
import '../models/error_report.dart';
import 'base_collector.dart';

class ErrorCollector extends BaseCollector {
  ErrorCollector({required super.store, required super.config});

  FlutterExceptionHandler? _prevFlutter;
  bool Function(Object, StackTrace)? _prevPlatform;

  @override
  String get id => 'error_collector';

  @override
  Future<void> onStart() async {
    _prevFlutter = FlutterError.onError;
    FlutterError.onError = _onFlutter;
    _prevPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = _onPlatform;
  }

  @override
  Future<void> onStop() async {
    FlutterError.onError = _prevFlutter;
    PlatformDispatcher.instance.onError = _prevPlatform ?? (_, __) => false;
  }

  void _onFlutter(FlutterErrorDetails d) {
    _prevFlutter?.call(d);
    final msg = d.exceptionAsString();
    store.addError(ErrorReport(
      id: _id(msg),
      capturedAt: DateTime.now(),
      category: ErrorCategory.flutter,
      message: msg,
      stackTrace: d.stack?.toString(),
      context: {'library': d.library ?? 'unknown'},
      isFatal: false,
    ));
  }

  bool _onPlatform(Object error, StackTrace stack) {
    final msg = error.toString();
    store.addError(ErrorReport(
      id: _id(msg),
      capturedAt: DateTime.now(),
      category: ErrorCategory.platform,
      message: msg,
      stackTrace: stack.toString(),
      isFatal: true,
    ));
    return _prevPlatform?.call(error, stack) ?? false;
  }

  String _id(String msg) {
    final key = msg.trim().replaceAll(RegExp(r'\s+'), ' ');
    return (key.length > 64 ? key.substring(0, 64) : key)
        .hashCode
        .toUnsigned(32)
        .toRadixString(16);
  }
}
