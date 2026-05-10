import '../core/runtime_store.dart';
import '../models/frame_stats.dart';
import '../models/render_issue.dart';
import '../services/metrics_service.dart';
import 'base_tool.dart';

/// MCP tool: `get_runtime_summary`
///
/// One-shot overview of the entire Flutter runtime state.
class GetRuntimeSummaryTool extends AnalystTool {
  @override
  String get name => 'get_runtime_summary';

  @override
  String get description =>
      'Returns a comprehensive one-shot summary of the Flutter app runtime: '
      'current route, frame stats, error count, render issues, widget tree '
      'stats, and internal analyst metrics. The best starting point for an '
      'AI client.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'includeInternalMetrics': {
            'type': 'boolean',
            'description':
                'If true, includes internal flutter_ai_analyst performance '
                'counters in the response.',
            'default': false,
          },
        },
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    RuntimeStore store,
  ) async {
    final includeMetrics =
        arguments['includeInternalMetrics'] as bool? ?? false;

    final snapshot = store.snapshot();
    final frames = snapshot.recentFrames;
    final summary = FrameSummary.fromFrames(frames);
    final errors = snapshot.recentErrors;
    final renderIssues = snapshot.recentRenderIssues;
    final nav = snapshot.navigationState;
    final widgetTree = snapshot.widgetTree;

    final result = <String, dynamic>{
      'timestamp': snapshot.capturedAt.toIso8601String(),
      'navigation': {
        'currentRoute': nav?.currentRoute ?? 'unknown',
        'stackDepth': nav?.stack.length ?? 0,
      },
      'widgetTree': {
        'captured': widgetTree != null,
        'totalNodes': widgetTree?.totalNodes ?? 0,
        'maxDepth': widgetTree?.maxDepth ?? 0,
        'lastCapturedAt': widgetTree?.capturedAt.toIso8601String(),
      },
      'frames': {
        'sampleCount': frames.length,
        'fps': summary.fps.toStringAsFixed(1),
        'jankyPercent': summary.jankyPercent.toStringAsFixed(1),
        'averageBuildMs': summary.averageBuildMs.toStringAsFixed(2),
        'averageRasterMs': summary.averageRasterMs.toStringAsFixed(2),
        'worstFrameMs': summary.worstFrameMs.toStringAsFixed(2),
      },
      'errors': {
        'totalStored': errors.length,
        'fatalCount': errors.where((e) => e.isFatal).length,
        'mostRecent': errors.isEmpty ? null : errors.last.toJson()
          ?..remove('stackTrace'),
      },
      'renderIssues': {
        'totalStored': renderIssues.length,
        'byKind': _countByKind(renderIssues),
      },
      'rebuilds': {
        'trackedWidgets': snapshot.widgetRebuildCounts.length,
        'topRebuilder': _topRebuilder(snapshot.widgetRebuildCounts),
      },
    };

    if (includeMetrics) {
      result['analystMetrics'] = MetricsService.instance.snapshot();
    }

    return ToolResult.success(result);
  }

  Map<String, int> _countByKind(List<RenderIssue> issues) {
    final counts = <String, int>{};
    for (final issue in issues) {
      counts[issue.kind.name] = (counts[issue.kind.name] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, dynamic>? _topRebuilder(Map<String, int> counts) {
    if (counts.isEmpty) return null;
    final top = counts.entries.reduce((a, b) => a.value > b.value ? a : b);
    return {'widgetType': top.key, 'rebuildCount': top.value};
  }
}
