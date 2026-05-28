import '../bridge/vm_bridge.dart';
import 'tool_dispatcher.dart';

void registerBridgeTools(ToolDispatcher d, VmBridge bridge) {
  d.register(
    'get_runtime_summary',
    (args) => bridge.callTool('get_runtime_summary', args),
    description: 'Complete runtime health snapshot',
  );

  d.register(
    'get_widget_tree',
    (args) => bridge.callTool('get_widget_tree', args),
    description: 'Get the current widget tree snapshot',
    schema: {
      'type': 'object',
      'properties': {
        'maxDepth': {'type': 'integer', 'default': 10},
      },
    },
  );

  d.register(
    'get_current_route',
    (args) => bridge.callTool('get_current_route', args),
    description: 'Get the active navigation route',
  );

  d.register(
    'get_recent_errors',
    (args) => bridge.callTool('get_recent_errors', args),
    description: 'Get recent error history',
    schema: {
      'type': 'object',
      'properties': {
        'limit': {'type': 'integer', 'default': 20},
        'fatalOnly': {'type': 'boolean', 'default': false},
      },
    },
  );

  d.register(
    'get_render_issues',
    (args) => bridge.callTool('get_render_issues', args),
    description: 'Get rendering problems (overflow, constraint errors)',
  );

  d.register(
    'get_frame_stats',
    (args) => bridge.callTool('get_frame_stats', args),
    description: 'Get frame timing metrics (FPS, jank)',
  );

  d.register(
    'analyze_performance',
    (args) => bridge.callTool('analyze_performance', args),
    description: 'Run performance analysis pipeline',
  );

  d.register(
    'analyze_rebuilds',
    (args) => bridge.callTool('analyze_rebuilds', args),
    description: 'Identify the most frequently rebuilding widgets',
  );
}
