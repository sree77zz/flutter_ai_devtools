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

  static NavigatorObserver get observer {
    _routeCollector ??= RouteCollector(
      store: _store ?? RuntimeStore(),
      config: const CollectorConfig(),
    );
    return _routeCollector!.observer;
  }

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

    // Start in reverse order so stop order (also reversed) chains correctly.
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
