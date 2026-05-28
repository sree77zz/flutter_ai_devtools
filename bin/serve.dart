// bin/serve.dart
import 'dart:io';

import 'package:flutter_ai_devtools/src/bridge/vm_bridge.dart';
import 'package:flutter_ai_devtools/src/mcp/sse_server.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_definitions.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_dispatcher.dart';

const _defaultMcpPort = 8765;

Future<void> main(List<String> args) async {
  final mcpPort = _argInt(args, '--port') ?? _defaultMcpPort;
  final vmUri = _argString(args, '--vm-uri');

  final bridge = VmBridge();

  stderr.writeln('⧗ Connecting to Flutter app VM service...');

  var connected = await bridge.connect(vmUri);
  if (!connected) {
    stderr.writeln('  (Waiting for Flutter app... Ctrl+C to cancel)');
    for (var i = 0; i < 15 && !connected; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      connected = await bridge.connect(vmUri);
    }
  }

  if (!connected) {
    stderr.writeln(
      '✗ Could not connect after 30s.\n'
      'Make sure your Flutter app is running.\n'
      '\nFor Android/iOS, run flutter with a fixed VM port:\n'
      '  flutter run --vm-service-port=8181 --disable-service-auth-codes\n'
      '\nOr pass the URI directly:\n'
      '  dart run flutter_ai_devtools:serve --vm-uri=<url>',
    );
    exit(1);
  }

  final dispatcher = ToolDispatcher();
  registerBridgeTools(dispatcher, bridge);

  final server = SseServer(dispatcher: dispatcher);
  final port = await server.bind(mcpPort);
  stderr.writeln('✓ MCP server listening at http://localhost:$port/sse');
  stderr.writeln('  Claude Code: run /mcp to connect');

  // Stay alive until Ctrl+C or stdin closes.
  ProcessSignal.sigint.watch().listen((_) async {
    stderr.writeln('\nShutting down...');
    await bridge.dispose();
    await server.stop();
    exit(0);
  });

  // Also exit if stdin closes (IDE/runner closed).
  await stdin.drain<void>();
  await bridge.dispose();
  await server.stop();
}

String? _argString(List<String> args, String flag) {
  final idx = args.indexOf(flag);
  if (idx != -1 && idx + 1 < args.length) return args[idx + 1];
  // Also support --flag=value form
  final prefix = '$flag=';
  for (final a in args) {
    if (a.startsWith(prefix)) return a.substring(prefix.length);
  }
  return null;
}

int? _argInt(List<String> args, String flag) =>
    int.tryParse(_argString(args, flag) ?? '');
