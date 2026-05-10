import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/runtime_store.dart';
import '../models/render_issue.dart';
import '../models/runtime_event.dart';
import 'base_collector.dart';

/// Detects render-tree problems by intercepting [FlutterError.onError] for
/// overflow errors and by scanning the render tree for constraint issues.
///
/// Flutter emits specific error strings for overflow/unbounded constraints
/// that this collector pattern-matches against before forwarding the error
/// to [ErrorCollector].
class RenderCollector extends BaseCollector {
  RenderCollector({
    required super.eventBus,
    required super.config,
    required RuntimeStore store,
  }) : _store = store;

  final RuntimeStore _store;
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
    if (_prevHandler != null) FlutterError.onError = _prevHandler;
  }

  void _intercept(FlutterErrorDetails details) {
    _prevHandler?.call(details);
    final msg = details.exceptionAsString();
    _tryClassifyRenderError(msg, details);
  }

  void _tryClassifyRenderError(String msg, FlutterErrorDetails details) {
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

    // Try to extract the widget type from the error context.
    final widgetType = details.context?.toString() ?? 'Unknown';

    final issue = RenderIssue(
      id: _uuid.v4(),
      kind: kind,
      description: msg.length > 400 ? '${msg.substring(0, 400)}â€¦' : msg,
      widgetType: widgetType,
      capturedAt: DateTime.now(),
      severity: severity,
    );

    _store.addRenderIssue(issue);
    eventBus.publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.renderIssueDetected,
      timestamp: issue.capturedAt,
      source: id,
      severity: severity == RenderIssueSeverity.error
          ? EventSeverity.error
          : EventSeverity.warning,
      payload: issue.toJson(),
    ));

    log.warning('Render issue detected: ${kind.name} in $widgetType');
  }
}
