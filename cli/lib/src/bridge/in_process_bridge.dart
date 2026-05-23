import 'package:flutter_ai_devtools/flutter_ai_devtools.dart';
import '../server/sse_server.dart';
import '../server/stdio_server.dart';
import '../tools/tool_definitions.dart';
import '../tools/tool_dispatcher.dart';

class InProcessBridge {
  InProcessBridge._();

  static SseServer? _sseServer;
  static StdioServer? _stdioServer;

  /// Call this once at app startup (before FlutterAiDevtools.start()) to
  /// register the in-process MCP server factory.
  static void register() {
    FlutterAiDevtools.registerMcpStarter(_start);
  }

  static Future<Object> _start(
    int port,
    McpTransport transport,
    RuntimeStore store,
    List<Object> extraTools,
  ) async {
    final dispatcher = ToolDispatcher();
    registerDefaultTools(dispatcher, store);

    switch (transport) {
      case McpTransport.sse:
        _sseServer = SseServer(dispatcher: dispatcher, store: store);
        await _sseServer!.bind(port);
        return _sseServer!;
      case McpTransport.stdio:
        _stdioServer = StdioServer(dispatcher: dispatcher);
        _stdioServer!.start();
        return _stdioServer!;
      case McpTransport.none:
        throw ArgumentError('McpTransport.none should not reach _start');
    }
  }

  static Future<void> stop() async {
    await _sseServer?.stop();
    await _stdioServer?.stop();
    _sseServer = null;
    _stdioServer = null;
  }
}
