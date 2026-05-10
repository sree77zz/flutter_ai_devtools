import 'package:meta/meta.dart';

/// Immutable configuration snapshot for the analyst engine.
@immutable
class AnalystConfig {
  const AnalystConfig({
    this.mcpHost = 'localhost',
    this.mcpPort = 8765,
    this.enableWidgetCollector = true,
    this.enableErrorCollector = true,
    this.enableRouteCollector = true,
    this.enableFrameCollector = true,
    this.enableRenderCollector = true,
    this.frameWindowSize = 300,
    this.errorHistorySize = 100,
    this.routeHistorySize = 50,
    this.renderIssueHistorySize = 200,
    this.widgetSnapshotMaxDepth = 20,
    this.widgetSnapshotMaxNodes = 500,
    this.logLevel = 'info',
    this.securityTokens = const [],
    this.enableMetrics = true,
    this.analyzerPipelineIntervalMs = 5000,
  });

  final String mcpHost;
  final int mcpPort;
  final bool enableWidgetCollector;
  final bool enableErrorCollector;
  final bool enableRouteCollector;
  final bool enableFrameCollector;
  final bool enableRenderCollector;
  final int frameWindowSize;
  final int errorHistorySize;
  final int routeHistorySize;
  final int renderIssueHistorySize;
  final int widgetSnapshotMaxDepth;
  final int widgetSnapshotMaxNodes;
  final String logLevel;
  final List<String> securityTokens;
  final bool enableMetrics;
  final int analyzerPipelineIntervalMs;

  AnalystConfig copyWith({
    String? mcpHost,
    int? mcpPort,
    bool? enableWidgetCollector,
    bool? enableErrorCollector,
    bool? enableRouteCollector,
    bool? enableFrameCollector,
    bool? enableRenderCollector,
    int? frameWindowSize,
    int? errorHistorySize,
    int? routeHistorySize,
    int? renderIssueHistorySize,
    int? widgetSnapshotMaxDepth,
    int? widgetSnapshotMaxNodes,
    String? logLevel,
    List<String>? securityTokens,
    bool? enableMetrics,
    int? analyzerPipelineIntervalMs,
  }) =>
      AnalystConfig(
        mcpHost: mcpHost ?? this.mcpHost,
        mcpPort: mcpPort ?? this.mcpPort,
        enableWidgetCollector:
            enableWidgetCollector ?? this.enableWidgetCollector,
        enableErrorCollector: enableErrorCollector ?? this.enableErrorCollector,
        enableRouteCollector: enableRouteCollector ?? this.enableRouteCollector,
        enableFrameCollector: enableFrameCollector ?? this.enableFrameCollector,
        enableRenderCollector:
            enableRenderCollector ?? this.enableRenderCollector,
        frameWindowSize: frameWindowSize ?? this.frameWindowSize,
        errorHistorySize: errorHistorySize ?? this.errorHistorySize,
        routeHistorySize: routeHistorySize ?? this.routeHistorySize,
        renderIssueHistorySize:
            renderIssueHistorySize ?? this.renderIssueHistorySize,
        widgetSnapshotMaxDepth:
            widgetSnapshotMaxDepth ?? this.widgetSnapshotMaxDepth,
        widgetSnapshotMaxNodes:
            widgetSnapshotMaxNodes ?? this.widgetSnapshotMaxNodes,
        logLevel: logLevel ?? this.logLevel,
        securityTokens: securityTokens ?? this.securityTokens,
        enableMetrics: enableMetrics ?? this.enableMetrics,
        analyzerPipelineIntervalMs:
            analyzerPipelineIntervalMs ?? this.analyzerPipelineIntervalMs,
      );

  Map<String, dynamic> toJson() => {
        'mcpHost': mcpHost,
        'mcpPort': mcpPort,
        'enableWidgetCollector': enableWidgetCollector,
        'enableErrorCollector': enableErrorCollector,
        'enableRouteCollector': enableRouteCollector,
        'enableFrameCollector': enableFrameCollector,
        'enableRenderCollector': enableRenderCollector,
        'frameWindowSize': frameWindowSize,
        'errorHistorySize': errorHistorySize,
        'routeHistorySize': routeHistorySize,
        'widgetSnapshotMaxDepth': widgetSnapshotMaxDepth,
        'widgetSnapshotMaxNodes': widgetSnapshotMaxNodes,
        'logLevel': logLevel,
        'enableMetrics': enableMetrics,
        'analyzerPipelineIntervalMs': analyzerPipelineIntervalMs,
      };
}

/// Mutable holder for [AnalystConfig] with change notification.
class ConfigManager {
  ConfigManager([AnalystConfig? initial])
      : _config = initial ?? const AnalystConfig();

  AnalystConfig _config;

  AnalystConfig get current => _config;

  void update(AnalystConfig Function(AnalystConfig current) updater) {
    _config = updater(_config);
  }

  void apply(AnalystConfig config) => _config = config;
}
