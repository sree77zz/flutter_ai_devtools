import 'package:flutter/widgets.dart';

import 'collectors/base_collector.dart';
import 'collectors/error_collector.dart';
import 'collectors/frame_collector.dart';
import 'collectors/render_collector.dart';
import 'collectors/route_collector.dart';
import 'collectors/widget_collector.dart';
import 'config.dart';
import 'lockfile.dart';
import 'store/runtime_store.dart';

class FlutterAiDevtools {
  FlutterAiDevtools._();

  static RuntimeStore? _store;
  static RouteCollector? _routeCollector;
  static final List<BaseCollector> _collectors = [];
  static dynamic _mcpServer;

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
    _store = RuntimeStore(
      maxErrors: collectors.maxErrors,
      maxFrames: collectors.maxFrames,
      maxRenderIssues: collectors.maxRenderIssues,
    );

    _routeCollector = RouteCollector(store: _store!, config: collectors);

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

    if (transport != McpTransport.none && _mcpStarter != null) {
      _mcpServer = await _mcpStarter!(port, transport, _store!, extraTools);
      await writeLockfile(mcpPort: port);
    }
  }

  static Future<void> stop() async {
    // Stop in reverse order to correctly unchain FlutterError handlers.
    for (final c in _collectors.reversed) {
      await c.stop();
    }
    _collectors.clear();
    await (_mcpServer as dynamic)?.stop();
    _mcpServer = null;
    _routeCollector = null;
    await deleteLockfile();
    _store = null;
  }

  static Future<Object> Function(
    int port,
    McpTransport transport,
    RuntimeStore store,
    List<Object> extraTools,
  )? _mcpStarter;

  static void registerMcpStarter(
    Future<Object> Function(int, McpTransport, RuntimeStore, List<Object>)
        starter,
  ) {
    _mcpStarter = starter;
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
