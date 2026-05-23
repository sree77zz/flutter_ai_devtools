import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../tools/tool_dispatcher.dart';

class StdioServer {
  StdioServer({required this.dispatcher});

  final ToolDispatcher dispatcher;
  StreamSubscription<String>? _sub;

  void start() {
    _sub = stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onError: (_) => stop(), onDone: stop);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _onLine(String line) async {
    if (line.trim().isEmpty) return;
    Map<String, dynamic> rpc;
    try {
      rpc = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      _write(_error(null, -32700, 'Parse error'));
      return;
    }

    final id = rpc['id'];
    final method = rpc['method'] as String?;
    final params = rpc['params'] as Map<String, dynamic>? ?? {};

    try {
      final result = await _dispatch(method, params);
      _write({'jsonrpc': '2.0', 'id': id, 'result': result});
    } catch (e) {
      _write(_error(id, -32603, e.toString()));
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
        final name = params['name'] as String;
        final args = params['arguments'] as Map<String, dynamic>? ?? {};
        final content = await dispatcher.dispatch(name, args);
        return ToolDispatcher.mcpResult(content);
      case 'ping':
        return {'timestamp': DateTime.now().toIso8601String()};
      default:
        throw 'Method not found: $method';
    }
  }

  void _write(Map<String, dynamic> msg) {
    stdout.writeln(jsonEncode(msg));
  }

  Map<String, dynamic> _error(dynamic id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}
