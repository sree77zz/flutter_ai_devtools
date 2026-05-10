/// flutter_ai_analyst — AI-native Flutter runtime intelligence platform.
///
/// Exposes Flutter app internals to AI clients (Claude, Cursor, Gemini,
/// Codex, VSCode AI agents) in real time via the MCP protocol.
///
/// ## Quick start
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   await FlutterAiAnalyst.initialize(
///     config: const AnalystConfig(mcpPort: 8765),
///     mcpTransport: McpTransport.tcp,
///   );
///
///   runApp(
///     MaterialApp(
///       navigatorObservers: [FlutterAiAnalyst.navigatorObserver],
///       home: const MyHome(),
///     ),
///   );
/// }
/// ```
///
/// ## Architecture
///
/// ```
/// AI Clients (Claude / Cursor / Gemini / Codex / VSCode)
///      │  MCP Protocol (JSON-RPC 2.0)
///      ▼
/// AnalystMcpServer  ─── ToolRegistry ──────────── 8 built-in tools
///      │
///      ▼
/// AnalystEngine (core orchestrator)
///   ├── EventBus          (broadcast stream hub)
///   ├── RuntimeStore      (bounded circular buffers)
///   ├── AnalyzerEngine    (pluggable insight pipeline)
///   ├── ExtensionRegistry (optional adapters)
///   └── Collectors
///         ├── WidgetCollector   (widget tree + rebuilds)
///         ├── ErrorCollector    (FlutterError + PlatformDispatcher)
///         ├── RouteCollector    (NavigatorObserver)
///         ├── FrameCollector    (SchedulerBinding.addTimingsCallback)
///         └── RenderCollector   (overflow / constraint errors)
/// ```
library flutter_ai_analyst;

// Bootstrap / public API
export 'src/core/bootstrap.dart';
export 'src/core/engine.dart' show AnalystEngine, EngineState;

// Configuration
export 'src/services/config_manager.dart';

// Models
export 'src/models/runtime_event.dart';
export 'src/models/widget_snapshot.dart';
export 'src/models/error_report.dart';
export 'src/models/frame_stats.dart';
export 'src/models/route_info.dart';
export 'src/models/render_issue.dart';

// Core subsystems (for advanced users)
export 'src/core/event_bus.dart';
export 'src/core/runtime_store.dart';
export 'src/core/tool_registry.dart';
export 'src/core/extension_registry.dart';
export 'src/core/analyzer_engine.dart';

// Collectors
export 'src/collectors/base_collector.dart';
export 'src/collectors/widget_collector.dart';
export 'src/collectors/error_collector.dart';
export 'src/collectors/route_collector.dart';
export 'src/collectors/frame_collector.dart';
export 'src/collectors/render_collector.dart';

// Adapters
export 'src/adapters/base_adapter.dart';
export 'src/adapters/bloc_adapter.dart';
export 'src/adapters/riverpod_adapter.dart';
export 'src/adapters/getx_adapter.dart';
export 'src/adapters/dio_adapter.dart';
export 'src/adapters/firebase_adapter.dart';

// MCP Tools (public for extension)
export 'src/tools/base_tool.dart';
export 'src/tools/widget_tree_tool.dart';
export 'src/tools/route_tool.dart';
export 'src/tools/error_tool.dart';
export 'src/tools/render_tool.dart';
export 'src/tools/frame_tool.dart';
export 'src/tools/performance_tool.dart';
export 'src/tools/rebuild_tool.dart';
export 'src/tools/summary_tool.dart';

// Transport (for custom server setups)
export 'src/transport/mcp_server.dart';
export 'src/transport/session_manager.dart';
export 'src/transport/security_middleware.dart';

// Services (for advanced composition)
export 'src/services/notifier_service.dart';
export 'src/services/metrics_service.dart';
export 'src/services/scheduler.dart';
export 'src/services/data_normalizer.dart';

// Logging
export 'src/logging/analyst_logger.dart';
export 'src/logging/error_handler.dart';
