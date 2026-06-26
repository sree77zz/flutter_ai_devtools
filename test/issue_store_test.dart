import 'package:flutter_ai_devtools/src/config.dart';
import 'package:flutter_ai_devtools/src/models/issue.dart';
import 'package:flutter_ai_devtools/src/store/runtime_store.dart';
import 'package:flutter_test/flutter_test.dart';

Issue mk(String sig, {IssueSeverity sev = IssueSeverity.warning, int n = 1}) =>
    Issue(
      signature: sig,
      category: IssueCategory.exception,
      severity: sev,
      source: IssueSource.detected,
      title: 't',
      detail: 'd',
      firstSeen: DateTime(2026),
      lastSeen: DateTime(2026, 1, 1, 0, 0, n),
      count: 1,
      evidence: const {},
    );

void main() {
  group('RuntimeStore.addIssue', () {
    test('stores a new issue', () {
      final s = RuntimeStore();
      s.addIssue(mk('a'));
      expect(s.issues, hasLength(1));
      expect(s.issues.first.count, 1);
    });

    test('deduplicates by signature and increments count + lastSeen', () {
      final s = RuntimeStore();
      s.addIssue(mk('a', n: 1));
      s.addIssue(mk('a', n: 2));
      s.addIssue(mk('a', n: 3));
      expect(s.issues, hasLength(1));
      expect(s.issues.first.count, 3);
      expect(s.issues.first.lastSeen, DateTime(2026, 1, 1, 0, 0, 3));
    });

    test('keeps the highest severity seen', () {
      final s = RuntimeStore();
      s.addIssue(mk('a', sev: IssueSeverity.warning));
      s.addIssue(mk('a', sev: IssueSeverity.error));
      s.addIssue(mk('a', sev: IssueSeverity.info));
      expect(s.issues.first.severity, IssueSeverity.error);
    });

    test('escalates to critical once count reaches recurrenceThreshold', () {
      final s = RuntimeStore(recurrenceThreshold: 3);
      s.addIssue(mk('a', sev: IssueSeverity.warning));
      s.addIssue(mk('a', sev: IssueSeverity.warning));
      expect(s.issues.first.severity, IssueSeverity.warning);
      s.addIssue(mk('a', sev: IssueSeverity.warning)); // count == 3
      expect(s.issues.first.severity, IssueSeverity.critical);
    });

    test('bounds issue count, evicting the oldest', () {
      final s = RuntimeStore(maxIssues: 2);
      s.addIssue(mk('a'));
      s.addIssue(mk('b'));
      s.addIssue(mk('c'));
      expect(s.issues.map((i) => i.signature), ['b', 'c']);
    });

    test('clear() removes issues', () {
      final s = RuntimeStore();
      s.addIssue(mk('a'));
      s.clear();
      expect(s.issues, isEmpty);
    });
  });

  test('CollectorConfig exposes maxIssues / lifecycle / recurrenceThreshold',
      () {
    const c = CollectorConfig();
    expect(c.maxIssues, greaterThan(0));
    expect(c.lifecycle, isTrue);
    expect(c.recurrenceThreshold, greaterThan(1));
  });
}
