import 'dart:async';
import 'dart:convert';
// dart:io is available on Android/iOS/macOS/Linux/Windows but NOT on web.
// MCP stdio/TCP transports are only meaningful on native targets anyway.
import 'dart:io'
    show
        ContentType,
        HttpRequest,
        HttpServer,
        ServerSocket,
        Socket,
        stdin,
        stdout;

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
  HttpServer? _httpServer;
  StreamSubscription<String>? _stdioSub;
  final _sseSessions = <String, StreamController<String>>{};

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

  /// Start an MCP server over HTTP + Server-Sent Events (SSE).
  ///
  /// Claude Code connects with:
  ///   claude mcp add flutter-ai-devtools --transport sse http://localhost:[port]/sse
  ///
  /// Only supported on native (non-web) targets.
  Future<void> startSse({int port = 8765, String host = 'localhost'}) async {
    _assertNative('startSse');
    _running = true;
    _httpServer = await HttpServer.bind(host, port);
    _log.info('MCP SSE server listening on http://$host:$port/sse');

    _httpServer!.listen((HttpRequest req) async {
      req.response.headers
        ..add('Access-Control-Allow-Origin', '*')
        ..add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        ..add('Access-Control-Allow-Headers', 'Content-Type');

      if (req.method == 'OPTIONS') {
        req.response.statusCode = 200;
        await req.response.close();
        return;
      }

      if (req.uri.path == '/sse' && req.method == 'GET') {
        await _handleSseUpgrade(req);
      } else if (req.uri.path == '/message' && req.method == 'POST') {
        await _handleSseMessage(req);
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });
  }

  Future<void> _handleSseUpgrade(HttpRequest req) async {
    final sessionId = _uuid.v4();
    final controller = StreamController<String>();
    _sseSessions[sessionId] = controller;

    req.response
      ..statusCode = 200
      ..headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8')
      ..headers.add('Cache-Control', 'no-cache')
      ..headers.add('Connection', 'keep-alive');

    req.response.write('event: endpoint\ndata: /message?sessionId=$sessionId\n\n');
    await req.response.flush();

    _log.info('SSE client connected: $sessionId');
    _sessionManager.createSession(sessionId: sessionId, clientId: sessionId);

    try {
      await for (final event in controller.stream) {
        req.response.write('event: message\ndata: $event\n\n');
        await req.response.flush();
      }
    } catch (_) {
      // Client disconnected.
    } finally {
      _sseSessions.remove(sessionId);
      _sessionManager.removeSession(sessionId);
      if (!controller.isClosed) await controller.close();
      await req.response.close();
      _log.info('SSE client disconnected: $sessionId');
    }
  }

  Future<void> _handleSseMessage(HttpRequest req) async {
    final sessionId = req.uri.queryParameters['sessionId'];
    // ignore: close_sinks — owned and closed by _handleSseUpgrade's finally block.
    final controller = sessionId != null ? _sseSessions[sessionId] : null;

    final body = await utf8.decoder.bind(req).join();

    req.response.statusCode = 202;
    await req.response.close();

    if (controller == null || controller.isClosed) return;

    void write(Map<String, dynamic> json) {
      if (!controller.isClosed) controller.add(jsonEncode(json));
    }

    await _handleLine(body, write);
  }

  Future<void> stop() async {
    _running = false;
    await _stdioSub?.cancel();
    await _serverSocket?.close();
    await _httpServer?.close(force: true);
    for (final c in _sseSessions.values) {
      await c.close();
    }
    _sseSessions.clear();
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
