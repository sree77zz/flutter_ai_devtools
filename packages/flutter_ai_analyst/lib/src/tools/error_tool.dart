import '../core/runtime_store.dart';
import '../models/error_report.dart';
import 'base_tool.dart';

/// MCP tool: `get_recent_errors`
///
/// Returns deduplicated recent Flutter/platform errors.
class GetRecentErrorsTool extends AnalystTool {
  @override
  String get name => 'get_recent_errors';

  @override
  String get description =>
      'Returns the N most recent Flutter and platform errors, deduplicated '
      'by message. Includes stack traces, category, fatality, and occurrence '
      'counts.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of errors to return.',
            'default': 20,
          },
          'category': {
            'type': 'string',
            'description':
                'Filter by category: flutter, platform, dart, network, unknown.',
            'enum': ['flutter', 'platform', 'dart', 'network', 'unknown'],
          },
          'fatalOnly': {
            'type': 'boolean',
            'description': 'If true, return only fatal errors.',
            'default': false,
          },
          'includeStackTrace': {
            'type': 'boolean',
            'description': 'Whether to include stack traces in the response.',
            'default': true,
          },
        },
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    RuntimeStore store,
  ) async {
    final limit = arguments['limit'] as int? ?? 20;
    final categoryFilter = arguments['category'] as String?;
    final fatalOnly = arguments['fatalOnly'] as bool? ?? false;
    final includeStack = arguments['includeStackTrace'] as bool? ?? true;

    var errors = store.recentErrors;

    if (categoryFilter != null) {
      final cat = ErrorCategory.values.byName(categoryFilter);
      errors = errors.where((e) => e.category == cat).toList();
    }
    if (fatalOnly) {
      errors = errors.where((e) => e.isFatal).toList();
    }

    final limited = errors.reversed.take(limit).toList();

    return ToolResult.success({
      'totalStored': store.recentErrors.length,
      'returned': limited.length,
      'errors': limited.map((e) {
        final json = e.toJson();
        if (!includeStack) json.remove('stackTrace');
        return json;
      }).toList(),
    });
  }
}
