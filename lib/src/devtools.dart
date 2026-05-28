import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'collectors/base_collector.dart';
import 'collectors/error_collector.dart';
import 'collectors/frame_collector.dart';
import 'collectors/render_collector.dart';
import 'collectors/route_collector.dart';
import 'collectors/widget_collector.dart';
import 'config.dart';
import 'lockfile.dart';
import 'mcp/mcp_server.dart';
import 'mcp/sse_server.dart';
import 'mcp/stdio_server.dart';
import 'mcp/tool_definitions.dart';
import 'mcp/tool_dispatcher.dart';
import 'store/runtime_store.dart';

class FlutterAiDevtools {
  FlutterAiDevtools._();

  static RuntimeStore? _store;
  static RouteCollector? _routeCollector;
  static final List<BaseCollector> _collectors = [];
  static McpServer? _mcpServer;
  static bool _running = false;

  /// A permanent delegating observer that forwards navigation events to the
  /// current [_routeCollector] (if any). Safe to register with [MaterialApp]
  /// before [start] is called — it becomes a no-op until [start] initialises
  /// [_routeCollector], and reverts to a no-op again after [stop].
  static final NavigatorObserver observer = _DelegatingNavigatorObserver();

  static RuntimeStore? get store => _store;

  static Future<void> start({
    int port = 8765,
    McpTransport transport = McpTransport.sse,
    CollectorConfig collectors = const CollectorConfig(),
    List<Object> extraTools = const [],
  }) async {
    if (_running) await stop();
    _running = true;

    _store = RuntimeStore(
      maxErrors: collectors.maxErrors,
      maxFrames: collectors.maxFrames,
      maxRenderIssues: collectors.maxRenderIssues,
    );

    if (collectors.routes) {
      _routeCollector = RouteCollector(store: _store!, config: collectors);
    }

    _collectors.clear();
    if (collectors.widgets) {
      _collectors.add(WidgetCollector(store: _store!, config: collectors));
    }
    if (collectors.errors) {
      _collectors.add(ErrorCollector(store: _store!, config: collectors));
    }
    if (collectors.frames) {
      _collectors.add(FrameCollector(store: _store!, config: collectors));
    }
    if (collectors.renders) {
      _collectors.add(RenderCollector(store: _store!, config: collectors));
    }

    // RenderCollector and ErrorCollector both hook FlutterError.onError, so stop must reverse start order.
    for (final c in _collectors) {
      await c.start();
    }

    if (transport != McpTransport.none) {
      await _startMcp(port, transport, extraTools);
    }
  }

  static Future<void> stop() async {
    // Stop in reverse order to correctly unchain FlutterError handlers.
    for (final c in _collectors.reversed) {
      await c.stop();
    }
    _collectors.clear();
    await _mcpServer?.stop();
    _mcpServer = null;
    _routeCollector = null;
    await deleteLockfile();
    _store = null;
    _running = false;
  }

  static Future<void> _startMcp(
      int port, McpTransport transport, List<Object> extraTools) async {
    if (kIsWeb) return; // dart:io not available on Flutter Web

    final dispatcher = ToolDispatcher();
    registerDefaultTools(dispatcher, _store!);

    switch (transport) {
      case McpTransport.sse:
        final server = SseServer(dispatcher: dispatcher, store: _store!);
        await server.bind(port);
        _mcpServer = server;
      case McpTransport.stdio:
        final server = StdioServer(dispatcher: dispatcher);
        server.start();
        _mcpServer = server;
      case McpTransport.none:
        return;
    }
    await writeLockfile(mcpPort: port);
  }
}

class _DelegatingNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      FlutterAiDevtools._routeCollector?.observer.didPush(route, previousRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      FlutterAiDevtools._routeCollector?.observer.didPop(route, previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      FlutterAiDevtools._routeCollector?.observer
          .didReplace(newRoute: newRoute, oldRoute: oldRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      FlutterAiDevtools._routeCollector?.observer
          .didRemove(route, previousRoute);
}
