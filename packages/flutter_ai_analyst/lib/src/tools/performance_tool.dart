import '../core/analyzer_engine.dart';
import '../core/runtime_store.dart';
import '../models/frame_stats.dart';
import 'base_tool.dart';

/// MCP tool: `analyze_performance`
///
/// Runs the analyzer pipeline and returns structured performance insights.
class AnalyzePerformanceTool extends AnalystTool {
  AnalyzePerformanceTool(this._engine);

  final AnalyzerEngine _engine;

  @override
  String get name => 'analyze_performance';

  @override
  String get description =>
      'Runs the full analyzer pipeline and returns structured performance '
      'insights: jank detection, render issues, memory patterns, and '
      'recommendations for the AI client.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'freshRun': {
            'type': 'boolean',
            'description':
                'If true, runs a fresh pipeline analysis. If false, returns '
                'cached results from the last run.',
            'default': true,
          },
        },
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    RuntimeStore store,
  ) async {
    final freshRun = arguments['freshRun'] as bool? ?? true;

    List<AnalysisInsight> insights;
    if (freshRun) {
      insights = await _engine.runPipeline();
    } else {
      insights = _engine.lastInsights;
    }

    final frames = store.recentFrames;
    final summary = FrameSummary.fromFrames(frames);
    final errors = store.recentErrors;
    final renderIssues = store.recentRenderIssues;

    return ToolResult.success({
      'analysisTimestamp': DateTime.now().toIso8601String(),
      'freshRun': freshRun,
      'insightCount': insights.length,
      'insights': insights.map((i) => i.toJson()).toList(),
      'quickStats': {
        'fps': summary.fps.toStringAsFixed(1),
        'jankyPercent': summary.jankyPercent.toStringAsFixed(1),
        'averageBuildMs': summary.averageBuildMs.toStringAsFixed(2),
        'errorCount': errors.length,
        'renderIssueCount': renderIssues.length,
        'widgetRebuildHotspots': store.widgetRebuildCounts.entries
            .toList()
            .where((e) => e.value > 50)
            .map((e) => {'widget': e.key, 'rebuilds': e.value})
            .toList(),
      },
    });
  }
}
