import '../models/issue.dart';
import '../models/render_issue.dart';

/// Shared FlutterError message classifiers, so ErrorCollector/RenderCollector/
/// LifecycleCollector agree on which errors are layout/render vs lifecycle and
/// no generic `exception` duplicate is emitted for an already-specialized error.

/// Layout/render classification for a FlutterError message, or null.
({String title, RenderIssueKind kind, IssueSeverity severity})? matchLayoutRender(
    String msg) {
  if (msg.contains('overflowed by') || msg.contains('RenderFlex overflowed')) {
    return (title: 'Render overflow', kind: RenderIssueKind.overflow, severity: IssueSeverity.error);
  }
  if (msg.contains('Unbounded') || msg.contains('forces an infinite')) {
    return (title: 'Unbounded constraints', kind: RenderIssueKind.unboundedConstraints, severity: IssueSeverity.warning);
  }
  if (msg.contains('intrinsic')) {
    return (title: 'Intrinsic measurement', kind: RenderIssueKind.intrinsicMeasurement, severity: IssueSeverity.warning);
  }
  return null;
}

/// Lifecycle issue title for a FlutterError message, or null.
String? matchLifecycle(String msg) {
  if (msg.contains('called after dispose()')) return 'setState after dispose';
  if (msg.contains('used after being disposed')) return 'Object used after dispose';
  if (msg.contains('has been unmounted') || msg.contains('!_debugLifecycleState')) {
    return 'Access after unmount';
  }
  if (msg.contains('Another exception was thrown')) return 'Cascading exception';
  return null;
}
