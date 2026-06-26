import 'package:flutter_ai_devtools/src/models/issue.dart';
import 'package:flutter_ai_devtools/src/service_extensions.dart';
import 'package:flutter_ai_devtools/src/store/runtime_store.dart';
import 'package:flutter_test/flutter_test.dart';

Issue mk(String sig, IssueCategory cat, IssueSeverity sev) => Issue(
      signature: sig,
      category: cat,
      severity: sev,
      source: IssueSource.detected,
      title: sig,
      detail: 'd',
      firstSeen: DateTime(2026),
      lastSeen: DateTime(2026),
      count: 1,
      evidence: const {},
    );

void main() {
  test('buildIssuesResult filters by category and severity', () {
    final store = RuntimeStore();
    store.addIssue(mk('a', IssueCategory.exception, IssueSeverity.error));
    store.addIssue(mk('b', IssueCategory.layoutRender, IssueSeverity.warning));
    store.addIssue(mk('c', IssueCategory.exception, IssueSeverity.info));

    final all = buildIssuesResult(store, {});
    expect(all['count'], 3);

    final exceptions = buildIssuesResult(store, {'category': 'exception'});
    expect(exceptions['count'], 2);

    final errorsUp = buildIssuesResult(store, {'minSeverity': 'error'});
    expect(errorsUp['count'], 1);
  });

  test('buildIssuesResult sorts by severity desc then count desc', () {
    final store = RuntimeStore();
    store.addIssue(mk('warn', IssueCategory.exception, IssueSeverity.warning));
    store.addIssue(mk('crit', IssueCategory.exception, IssueSeverity.critical));
    final r = buildIssuesResult(store, {});
    final list = r['issues'] as List;
    expect((list.first as Map)['signature'], 'crit');
  });

  test('registerServiceExtensions registers without throwing', () {
    expect(() => registerServiceExtensions(RuntimeStore()), returnsNormally);
  });
}
