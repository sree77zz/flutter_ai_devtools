import '../core/runtime_store.dart';
import 'base_tool.dart';

/// MCP tool: `get_current_route`
///
/// Returns the current navigation route and recent navigation history.
class GetCurrentRouteTool extends AnalystTool {
  @override
  String get name => 'get_current_route';

  @override
  String get description =>
      'Returns the current active route name, the full navigation stack, '
      'and the N most recent route change events.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'historyLimit': {
            'type': 'integer',
            'description': 'Maximum number of recent route events to return.',
            'default': 10,
          },
        },
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    RuntimeStore store,
  ) async {
    final nav = store.navigationState;
    if (nav == null) {
      return const ToolResult.error(
        'Navigation state not available. Ensure RouteCollector is enabled and '
        'AnalystNavigatorObserver is attached to your Navigator.',
      );
    }

    final historyLimit = arguments['historyLimit'] as int? ?? 10;
    final history = nav.history.reversed.take(historyLimit).toList();

    return ToolResult.success({
      'currentRoute': nav.currentRoute,
      'stack': nav.stack,
      'stackDepth': nav.stack.length,
      'recentHistory': history.map((r) => r.toJson()).toList(),
    });
  }
}
