import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../store/runtime_store.dart';
import 'mcp_server.dart';
import 'tool_dispatcher.dart';

class SseServer implements McpServer {
  SseServer({required this.dispatcher, required this.store});

  final ToolDispatcher dispatcher;
  final RuntimeStore store;
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _sub;
  final _sessions = <String, StreamController<String>>{};
  final _uuid = const Uuid();

  /// Binds to [port] (0 = OS-assigned free port) and returns the actual port.
  /// Completes only after the server is actively listening.
  Future<int> bind(int port, {String host = 'localhost'}) async {
    _server = await HttpServer.bind(host, port);
    _sub = _server!.listen(_handle, onError: (e) {
      stderr.writeln('[SseServer] Error: $e');
    });
    return _server!.port;
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    for (final c in _sessions.values.toList()) {
      await c.close();
    }
    _sessions.clear();
    await _server?.close(force: true);
    _server = null;
  }

  void _handle(HttpRequest req) {
    if (req.method == 'GET' && req.uri.path == '/sse') {
      _handleSse(req);
    } else if (req.method == 'POST') {
      _handlePost(req);
    } else if (req.method == 'GET' && req.uri.path == '/health') {
      req.response.statusCode = 200;
      req.response.write('ok');
      req.response.close();
    } else {
      req.response.statusCode = 404;
      req.response.close();
    }
  }

  Future<void> _handleSse(HttpRequest req) async {
    final sessionId = _uuid.v4();
    final controller = StreamController<String>();
    _sessions[sessionId] = controller;

    try {
      req.response.bufferOutput = false;
      req.response.statusCode = 200;
      req.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      req.response.headers.add('Cache-Control', 'no-cache');
      req.response.headers.add('Connection', 'keep-alive');
      req.response.headers.add('Access-Control-Allow-Origin', '*');

      req.response.write('event: endpoint\ndata: /\n\n');

      // Close the controller when the client disconnects.
      unawaited(req.response.done.then((_) {
        if (!controller.isClosed) controller.close();
      }, onError: (_) {
        if (!controller.isClosed) controller.close();
      }));

      await for (final msg in controller.stream) {
        try {
          req.response.write('data: $msg\n\n');
        } catch (_) {
          break;
        }
      }
      try {
        await req.response.close();
      } catch (_) {}
    } finally {
      _sessions.remove(sessionId);
      if (!controller.isClosed) await controller.close();
    }
  }

  Future<void> _handlePost(HttpRequest req) async {
    req.response.headers.add('Access-Control-Allow-Origin', '*');
    final body = await req
        .cast<List<int>>()
        .transform(utf8.decoder)
        .join();
    Map<String, dynamic> rpc;
    try {
      rpc = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      req.response.statusCode = 400;
      req.response.write(jsonEncode(_error(null, -32700, 'Parse error')));
      await req.response.close();
      return;
    }

    final id = rpc['id'];
    final method = rpc['method'] as String?;
    final params = rpc['params'] as Map<String, dynamic>? ?? {};

    try {
      final result = await _dispatch(method, params);
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
          jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}));
      await req.response.close();
    } catch (e) {
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(_error(id, -32603, e.toString())));
      await req.response.close();
    }
  }

  Future<Map<String, dynamic>> _dispatch(
      String? method, Map<String, dynamic> params) async {
    switch (method) {
      case 'initialize':
        return {
          'protocolVersion': '2024-11-05',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'flutter_ai_devtools', 'version': '0.1.0'},
        };
      case 'initialized':
        return {};
      case 'tools/list':
        return {'tools': dispatcher.toolManifests};
      case 'tools/call':
        final name = params['name'];
        if (name is! String) {
          throw const FormatException('tools/call requires string "name"');
        }
        final args = params['arguments'] as Map<String, dynamic>? ?? {};
        final content = await dispatcher.dispatch(name, args);
        return ToolDispatcher.mcpResult(content);
      case 'ping':
        return {'timestamp': DateTime.now().toIso8601String()};
      default:
        throw FormatException('Method not found: $method');
    }
  }

  Map<String, dynamic> _error(dynamic id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };
}
