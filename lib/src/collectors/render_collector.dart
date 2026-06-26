import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/issue.dart';
import '../models/render_issue.dart';
import 'base_collector.dart';
import 'error_patterns.dart';

/// Detects render-tree problems by intercepting [FlutterError.onError] and
/// pattern-matching against known layout error strings. Emits both the legacy
/// [RenderIssue] (kept for back-compat) and a unified [Issue] (category
/// [IssueCategory.layoutRender]) into the store.
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
    _classify(details.exceptionAsString(), details);
  }

  void _classify(String msg, FlutterErrorDetails details) {
    final hit = matchLayoutRender(msg);
    if (hit == null) return;

    final widgetType = details.context?.toString() ?? 'Unknown';
    final detail = msg.length > 400 ? '${msg.substring(0, 400)}…' : msg;

    store.addRenderIssue(RenderIssue(
      id: _uuid.v4(),
      kind: hit.kind,
      description: detail,
      widgetType: widgetType,
      capturedAt: DateTime.now(),
      severity: hit.severity == IssueSeverity.error
          ? RenderIssueSeverity.error
          : RenderIssueSeverity.warning,
    ));

    store.addIssue(Issue(
      signature: issueSignature(
          IssueCategory.layoutRender, '${hit.kind.name}|$widgetType'),
      category: IssueCategory.layoutRender,
      severity: hit.severity,
      source: IssueSource.detected,
      title: hit.title,
      detail: detail,
      firstSeen: DateTime.now(),
      lastSeen: DateTime.now(),
      count: 1,
      evidence: {'widget': widgetType},
    ));
  }
}
