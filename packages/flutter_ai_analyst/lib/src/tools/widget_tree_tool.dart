import '../core/runtime_store.dart';
import 'base_tool.dart';

/// MCP tool: `get_widget_tree`
///
/// Returns a serialized snapshot of the current Flutter widget tree,
/// including node type, depth, bounds, key, and rebuild counts.
class GetWidgetTreeTool extends AnalystTool {
  @override
  String get name => 'get_widget_tree';

  @override
  String get description =>
      'Returns a serialized snapshot of the current Flutter widget tree. '
      'Includes widget types, hierarchy depth, layout bounds, and rebuild '
      'counts. Use maxDepth to limit traversal.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'maxDepth': {
            'type': 'integer',
            'description':
                'Maximum tree depth to include. Defaults to 10. Set lower for '
                'a compact summary, higher for full detail.',
            'default': 10,
          },
          'includeRenderBounds': {
            'type': 'boolean',
            'description': 'Whether to include layout bounding boxes.',
            'default': true,
          },
        },
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    RuntimeStore store,
  ) async {
    final snapshot = store.widgetTree;
    if (snapshot == null) {
      return const ToolResult.error(
        'Widget tree not yet captured. Ensure WidgetCollector is enabled and '
        'the app has rendered at least one frame.',
      );
    }

    final maxDepth = arguments['maxDepth'] as int? ?? 10;
    final includeBounds = arguments['includeRenderBounds'] as bool? ?? true;

    var json = snapshot.toJson();
    if (!includeBounds && json['root'] != null) {
      json = _stripBounds(json);
    }

    return ToolResult.success({
      'capturedAt': snapshot.capturedAt.toIso8601String(),
      'totalNodes': snapshot.totalNodes,
      'maxDepth': snapshot.maxDepth,
      'requestedMaxDepth': maxDepth,
      'tree': json['root'],
    });
  }

  Map<String, dynamic> _stripBounds(Map<String, dynamic> node) {
    final result = Map<String, dynamic>.from(node)..remove('bounds');
    if (result['children'] is List) {
      result['children'] = (result['children'] as List)
          .map((c) => _stripBounds(Map<String, dynamic>.from(c as Map)))
          .toList();
    }
    return result;
  }
}
