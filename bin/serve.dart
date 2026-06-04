// bin/serve.dart
import 'dart:io';

import 'package:flutter_ai_devtools/src/bridge/vm_bridge.dart';
import 'package:flutter_ai_devtools/src/mcp/sse_server.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_definitions.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_dispatcher.dart';

const _defaultMcpPort = 8765;

Future<void> main(List<String> args) async {
  final mcpPort = int.tryParse(_argValue(args, '--port') ?? '') ?? _defaultMcpPort;

  final bridge = VmBridge();
  bridge.start(); // resilient; connects whenever the app appears.

  final dispatcher = ToolDispatcher();
  registerBridgeTools(dispatcher, bridge);

  final server = SseServer(dispatcher: dispatcher);
  final port = await server.bind(mcpPort);
  stderr.writeln('✓ MCP SSE server listening at http://localhost:$port/sse');
  stderr.writeln('  (The bridge connects to your app automatically when it starts.)');

  ProcessSignal.sigint.watch().listen((_) async {
    await bridge.dispose();
    await server.stop();
    exit(0);
  });

  await stdin.drain<void>();
  await bridge.dispose();
  await server.stop();
}

String? _argValue(List<String> args, String flag) {
  final idx = args.indexOf(flag);
  if (idx != -1 && idx + 1 < args.length) return args[idx + 1];
  final prefix = '$flag=';
  for (final a in args) {
    if (a.startsWith(prefix)) return a.substring(prefix.length);
  }
  return null;
}
