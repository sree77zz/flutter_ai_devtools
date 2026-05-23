// lib/src/collectors/render_collector.dart
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/render_issue.dart';
import 'base_collector.dart';

/// Detects render-tree problems by intercepting [FlutterError.onError] and
/// pattern-matching against known overflow / constraint error strings.
class RenderCollector extends BaseCollector {
  RenderCollector({required super.store, required super.config});

  final _uuid = const Uuid();
  FlutterExceptionHandler? _prevHandler;

  @override
  String get id => 'render_collector';

  @override
  Future<void> onStart() async {
    _prevHandler = FlutterError.onError;
    FlutterError.onError = _intercept;
  }

  @override
  Future<void> onStop() async {
    FlutterError.onError = _prevHandler;
  }

  void _intercept(FlutterErrorDetails details) {
    _prevHandler?.call(details);
    final msg = details.exceptionAsString();
    _tryClassify(msg, details);
  }

  void _tryClassify(String msg, FlutterErrorDetails details) {
    RenderIssueKind? kind;
    RenderIssueSeverity severity = RenderIssueSeverity.warning;

    if (msg.contains('overflowed by') || msg.contains('RenderFlex overflowed')) {
      kind = RenderIssueKind.overflow;
      severity = RenderIssueSeverity.error;
    } else if (msg.contains('Unbounded')) {
      kind = RenderIssueKind.unboundedConstraints;
    } else if (msg.contains('intrinsic')) {
      kind = RenderIssueKind.intrinsicMeasurement;
    }

    if (kind == null) return;

    final widgetType = details.context?.toString() ?? 'Unknown';
    final description = msg.length > 400 ? '${msg.substring(0, 400)}…' : msg;

    store.addRenderIssue(RenderIssue(
      id: _uuid.v4(),
      kind: kind,
      description: description,
      widgetType: widgetType,
      capturedAt: DateTime.now(),
      severity: severity,
    ));
  }
}
