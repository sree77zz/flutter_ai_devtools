import 'dart:async' show Future, unawaited;

import 'package:flutter/widgets.dart';

import '../adapters/base_adapter.dart';
import '../collectors/base_collector.dart';
import '../collectors/error_collector.dart';
import '../collectors/frame_collector.dart';
import '../collectors/render_collector.dart';
import '../collectors/route_collector.dart';
import '../collectors/widget_collector.dart';
import '../logging/analyst_logger.dart';
import '../logging/error_handler.dart';
import '../services/config_manager.dart';
import '../services/data_normalizer.dart';
import '../services/metrics_service.dart';
import '../services/notifier_service.dart';
import '../services/scheduler.dart';
import '../tools/base_tool.dart';
import '../tools/error_tool.dart';
import '../tools/frame_tool.dart';
import '../tools/performance_tool.dart';
import '../tools/rebuild_tool.dart';
import '../tools/render_tool.dart';
import '../tools/route_tool.dart';
import '../tools/summary_tool.dart';
import '../tools/widget_tree_tool.dart';
import '../transport/mcp_server.dart';
import '../transport/security_middleware.dart';
import '../transport/session_manager.dart';
import 'analyzer_engine.dart';
import 'event_bus.dart';
import 'extension_registry.dart';
import 'runtime_store.dart';
import 'tool_registry.dart';

enum EngineState { idle, starting, running, stopping, stopped }

/// The central orchestrator of the flutter_ai_devtools platform.
///
/// [AnalystEngine] wires together all subsystems: collectors, adapters,
/// the event bus, runtime store, analyzer pipeline, and MCP server.
///
/// Typical usage â€” call once in main():
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await FlutterAiAnalyst.initialize();
///   runApp(const MyApp());
/// }
/// ```
class AnalystEngine {
  AnalystEngine._({required AnalystConfig config}) {
    _configManager = ConfigManager(config);
    _eventBus = EventBus();
    _store = RuntimeStore(_configManager);
    _notifier = NotifierService();
    _scheduler = SchedulerService();
    _normalizer = DataNormalizer();
    _analyzerEngine = AnalyzerEngine(
      eventBus: _eventBus,
      store: _store,
    );
    _toolRegistry = ToolRegistry();
    _extensionRegistry = ExtensionRegistry();
  }

  static AnalystEngine? _instance;

  static AnalystEngine get instance {
    assert(
      _instance != null,
      'AnalystEngine not initialized. Call FlutterAiAnalyst.initialize() first.',
    );
    return _instance!;
  }

  static bool get isInitialized => _instance != null;

  late final ConfigManager _configManager;
  late final EventBus _eventBus;
  late final RuntimeStore _store;
  late final NotifierService _notifier;
  late final SchedulerService _scheduler;
  late final DataNormalizer _normalizer;
  late final AnalyzerEngine _analyzerEngine;
  late final ToolRegistry _toolRegistry;
  late final ExtensionRegistry _extensionRegistry;

  final _collectors = <String, BaseCollector>{};
  AnalystMcpServer? _mcpServer;
  EngineState _state = EngineState.idle;

  final _log = AnalystLogger.forName('Engine');

  // â”€â”€ Public accessors â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  EventBus get eventBus => _eventBus;
  RuntimeStore get store => _store;
  ToolRegistry get toolRegistry => _toolRegistry;
  ExtensionRegistry get extensionRegistry => _extensionRegistry;
  AnalyzerEngine get analyzerEngine => _analyzerEngine;
  ConfigManager get configManager => _configManager;
  AnalystMcpServer? get mcpServer => _mcpServer;
  EngineState get state => _state;

  /// The [NavigatorObserver] to attach to your app's Navigator.
  NavigatorObserver get navigatorObserver =>
      (_collectors['route_collector'] as RouteCollector).observer;

  // â”€â”€ Lifecycle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<AnalystEngine> create(AnalystConfig config) async {
    if (_instance != null) {
      _instance!._log.warning(
        'AnalystEngine.create() called more than once; returning existing instance.',
      );
      return _instance!;
    }
    final engine = AnalystEngine._(config: config);
    await engine._initialize();
    _instance = engine;
    return engine;
  }

  Future<void> _initialize() async {
    _state = EngineState.starting;
    _log.info('Initializing AnalystEngine v0.1.0');

    AnalystErrorHandler.instance.addListener((e, st) {
      _log.error('Unhandled engine error', e, st);
    });

    _registerDefaultCollectors();
    _registerDefaultTools();
    _registerDefaultAnalyzerSteps();

    await _startCollectors();
    await _extensionRegistry.startAll();

    _setupEventRouting();
    _setupScheduler();
    _setupMcpServer();

    _state = EngineState.running;
    _log.info('AnalystEngine running. MCP server: ${_mcpServer != null}');
  }

  Future<void> shutdown() async {
    if (_state == EngineState.stopping || _state == EngineState.stopped) return;
    _state = EngineState.stopping;
    _log.info('Shutting down AnalystEngine');

    _scheduler.cancelAll();
    await _mcpServer?.stop();

    for (final c in _collectors.values) {
      try {
        await c.stop();
      } catch (e) {
        _log.warning('Error stopping collector ${c.id}', e);
      }
    }

    await _extensionRegistry.stopAll();
    await _eventBus.dispose();

    _state = EngineState.stopped;
    _instance = null;
    _log.info('AnalystEngine stopped');
  }

  // â”€â”€ Registration â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _registerDefaultCollectors() {
    final cfg = _configManager;

    if (cfg.current.enableWidgetCollector) {
      _collectors['widget_collector'] = WidgetCollector(
        eventBus: _eventBus,
        config: cfg,
        store: _store,
      );
    }
    if (cfg.current.enableErrorCollector) {
      _collectors['error_collector'] = ErrorCollector(
        eventBus: _eventBus,
        config: cfg,
        store: _store,
      );
    }
    if (cfg.current.enableRouteCollector) {
      _collectors['route_collector'] = RouteCollector(
        eventBus: _eventBus,
        config: cfg,
        store: _store,
      );
    }
    if (cfg.current.enableFrameCollector) {
      _collectors['frame_collector'] = FrameCollector(
        eventBus: _eventBus,
        config: cfg,
        store: _store,
      );
    }
    if (cfg.current.enableRenderCollector) {
      _collectors['render_collector'] = RenderCollector(
        eventBus: _eventBus,
        config: cfg,
        store: _store,
      );
    }
  }

  Future<void> _startCollectors() async {
    for (final c in _collectors.values) {
      try {
        await c.start();
      } catch (e, st) {
        _log.error('Failed to start collector ${c.id}', e, st);
      }
    }
  }

  void _registerDefaultTools() {
    final tools = <AnalystTool>[
      GetWidgetTreeTool(),
      GetCurrentRouteTool(),
      GetRecentErrorsTool(),
      GetRenderIssuesTool(),
      GetFrameStatsTool(),
      AnalyzePerformanceTool(_analyzerEngine),
      AnalyzeRebuildsTool(),
      GetRuntimeSummaryTool(),
    ];
    for (final t in tools) {
      _toolRegistry.register(t);
    }
  }

  void _registerDefaultAnalyzerSteps() {
    _analyzerEngine
      ..addStep(JankAnalyzerStep())
      ..addStep(RebuildAnalyzerStep())
      ..addStep(RenderIssueAnalyzerStep());
  }

  // â”€â”€ Adapter registration (public API) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void registerAdapter(AnalystAdapter adapter) {
    _extensionRegistry.register(adapter);
    if (_state == EngineState.running) {
      unawaited(adapter.start());
    }
  }

  // â”€â”€ Tool registration (public API) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void registerTool(AnalystTool tool) {
    _toolRegistry.register(tool);
  }

  // â”€â”€ Event routing â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _setupEventRouting() {
    _eventBus.events.listen((event) {
      final normalized = _normalizer.normalize(event);
      _store.ingest(normalized);
      unawaited(_notifier.evaluate(normalized));
      MetricsService.instance.increment('events.total');
      MetricsService.instance.increment('events.${event.type.name}');
    });
  }

  // â”€â”€ Scheduler â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _setupScheduler() {
    final intervalMs = _configManager.current.analyzerPipelineIntervalMs;
    _scheduler.schedule(
      key: 'analyzer_pipeline',
      interval: Duration(milliseconds: intervalMs),
      task: () => unawaited(_analyzerEngine.runPipeline()),
    );

    if (_configManager.current.enableMetrics) {
      _scheduler.schedule(
        key: 'metrics_gauge',
        interval: const Duration(seconds: 30),
        task: () {
          MetricsService.instance
              .gauge('store.errors', _store.recentErrors.length.toDouble());
          MetricsService.instance
              .gauge('store.frames', _store.recentFrames.length.toDouble());
        },
      );
    }
  }

  // â”€â”€ MCP Server â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _setupMcpServer() {
    final cfg = _configManager.current;
    final security = SecurityMiddleware(cfg.securityTokens);
    final sessionManager = SessionManager();

    _mcpServer = AnalystMcpServer(
      toolRegistry: _toolRegistry,
      store: _store,
      security: security,
      sessionManager: sessionManager,
    );
  }

  /// Start MCP server in stdio mode (Claude Desktop / VSCode extensions).
  Future<void> startMcpStdio() async {
    await _mcpServer!.startStdio();
    _log.info('MCP stdio transport active');
  }

  /// Start MCP server on a TCP port for remote AI clients.
  Future<void> startMcpTcp({int? port}) async {
    final cfg = _configManager.current;
    await _mcpServer!.startTcp(
      port: port ?? cfg.mcpPort,
      host: cfg.mcpHost,
    );
    _log.info('MCP TCP transport active on ${cfg.mcpHost}:${port ?? cfg.mcpPort}');
  }
}
