import 'package:flutter_ai_devtools/flutter_ai_devtools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Disable collectors so start() installs no timers/FlutterError hooks — we
  // only need _store set so reportError is live.
  const noCollectors = CollectorConfig(
      widgets: false,
      frames: false,
      errors: false,
      routes: false,
      renders: false,
      lifecycle: false);

  test('reportError/reportIssue no-op before start()', () {
    expect(
        () => FlutterAiDevtools.reportError(Exception('x'), StackTrace.current),
        returnsNormally);
    expect(() => FlutterAiDevtools.reportIssue('x'), returnsNormally);
  });

  test('reportError records a reported issue with category + context',
      () async {
    await FlutterAiDevtools.start(collectors: noCollectors);
    addTearDown(FlutterAiDevtools.stop);

    FlutterAiDevtools.reportError(
      Exception('charge failed'),
      StackTrace.current,
      category: 'api',
      context: {'orderId': 42},
    );

    final issues = FlutterAiDevtools.store!.issues;
    expect(issues, hasLength(1));
    final i = issues.first;
    expect(i.source, IssueSource.reported);
    expect(i.category, IssueCategory.reported);
    expect(i.domainCategory, 'api');
    expect(i.evidence['orderId'], 42);
    expect(i.detail, contains('charge failed'));
  });

  test('reportIssue records a reported issue with given severity', () async {
    await FlutterAiDevtools.start(collectors: noCollectors);
    addTearDown(FlutterAiDevtools.stop);

    FlutterAiDevtools.reportIssue('Cart total mismatch',
        severity: IssueSeverity.error, context: {'expected': 1200});

    final i = FlutterAiDevtools.store!.issues.single;
    expect(i.title, 'Cart total mismatch');
    expect(i.severity, IssueSeverity.error);
    expect(i.evidence['expected'], 1200);
  });
}
