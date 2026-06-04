import '../bridge/vm_bridge.dart';
import '../models/log_entry.dart';
import 'tool_dispatcher.dart';

/// Registers every MCP tool against [d]. App-state tools proxy to the running
/// app via service extensions ([bridge.callTool]); live/console/connection
/// tools read directly from the bridge and its [VmBridge.liveBuffer].
void registerBridgeTools(ToolDispatcher d, VmBridge bridge) {
  // ── App-state tools (service-extension proxies) ──────────────────────────
  d.register('get_runtime_summary', (a) => bridge.callTool('get_runtime_summary', a),
      description: 'Complete runtime health snapshot');
  d.register('get_widget_tree', (a) => bridge.callTool('get_widget_tree', a),
      description: 'Current widget tree snapshot',
      schema: {
        'type': 'object',
        'properties': {'maxDepth': {'type': 'integer', 'default': 10}},
      });
  d.register('get_current_route', (a) => bridge.callTool('get_current_route', a),
      description: 'Active navigation route');
  d.register('get_recent_errors', (a) => bridge.callTool('get_recent_errors', a),
      description: 'Recent error history',
      schema: {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer', 'default': 20},
          'fatalOnly': {'type': 'boolean', 'default': false},
        },
      });
  d.register('get_render_issues', (a) => bridge.callTool('get_render_issues', a),
      description: 'Rendering problems (overflow, constraints)');
  d.register('get_frame_stats', (a) => bridge.callTool('get_frame_stats', a),
      description: 'Frame timing metrics (FPS, jank)');
  d.register('analyze_performance', (a) => bridge.callTool('analyze_performance', a),
      description: 'Performance analysis pipeline');
  d.register('analyze_rebuilds', (a) => bridge.callTool('analyze_rebuilds', a),
      description: 'Most frequently rebuilding widgets');

  // ── Live / console / connection tools (bridge-direct) ────────────────────
  d.register('get_logs', (a) async {
    final sinceSeq = _asInt(a['sinceSeq']) ?? 0;
    final limit = _asInt(a['limit']) ?? 200;
    final grep = a['grep'] as String?;
    final level = _levelFromName(a['level'] as String?);
    final nextSeq = bridge.liveBuffer.nextSeq;
    final entries = bridge.liveBuffer
        .logsSince(sinceSeq, minLevel: level, grep: grep, limit: limit);
    return {
      'logs': entries.map((e) => e.toJson()).toList(),
      'nextSeq': nextSeq,
    };
  },
      description:
          'Live console tail (stdout/stderr/developer.log) since a cursor',
      schema: {
        'type': 'object',
        'properties': {
          'sinceSeq': {'type': 'integer', 'default': 0, 'minimum': 0},
          'level': {'type': 'string', 'enum': ['debug', 'info', 'warning', 'error']},
          'grep': {'type': 'string'},
          'limit': {'type': 'integer', 'default': 200, 'minimum': 0},
        },
      });

  d.register('get_connection_status', (a) async => bridge.status.toJson(),
      description: 'Whether the bridge is connected to the running app');

  d.register('hot_reload', (a) => bridge.hotReload(),
      description: 'Trigger a hot reload of the running app');

  d.register('get_memory_info', (a) => bridge.memoryInfo(),
      description: 'Current heap usage of the running app');
}

int? _asInt(Object? v) => v is int
    ? v
    : v is double
        ? v.toInt()
        : (v is String ? int.tryParse(v) : null);

LogLevel? _levelFromName(String? name) {
  if (name == null) return null;
  for (final l in LogLevel.values) {
    if (l.name == name) return l;
  }
  return null;
}
