/// flutter_ai_devtools companion MCP server.
///
/// Connects lazily to a running Flutter app via the VM Service protocol.
/// Starts serving MCP over stdio immediately with a static tool list —
/// no need to have the app running before Claude Code launches this process.
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

// Lazy connection state.
VmService? _service;
Uri? _explicitUri;

Future<void> main(List<String> args) async {
  _explicitUri = _parseUriOrNull(args);
  stderr.writeln('[flutter_ai_devtools] MCP server ready.');
  unawaited(_tryConnect());
  await _serveMcp();
}

// ── Static tool definitions ────────────────────────────────────────────────
// Hardcoded so Claude always sees tools even before the app is running.

const _staticTools = [
  {
    'name': 'get_widget_tree',
    'description': 'Returns the current Flutter widget tree of the running app.',
    'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}, 'required': <String>[]},
  },
  {
    'name': 'get_current_route',
    'description': 'Returns the active navigation route of the running Flutter app.',
    'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}, 'required': <String>[]},
  },
  {
    'name': 'get_recent_errors',
    'description': 'Returns recent Flutter and platform errors captured by the app.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'limit': {'type': 'integer', 'description': 'Max number of errors to return (default 10).'},
      },
      'required': <String>[],
    },
  },
  {
    'name': 'get_render_issues',
    'description': 'Returns detected rendering issues such as overflow or large repaint regions.',
    'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}, 'required': <String>[]},
  },
  {
    'name': 'get_frame_stats',
    'description': 'Returns frame timing statistics including FPS and jank percentage.',
    'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}, 'required': <String>[]},
  },
  {
    'name': 'analyze_performance',
    'description': 'Runs the AI analyzer pipeline and returns performance insights and recommendations.',
    'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}, 'required': <String>[]},
  },
  {
    'name': 'analyze_rebuilds',
    'description': 'Analyzes widget rebuild counts and identifies widgets rebuilding too frequently.',
    'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}, 'required': <String>[]},
  },
  {
    'name': 'get_runtime_summary',
    'description': 'Returns a full runtime health snapshot: routes, errors, frames, rebuilds, and insights.',
    'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}, 'required': <String>[]},
  },
];

// ── Connection ─────────────────────────────────────────────────────────────

Future<bool> _tryConnect() async {
  if (_service != null) return true;

  final uri = _explicitUri ?? await _discoverVmServiceUri();
  if (uri == null) return false;

  try {
    stderr.writeln('[flutter_ai_devtools] Connecting to VM service: $uri');
    // Strip trailing slash to avoid ws://host:port//ws double-slash.
    final base = uri.toString().replaceAll(RegExp(r'/+$'), '');
    final wsBase = base.replaceFirst(RegExp(r'^http'), 'ws');
    final wsUrl = '$wsBase/ws';
    stderr.writeln('[flutter_ai_devtools] WebSocket: $wsUrl');
    _service = await vmServiceConnectUri(wsUrl);
    stderr.writeln('[flutter_ai_devtools] Connected to Flutter app.');
    return true;
  } catch (e) {
    _service = null;
    stderr.writeln('[flutter_ai_devtools] Connection failed: $e');
    return false;
  }
}

Future<VmService> _requireService() async {
  if (_service != null) return _service!;

  stderr.writeln('[flutter_ai_devtools] Connecting to Flutter app...');
  for (var attempt = 0; attempt < 10; attempt++) {
    if (await _tryConnect()) return _service!;
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  throw Exception(
    'Flutter app not reachable. Run "flutter run" first, then retry.',
  );
}

// ── VM Service helpers ──────────────────────────────────────────────────────

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
    final params = Map<String, dynamic>.from(request['params'] as Map? ?? {});

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
    'tools/list' => {'tools': _staticTools},
    'tools/call' => await _handleToolCall(params),
    'ping' => {'pong': true},
    null => throw Exception('method is required'),
    _ => throw Exception('Method not found: $method'),
  };
}

Future<Map<String, dynamic>> _handleToolCall(
  Map<String, dynamic> params,
) async {
  final name = params['name'] as String?;
  if (name == null) throw Exception('"name" is required');
  final args = Map<String, dynamic>.from(params['arguments'] as Map? ?? {});
  try {
    final result = await _callTool(name, args);
    return {
      'content': [
        {'type': 'text', 'text': jsonEncode(result)},
      ],
      'isError': false,
    };
  } catch (e) {
    return {
      'content': [
        {'type': 'text', 'text': e.toString()},
      ],
      'isError': true,
    };
  }
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
  // Check environment variable first — most reliable.
  final envUri = Platform.environment['FLUTTER_VM_SERVICE_URI'];
  if (envUri != null && envUri.isNotEmpty) {
    stderr.writeln('[flutter_ai_devtools] Using FLUTTER_VM_SERVICE_URI: $envUri');
    return Uri.parse(envUri);
  }

  // Scan ports Flutter commonly uses when --vm-service-port is set.
  stderr.writeln('[flutter_ai_devtools] Scanning common ports for Flutter VM service...');
  for (var port = 8080; port <= 8200; port++) {
    try {
      final socket = await Socket.connect('localhost', port,
          timeout: const Duration(milliseconds: 50));
      socket.destroy();
      stderr.writeln('[flutter_ai_devtools] Found open port: $port');
      return Uri.parse('http://localhost:$port');
    } catch (_) {}
  }

  stderr.writeln(
    '[flutter_ai_devtools] Auto-discovery failed.\n'
    'Fix: run your app with a fixed port:\n'
    '  flutter run --vm-service-port 8181\n'
    'Or set the env variable:\n'
    '  FLUTTER_VM_SERVICE_URI=http://127.0.0.1:<port>/<token>/',
  );
  return null;
}