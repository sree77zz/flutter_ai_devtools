import '../core/runtime_store.dart';
import '../models/render_issue.dart';
import 'base_tool.dart';

/// MCP tool: `get_render_issues`
///
/// Returns recent render-tree issues: overflow, unbounded constraints, etc.
class GetRenderIssuesTool extends AnalystTool {
  @override
  String get name => 'get_render_issues';

  @override
  String get description =>
      'Returns recent render tree issues detected by RenderCollector, '
      'including overflow errors, unbounded constraints, and intrinsic '
      'measurement problems.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of issues to return.',
            'default': 30,
          },
          'severity': {
            'type': 'string',
            'description': 'Filter by severity: info, warning, error.',
            'enum': ['info', 'warning', 'error'],
          },
          'kind': {
            'type': 'string',
            'description':
                'Filter by issue kind: overflow, unboundedConstraints, '
                'intrinsicMeasurement, largeRepaintBoundary, offscreenLayer.',
          },
        },
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    RuntimeStore store,
  ) async {
    final limit = arguments['limit'] as int? ?? 30;
    final severityFilter = arguments['severity'] as String?;
    final kindFilter = arguments['kind'] as String?;

    var issues = store.recentRenderIssues;

    if (severityFilter != null) {
      final sev = RenderIssueSeverity.values.byName(severityFilter);
      issues = issues.where((i) => i.severity == sev).toList();
    }
    if (kindFilter != null) {
      final kind = RenderIssueKind.values.byName(kindFilter);
      issues = issues.where((i) => i.kind == kind).toList();
    }

    final limited = issues.reversed.take(limit).toList();

    final summary = <String, int>{};
    for (final issue in store.recentRenderIssues) {
      summary[issue.kind.name] = (summary[issue.kind.name] ?? 0) + 1;
    }

    return ToolResult.success({
      'totalStored': store.recentRenderIssues.length,
      'returned': limited.length,
      'summary': summary,
      'issues': limited.map((i) => i.toJson()).toList(),
    });
  }
}
