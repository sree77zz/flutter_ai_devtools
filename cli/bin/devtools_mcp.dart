/// flutter_ai_devtools companion MCP server.
///
/// Connects lazily to a running Flutter app via the VM Service protocol.
/// Starts serving MCP over stdio immediately — no need to have the app
/// running before Claude Code launches this process.
///
/// Usage:
///   devtools_mcp [--vm-service-uri <uri>]
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _ext = 'ext.flutter_ai_devtools';

// Lazy connection state — populated on first tool call.
VmService? _service;
List<Map<String, dynamic>> _cachedTools = [];
Uri? _explicitUri;

Future<void> main(List<String> args) async {
  _explicitUri = _parseUriOrNull(args);
  stderr.writeln('[flutter_ai_devtools] MCP server ready. Waiting for tool calls...');

  // Try connecting in the background so tools/list populates early.
  unawaited(_tryConnect());

  await _serveMcp();
}

// ── Connection ─────────────────────────────────────────────────────────────

Future<bool> _tryConnect() async {
  if (_service != null) return true;

  final uri = _explicitUri ?? await _discoverVmServiceUri();
  if (uri == null) return false;

  try {
    stderr.writeln('[flutter_ai_devtools] Connecting to VM service: $uri');
    final wsUri = uri.replace(scheme: uri.scheme == 'http' ? 'ws' : 'wss');
    _service = await vmServiceConnectUri('$wsUri/ws');
    _cachedTools = await _listTools(_service!);
    stderr.writeln(
      '[flutter_ai_devtools] Connected. ${_cachedTools.length} tools available.',
    );
    return true;
  } catch (e) {
    _service = null;
    stderr.writeln('[flutter_ai_devtools] Connection failed: $e');
    return false;
  }
}

/// Ensures we have a live connection, retrying if needed.
Future<VmService> _requireService() async {
  if (_service != null) return _service!;

  stderr.writeln('[flutter_ai_devtools] Attempting to connect to Flutter app...');
  for (var attempt = 0; attempt < 10; attempt++) {
    if (await _tryConnect()) return _service!;
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  throw Exception(
    'Flutter app not found. Make sure it is running with "flutter run", '
    'then try again. Or restart Claude Code after starting the app.',
  );
}

// ── VM Service helpers ──────────────────────────────────────────────────────

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
  String toolName,
  Map<String, dynamic> args,
) async {
  final service = await _requireService();
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

// ── MCP stdio server ────────────────────────────────────────────────────────

Future<void> _serveMcp() async {
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
      final result = await _dispatch(method, params);
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
    'tools/list' => {
        // Return cached tools, or attempt a connection to populate them.
        'tools': _cachedTools.isNotEmpty
            ? _cachedTools
            : await _fetchToolsOrEmpty(),
      },
    'tools/call' => await _handleToolCall(params),
    'ping' => {'pong': true},
    null => throw Exception('method is required'),
    _ => throw Exception('Method not found: $method'),
  };
}

Future<List<Map<String, dynamic>>> _fetchToolsOrEmpty() async {
  try {
    if (await _tryConnect()) return _cachedTools;
  } catch (_) {}
  return [];
}

Future<Map<String, dynamic>> _handleToolCall(
  Map<String, dynamic> params,
) async {
  final name = params['name'] as String?;
  if (name == null) throw Exception('"name" is required');
  final args =
      Map<String, dynamic>.from(params['arguments'] as Map? ?? {});
  final result = await _callTool(name, args);
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

// ── URI discovery ───────────────────────────────────────────────────────────

Uri? _parseUriOrNull(List<String> args) {
  final idx = args.indexOf('--vm-service-uri');
  if (idx != -1 && idx + 1 < args.length) return Uri.parse(args[idx + 1]);
  return null;
}

Future<Uri?> _discoverVmServiceUri() async {
  stderr.writeln('[flutter_ai_devtools] Scanning for Flutter app on localhost...');
  for (var port = 8100; port <= 8200; port++) {
    try {
      final socket = await Socket.connect(
        'localhost',
        port,
        timeout: const Duration(milliseconds: 100),
      );
      socket.destroy();
      stderr.writeln('[flutter_ai_devtools] Found open port: $port');
      return Uri.parse('http://localhost:$port');
    } catch (_) {}
  }
  return null;
}