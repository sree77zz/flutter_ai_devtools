/// flutter_ai_devtools companion MCP server.
///
/// Connects to a running Flutter app via the VM Service protocol,
/// calls ext.flutter_ai_devtools.* extensions, and serves them as
/// MCP tools over stdio to Claude Code / Claude Desktop / Cursor.
///
/// Usage:
///   dart run bin/devtools_mcp.dart [--vm-service-uri <uri>]
///
/// If --vm-service-uri is omitted, the tool auto-discovers the first
/// running Flutter app on localhost.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _ext = 'ext.flutter_ai_devtools';

Future<void> main(List<String> args) async {
  final uri = _parseUriOrNull(args) ?? await _discoverVmServiceUri();
  if (uri == null) {
    stderr.writeln(
      '[flutter_ai_devtools] Could not find a running Flutter app.\n'
      'Make sure your app is running with flutter run, then retry.\n'
      'Or pass --vm-service-uri <uri> explicitly.',
    );
    exit(1);
  }

  stderr.writeln('[flutter_ai_devtools] Connecting to VM service: $uri');
  final wsUri = uri.replace(scheme: uri.scheme == 'http' ? 'ws' : 'wss');
  final service = await vmServiceConnectUri('$wsUri/ws');

  // Discover available tools from the running app.
  final tools = await _listTools(service);
  if (tools.isEmpty) {
    stderr.writeln(
      '[flutter_ai_devtools] No tools found. '
      'Ensure FlutterAiAnalyst.initialize() was called in your app.',
    );
    exit(1);
  }

  stderr.writeln(
    '[flutter_ai_devtools] Found ${tools.length} tools. '
    'Serving MCP over stdio.',
  );

  await _serveMcp(service, tools);
}

// ── VM Service helpers ─────────────────────────────────────────────────────

Future<List<Map<String, dynamic>>> _listTools(VmService service) async {
  try {
    final isolateId = await _getMainIsolateId(service);
    final response = await service.callServiceExtension(
      '$_ext.list_tools',
      isolateId: isolateId,
    );
    final json =
        jsonDecode(response.json?['result'] as String? ?? '{}') as Map;
    return List<Map<String, dynamic>>.from(json['tools'] as List? ?? []);
  } catch (_) {
    return [];
  }
}

Future<String> _getMainIsolateId(VmService service) async {
  final vm = await service.getVM();
  final ref = vm.isolates?.first;
  if (ref == null) throw StateError('No isolates found');
  return ref.id!;
}

Future<dynamic> _callTool(
  VmService service,
  String toolName,
  Map<String, dynamic> args,
) async {
  final isolateId = await _getMainIsolateId(service);
  final stringArgs = args.map((k, v) => MapEntry(k, jsonEncode(v)));
  final response = await service.callServiceExtension(
    '$_ext.$toolName',
    isolateId: isolateId,
    args: stringArgs,
  );
  final resultStr = response.json?['result'] as String?;
  return resultStr != null ? jsonDecode(resultStr) : {};
}

// ── MCP stdio server ───────────────────────────────────────────────────────

Future<void> _serveMcp(
  VmService service,
  List<Map<String, dynamic>> tools,
) async {
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    Map<String, dynamic> request;
    try {
      request = Map<String, dynamic>.from(jsonDecode(line) as Map);
    } catch (_) {
      _write(_error(null, -32700, 'Parse error'));
      continue;
    }

    final id = request['id'];
    final method = request['method'] as String?;
    final params =
        Map<String, dynamic>.from(request['params'] as Map? ?? {});

    try {
      final result = await _dispatch(service, tools, method, params);
      if (id != null) {
        _write({'jsonrpc': '2.0', 'id': id, 'result': result});
      }
    } catch (e) {
      if (id != null) {
        _write(_error(id, -32603, e.toString()));
      }
    }
  }
}

Future<dynamic> _dispatch(
  VmService service,
  List<Map<String, dynamic>> tools,
  String? method,
  Map<String, dynamic> params,
) async {
  return switch (method) {
    'initialize' => {
        'protocolVersion': '2024-11-05',
        'capabilities': {
          'tools': {'listChanged': false},
        },
        'serverInfo': {
          'name': 'flutter_ai_devtools',
          'version': '0.1.0',
        },
      },
    'initialized' => null,
    'tools/list' => {'tools': tools},
    'tools/call' => await _handleToolCall(service, params),
    'ping' => {'pong': true},
    null => throw Exception('method is required'),
    _ => throw Exception('Method not found: $method'),
  };
}

Future<Map<String, dynamic>> _handleToolCall(
  VmService service,
  Map<String, dynamic> params,
) async {
  final name = params['name'] as String?;
  if (name == null) throw Exception('"name" is required');
  final args =
      Map<String, dynamic>.from(params['arguments'] as Map? ?? {});
  final result = await _callTool(service, name, args);
  return {
    'content': [
      {'type': 'text', 'text': jsonEncode(result)},
    ],
    'isError': false,
  };
}

void _write(Map<String, dynamic> json) {
  stdout.writeln(jsonEncode(json));
}

Map<String, dynamic> _error(dynamic id, int code, String message) => {
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      'error': {'code': code, 'message': message},
    };

// ── VM Service URI discovery ────────────────────────────────────────────────

Uri? _parseUriOrNull(List<String> args) {
  final idx = args.indexOf('--vm-service-uri');
  if (idx != -1 && idx + 1 < args.length) return Uri.parse(args[idx + 1]);
  return null;
}

/// Tries common localhost ports Flutter uses for the VM service (8181, 8182…).
Future<Uri?> _discoverVmServiceUri() async {
  stderr.writeln('[flutter_ai_devtools] Auto-discovering VM service...');
  for (var port = 8100; port <= 8200; port++) {
    try {
      final socket = await Socket.connect('localhost', port,
          timeout: const Duration(milliseconds: 100));
      socket.destroy();
      return Uri.parse('ws://localhost:$port');
    } catch (_) {}
  }
  return null;
}
