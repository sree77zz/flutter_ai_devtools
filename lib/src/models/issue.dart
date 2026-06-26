import 'package:meta/meta.dart';

/// What kind of problem this is.
enum IssueCategory { exception, layoutRender, lifecycle, reported }

/// Ordered: info < warning < error < critical.
enum IssueSeverity { info, warning, error, critical }

/// Where the issue came from.
enum IssueSource { detected, reported }

/// A single deduplicated, aggregated problem in the running app.
@immutable
class Issue {
  const Issue({
    required this.signature,
    required this.category,
    required this.severity,
    required this.source,
    required this.title,
    required this.detail,
    required this.firstSeen,
    required this.lastSeen,
    required this.count,
    required this.evidence,
    this.domainCategory,
  });

  final String signature;
  final IssueCategory category;
  final IssueSeverity severity;
  final IssueSource source;
  final String title;
  final String detail;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int count;
  final Map<String, dynamic> evidence;
  final String? domainCategory;

  Issue copyWith({
    IssueSeverity? severity,
    DateTime? lastSeen,
    int? count,
  }) =>
      Issue(
        signature: signature,
        category: category,
        severity: severity ?? this.severity,
        source: source,
        title: title,
        detail: detail,
        firstSeen: firstSeen,
        lastSeen: lastSeen ?? this.lastSeen,
        count: count ?? this.count,
        evidence: evidence,
        domainCategory: domainCategory,
      );

  Map<String, dynamic> toJson() => {
        'signature': signature,
        'category': category.name,
        'severity': severity.name,
        'source': source.name,
        'title': title,
        'detail': detail,
        'firstSeen': firstSeen.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'count': count,
        'evidence': evidence,
        if (domainCategory != null) 'domainCategory': domainCategory,
      };
}

/// Computes a stable signature from a [category] and free-text [key]
/// (whitespace-normalized, length-bounded) so repeats collapse onto one [Issue].
String issueSignature(IssueCategory category, String key) {
  final norm = key.trim().replaceAll(RegExp(r'\s+'), ' ');
  final bounded = norm.length > 120 ? norm.substring(0, 120) : norm;
  final hash = '${category.name}|$bounded'.hashCode.toUnsigned(32).toRadixString(16);
  return '${category.name}_$hash';
}
