import 'dart:async';

import 'package:flutter/widgets.dart';

import '../adapters/base_adapter.dart';
import '../logging/analyst_logger.dart';
import '../services/config_manager.dart';
import '../tools/base_tool.dart';
import 'engine.dart';

/// High-level bootstrap API for [flutter_ai_analyst].
///
/// Wrap your `runApp` call:
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   await FlutterAiAnalyst.initialize(
///     config: AnalystConfig(mcpPort: 8765),
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
class FlutterAiAnalyst {
  FlutterAiAnalyst._();

  static final _log = AnalystLogger.forName('Bootstrap');

  /// Initialize the analyst engine.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  static Future<void> initialize({
    AnalystConfig config = const AnalystConfig(),
    McpTransport mcpTransport = McpTransport.none,
    int? mcpPort,
    List<AnalystAdapter> adapters = const [],
    List<AnalystTool> extraTools = const [],
  }) async {
    if (AnalystEngine.isInitialized) {
      _log.warning('FlutterAiAnalyst already initialized; skipping.');
      return;
    }

    WidgetsFlutterBinding.ensureInitialized();

    final engine = await AnalystEngine.create(config);

    for (final adapter in adapters) {
      engine.registerAdapter(adapter);
    }
    for (final tool in extraTools) {
      engine.registerTool(tool);
    }

    switch (mcpTransport) {
      case McpTransport.stdio:
        await engine.startMcpStdio();
      case McpTransport.tcp:
        await engine.startMcpTcp(port: mcpPort);
      case McpTransport.none:
        _log.info(
          'MCP transport not started. Call engine.startMcpStdio() or '
          'engine.startMcpTcp() manually.',
        );
    }

    _log.info('FlutterAiAnalyst initialized (transport: ${mcpTransport.name})');
  }

  /// Tear down the engine. Call from your app's dispose or on hot restart.
  static Future<void> shutdown() => AnalystEngine.instance.shutdown();

  /// Attach this observer to your Navigator to capture route events.
  ///
  /// ```dart
  /// MaterialApp(navigatorObservers: [FlutterAiAnalyst.navigatorObserver])
  /// ```
  static NavigatorObserver get navigatorObserver =>
      AnalystEngine.instance.navigatorObserver;

  /// Direct access to the engine for advanced usage.
  static AnalystEngine get engine => AnalystEngine.instance;

  static bool get isInitialized => AnalystEngine.isInitialized;
}

/// Which MCP transport to start on [FlutterAiAnalyst.initialize].
enum McpTransport {
  /// No transport started; start manually via the engine.
  none,

  /// JSON-RPC over stdin/stdout — compatible with Claude Desktop and most IDE
  /// MCP extensions.
  stdio,

  /// JSON-RPC over a TCP socket — for remote AI clients.
  tcp,
}
