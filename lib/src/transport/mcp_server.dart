import 'dart:async';
import 'dart:convert';
// dart:io is available on Android/iOS/macOS/Linux/Windows but NOT on web.
// MCP stdio/TCP transports are only meaningful on native targets anyway.
import 'dart:io' show stdin, stdout, ServerSocket, Socket;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uuid/uuid.dart';

import '../core/runtime_store.dart';
import '../core/tool_registry.dart';
import '../logging/analyst_logger.dart';
import '../services/metrics_service.dart';
import 'security_middleware.dart';
import 'session_manager.dart';

/// MCP-compatible JSON-RPC 2.0 server that exposes analyst tools over stdio
/// or a TCP socket.
///
/// The MCP protocol (Model Context Protocol) specifies a JSON-RPC 2.0
/// transport. This server implements:
///   - initialize / initialized handshake
///   - tools/list  â€” returns registered tool manifests
///   - tools/call  â€” dispatches to [ToolRegistry]
///
/// Two transports are supported:
///   - [startStdio] â€” communicate via stdin/stdout (compatible with Claude
///     Desktop, Cursor, VSCode MCP extensions)
///   - [startTcp]   â€” listen on a TCP port for remote AI clients
class AnalystMcpServer {
  AnalystMcpServer({
    required ToolRegistry toolRegistry,
    required RuntimeStore store,
    required SecurityMiddleware security,
    required SessionManager sessionManager,
  })  : _toolRegistry = toolRegistry,
        _store = store,
        _security = security,
        _sessionManager = sessionManager;

  final ToolRegistry _toolRegistry;
  final RuntimeStore _store;
  final SecurityMiddleware _security;
  final SessionManager _sessionManager;
  final _log = AnalystLogger.forName('McpServer');
  final _uuid = const Uuid();

  bool _running = false;
  ServerSocket? _serverSocket;
  StreamSubscription<String>? _stdioSub;

  // â”€â”€ Public API â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Start an MCP server reading from stdin and writing to stdout.
  ///
  /// This is the standard transport for Claude Desktop and most AI IDE
  /// integrations. Only supported on native (non-web) targets.
  Future<void> startStdio() async {
    _assertNative('startStdio');
    _running = true;
    _log.info('MCP server starting (stdio transport)');
    final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
    _stdioSub = lines.listen(
      (line) => _handleLine(line, _writeStdout),
      onError: (e) => _log.error('Stdio read error', e),
      onDone: () {
        _running = false;
        _log.info('Stdio stream closed');
      },
    );
  }

  /// Start an MCP server listening on [port].
  ///
  /// Only supported on native (non-web) targets.
  Future<void> startTcp({int port = 8765, String host = 'localhost'}) async {
    _assertNative('startTcp');
    _running = true;
    _serverSocket = await ServerSocket.bind(host, port);
    _log.info('MCP server listening on $host:$port');
    _serverSocket!.listen(
      _handleTcpSocket,
      onError: (e) => _log.error('ServerSocket error', e),
      onDone: () {
        _running = false;
        _log.info('Server socket closed');
      },
    );
  }

  void _assertNative(String method) {
    if (kIsWeb) {
      throw UnsupportedError(
        'AnalystMcpServer.$method is not supported on Flutter Web. '
        'Use a native (Android/iOS/desktop) target.',
      );
    }
  }

  Future<void> stop() async {
    _running = false;
    await _stdioSub?.cancel();
    await _serverSocket?.close();
    _log.info('MCP server stopped');
  }

  bool get isRunning => _running;

  // â”€â”€ Transport handlers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _handleTcpSocket(Socket socket) {
    // Reject unauthenticated connections when tokens are configured.
    if (!_security.authorize(null)) {
      socket.write(
        '${jsonEncode(_errorResponse(null, -32001, 'Unauthorized'))}\n',
      );
      socket.close();
      return;
    }

    final sessionId = _uuid.v4();
    _sessionManager.createSession(
      sessionId: sessionId,
      clientId: socket.remoteAddress.address,
    );
    _log.info(
      'TCP client connected: ${socket.remoteAddress.address}:${socket.remotePort}',
    );

    void write(Map<String, dynamic> json) {
      try {
        socket.write('${jsonEncode(json)}\n');
      } catch (e) {
        _log.warning('Failed to write to socket $sessionId', e);
      }
    }

    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            _sessionManager.touchSession(sessionId);
            _handleLine(line, write);
          },
          onError: (e) {
            _log.warning('Socket error $sessionId', e);
            _sessionManager.removeSession(sessionId);
          },
          onDone: () {
            _sessionManager.removeSession(sessionId);
            _log.info('TCP client disconnected: $sessionId');
          },
        );
  }

  void _writeStdout(Map<String, dynamic> json) {
    stdout.writeln(jsonEncode(json));
  }

  // â”€â”€ Protocol handling â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _handleLine(
    String line,
    void Function(Map<String, dynamic>) write,
  ) async {
    if (line.trim().isEmpty) return;
    Map<String, dynamic> request;
    try {
      request = Map<String, dynamic>.from(jsonDecode(line) as Map);
    } catch (e) {
      write(_errorResponse(null, -32700, 'Parse error: $e'));
      return;
    }

    final id = request['id'];
    final method = request['method'] as String?;
    final params =
        request['params'] as Map<String, dynamic>? ?? const {};

    MetricsService.instance.increment('mcp.requests');

    try {
      final result = await _dispatch(method, params);
      if (id != null) {
        write({'jsonrpc': '2.0', 'id': id, 'result': result});
      }
    } catch (e, st) {
      _log.warning('Error handling method "$method"', e, st);
      MetricsService.instance.increment('mcp.errors');
      if (id != null) {
        write(_errorResponse(id, -32603, e.toString()));
      }
    }
  }

  Future<dynamic> _dispatch(
    String? method,
    Map<String, dynamic> params,
  ) async {
    return switch (method) {
      'initialize' => _handleInitialize(params),
      'initialized' => null,
      'tools/list' => _handleToolsList(),
      'tools/call' => _handleToolCall(params),
      'ping' => {'pong': true, 'timestamp': DateTime.now().toIso8601String()},
      null => throw Exception('Method is required'),
      _ => throw Exception('Method not found: $method'),
    };
  }

  Map<String, dynamic> _handleInitialize(Map<String, dynamic> params) {
    final clientInfo = params['clientInfo'] as Map<String, dynamic>?;
    _log.info(
      'Client initialized: ${clientInfo?['name']} ${clientInfo?['version']}',
    );
    return {
      'protocolVersion': '2024-11-05',
      'capabilities': {
        'tools': {'listChanged': false},
      },
      'serverInfo': {
        'name': 'flutter_ai_devtools',
        'version': '0.1.0',
        'description':
            'AI-native Flutter runtime intelligence platform. Inspect widget '
            'trees, errors, frame stats, routes, and render issues in real time.',
      },
    };
  }

  Map<String, dynamic> _handleToolsList() {
    final tools = _toolRegistry.all.map((t) => {
          'name': t.name,
          'description': t.description,
          'inputSchema': t.inputSchema,
        }).toList();
    return {'tools': tools};
  }

  Future<Map<String, dynamic>> _handleToolCall(
    Map<String, dynamic> params,
  ) async {
    final toolName = params['name'] as String?;
    if (toolName == null) {
      throw Exception('tools/call requires "name" parameter');
    }

    final tool = _toolRegistry.find(toolName);
    if (tool == null) {
      throw Exception('Tool not found: $toolName');
    }

    final arguments =
        Map<String, dynamic>.from(params['arguments'] as Map? ?? {});

    final stopwatch = Stopwatch()..start();
    final result = await tool.execute(arguments, _store);
    stopwatch.stop();

    MetricsService.instance
        .record('mcp.tool.$toolName.ms', stopwatch.elapsedMilliseconds.toDouble());
    _log.debug('Tool "$toolName" executed in ${stopwatch.elapsedMilliseconds}ms');

    return {
      'content': [
        {
          'type': 'text',
          'text': jsonEncode(result.toJson()),
        }
      ],
      'isError': result.isError,
    };
  }

  Map<String, dynamic> _errorResponse(dynamic id, int code, String message) =>
      {
        'jsonrpc': '2.0',
        if (id != null) 'id': id,
        'error': {'code': code, 'message': message},
      };
}
