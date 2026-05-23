// cli/bin/devtools_mcp.dart
import 'dart:io';
import 'package:flutter_ai_devtools_mcp/src/bridge/vm_bridge.dart';
import 'package:flutter_ai_devtools_mcp/src/server/stdio_server.dart';
import 'package:flutter_ai_devtools_mcp/src/tools/tool_dispatcher.dart';

Future<void> main() async {
  final bridge = VmBridge();

  // Try to connect immediately.
  var connected = await bridge.connect();

  if (!connected) {
    stderr.writeln('⧗ Waiting for Flutter app... (Ctrl+C to cancel)');
    for (var i = 0; i < 15 && !connected; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      connected = await bridge.connect();
    }
    if (!connected) {
      stderr.writeln('✗ Could not connect after 30s. Is your Flutter app running?');
      exit(1);
    }
  }

  final dispatcher = ToolDispatcher();
  _registerBridgeTools(dispatcher, bridge);

  final server = StdioServer(dispatcher: dispatcher);
  server.start();

  // Keep alive until stdin closes (Claude disconnects).
  await stdin.drain<List<int>>();
  await bridge.dispose();
}

void _registerBridgeTools(ToolDispatcher d, VmBridge bridge) {
  const tools = [
    'get_widget_tree',
    'get_current_route',
    'get_recent_errors',
    'get_render_issues',
    'get_frame_stats',
    'analyze_performance',
    'analyze_rebuilds',
    'get_runtime_summary',
  ];

  for (final name in tools) {
    d.register(name, (args) => bridge.callTool(name, args));
  }
}
