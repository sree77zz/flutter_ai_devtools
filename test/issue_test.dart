import 'package:flutter_ai_devtools/src/models/issue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Issue', () {
    test('toJson emits the documented shape', () {
      final i = Issue(
        signature: 'sig-1',
        category: IssueCategory.layoutRender,
        severity: IssueSeverity.error,
        source: IssueSource.detected,
        title: 'Overflow',
        detail: 'A RenderFlex overflowed by 42 px',
        firstSeen: DateTime(2026, 1, 1),
        lastSeen: DateTime(2026, 1, 1),
        count: 1,
        evidence: const {'widget': 'Row'},
      );
      final j = i.toJson();
      expect(j['signature'], 'sig-1');
      expect(j['category'], 'layoutRender');
      expect(j['severity'], 'error');
      expect(j['source'], 'detected');
      expect(j['count'], 1);
      expect(j['evidence'], {'widget': 'Row'});
      expect(j['domainCategory'], isNull);
    });

    test('copyWith overrides only the given fields', () {
      final i = Issue(
        signature: 's',
        category: IssueCategory.exception,
        severity: IssueSeverity.warning,
        source: IssueSource.detected,
        title: 't',
        detail: 'd',
        firstSeen: DateTime(2026),
        lastSeen: DateTime(2026),
        count: 1,
        evidence: const {},
      );
      final u = i.copyWith(count: 5, severity: IssueSeverity.critical);
      expect(u.count, 5);
      expect(u.severity, IssueSeverity.critical);
      expect(u.signature, 's');
      expect(u.firstSeen, DateTime(2026));
    });

    test('issueSignature is stable and normalizes whitespace', () {
      final a = issueSignature(IssueCategory.exception, 'Null   check  failed');
      final b = issueSignature(IssueCategory.exception, 'Null check failed');
      expect(a, b);
      final c = issueSignature(IssueCategory.lifecycle, 'Null check failed');
      expect(a, isNot(c));
    });
  });
}
