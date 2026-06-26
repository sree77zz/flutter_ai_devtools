import 'package:flutter/foundation.dart';
import '../models/issue.dart';
import 'base_collector.dart';
import 'error_patterns.dart';

/// Detects widget/state lifecycle violations from [FlutterError.onError]
/// (setState-after-dispose, use-after-dispose, unmounted access) and records
/// them as unified [Issue]s (category [IssueCategory.lifecycle]).
class LifecycleCollector extends BaseCollector {
  LifecycleCollector({required super.store, required super.config});

  FlutterExceptionHandler? _prevHandler;

  @override
  String get id => 'lifecycle_collector';

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
    _classify(details.exceptionAsString());
  }

  void _classify(String msg) {
    final title = matchLifecycle(msg);
    if (title == null) return;
    final detail = msg.length > 400 ? '${msg.substring(0, 400)}…' : msg;
    store.addIssue(Issue(
      signature: issueSignature(IssueCategory.lifecycle, title),
      category: IssueCategory.lifecycle,
      severity: IssueSeverity.error,
      source: IssueSource.detected,
      title: title,
      detail: detail,
      firstSeen: DateTime.now(),
      lastSeen: DateTime.now(),
      count: 1,
      evidence: const {},
    ));
  }
}
