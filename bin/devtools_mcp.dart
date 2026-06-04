// bin/devtools_mcp.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_ai_devtools/src/bridge/vm_bridge.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_definitions.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_dispatcher.dart';

Future<void> main(List<String> args) async {
  final bridge = VmBridge();
  bridge.start(); // resilient connect loop; never blocks, never dies.

  final dispatcher = ToolDispatcher();
  registerBridgeTools(dispatcher, bridge);

  await _serveStdio(dispatcher);
  await bridge.dispose();
}

Future<void> _serveStdio(ToolDispatcher dispatcher) async {
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    Map<String, dynamic> req;
    try {
      req = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      _write(_error(null, -32700, 'Parse error'));
      continue;
    }
    if (!req.containsKey('id')) continue; // notification

    final id = req['id'];
    final method = req['method'] as String?;
    final params = req['params'] as Map<String, dynamic>? ?? {};
    try {
      final result = await _dispatch(method, params, dispatcher);
      _write({'jsonrpc': '2.0', 'id': id, 'result': result});
    } catch (e) {
      _write(_error(id, _codeForError(e), e.toString()));
    }
  }
}

Future<Object?> _dispatch(
  String? method,
  Map<String, dynamic> params,
  ToolDispatcher dispatcher,
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

/// Maps an unknown method or tool name to JSON-RPC -32601 (Method Not Found);
/// everything else is -32603 (Internal Error).
int _codeForError(Object e) {
  if (e is ToolNotFoundException) return -32601;
  if (e is FormatException && e.message.startsWith('Method not found')) {
    return -32601;
  }
  return -32603;
}

Map<String, dynamic> _error(dynamic id, int code, String message) => {
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      'error': {'code': code, 'message': message},
    };
