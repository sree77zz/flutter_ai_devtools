// bin/devtools_mcp.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_ai_devtools/src/bridge/vm_bridge.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_definitions.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_dispatcher.dart';

Future<void> main(List<String> args) async {
  final vmUri = _argString(args, '--vm-uri');

  final bridge = VmBridge();
  final dispatcher = ToolDispatcher();
  registerBridgeTools(dispatcher, bridge);

  await _serveStdio(bridge, dispatcher, vmUri);
}

Future<void> _serveStdio(
    VmBridge bridge, ToolDispatcher dispatcher, String? vmUri) async {
  final lines =
      stdin.transform(utf8.decoder).transform(const LineSplitter());

  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    Map<String, dynamic> req;
    try {
      req = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      _write(_error(null, -32700, 'Parse error'));
      continue;
    }

    final id = req['id'];
    final method = req['method'] as String?;
    final params = req['params'] as Map<String, dynamic>? ?? {};

    // Notifications have no 'id' key. Messages with id:null are treated as requests.
    if (!req.containsKey('id')) continue;

    try {
      final result = await _dispatch(method, params, bridge, dispatcher, vmUri);
      _write({'jsonrpc': '2.0', 'id': id, 'result': result});
    } catch (e) {
      _write(_error(id, -32603, e.toString()));
    }
  }
}

Future<Object?> _dispatch(
  String? method,
  Map<String, dynamic> params,
  VmBridge bridge,
  ToolDispatcher dispatcher,
  String? vmUri,
) async {
  switch (method) {
    case 'initialize':
      return {
        'protocolVersion': '2024-11-05',
        'capabilities': {
          'tools': {'listChanged': false},
        },
        'serverInfo': {'name': 'flutter_ai_devtools', 'version': '0.1.0'},
      };
    case 'tools/list':
      return {'tools': dispatcher.toolManifests};
    case 'tools/call':
      final name = params['name'] as String?;
      if (name == null) throw const FormatException('"name" is required');
      // Ensure connected before calling — lazy connect with one retry burst.
      if (!await bridge.connect(vmUri)) {
        return ToolDispatcher.mcpError(
            'Flutter app not connected. Run: flutter run '
            '--vm-service-port=8181 --disable-service-auth-codes');
      }
      final toolArgs = params['arguments'] as Map<String, dynamic>? ?? {};
      final content = await dispatcher.dispatch(name, toolArgs);
      return ToolDispatcher.mcpResult(content);
    case 'ping':
      return {'pong': true};
    default:
      throw FormatException('Method not found: $method');
  }
}

void _write(Map<String, dynamic> msg) => stdout.writeln(jsonEncode(msg));

Map<String, dynamic> _error(dynamic id, int code, String message) => {
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      'error': {'code': code, 'message': message},
    };

String? _argString(List<String> args, String flag) {
  final idx = args.indexOf(flag);
  if (idx != -1 && idx + 1 < args.length) return args[idx + 1];
  final prefix = '$flag=';
  for (final a in args) {
    if (a.startsWith(prefix)) return a.substring(prefix.length);
  }
  return null;
}
