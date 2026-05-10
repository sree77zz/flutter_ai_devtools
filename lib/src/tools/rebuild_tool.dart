import '../core/runtime_store.dart';
import 'base_tool.dart';

/// MCP tool: `analyze_rebuilds`
///
/// Returns per-widget rebuild frequency analysis.
class AnalyzeRebuildsTool extends AnalystTool {
  @override
  String get name => 'analyze_rebuilds';

  @override
  String get description =>
      'Returns per-widget rebuild counts sorted by frequency. Highlights '
      'widgets that rebuild excessively, which are common performance culprits.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'threshold': {
            'type': 'integer',
            'description':
                'Minimum rebuild count to include in results. Defaults to 0 '
                '(all widgets).',
            'default': 0,
          },
          'topN': {
            'type': 'integer',
            'description': 'Return only the top N highest-rebuild widgets.',
            'default': 20,
          },
        },
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    RuntimeStore store,
  ) async {
    final threshold = arguments['threshold'] as int? ?? 0;
    final topN = arguments['topN'] as int? ?? 20;

    final counts = store.widgetRebuildCounts;
    final sorted = counts.entries
        .where((e) => e.value >= threshold)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final top = sorted.take(topN).toList();
    final totalRebuilds = counts.values.fold<int>(0, (s, v) => s + v);

    return ToolResult.success({
      'totalTrackedWidgets': counts.length,
      'totalRebuilds': totalRebuilds,
      'threshold': threshold,
      'returned': top.length,
      'hotspots': top.map((e) => {
            'widgetType': e.key,
            'rebuildCount': e.value,
            'percentOfTotal': totalRebuilds > 0
                ? '${(e.value / totalRebuilds * 100).toStringAsFixed(1)}%'
                : '0%',
          }).toList(),
      'recommendation': _recommendation(top),
    });
  }

  String _recommendation(List<MapEntry<String, int>> hotspots) {
    if (hotspots.isEmpty) return 'No rebuild hotspots detected.';
    final worst = hotspots.first;
    return '${worst.key} has been rebuilt ${worst.value} times. '
        'Consider using const constructors, RepaintBoundary, or selective '
        'state management to reduce rebuilds.';
  }
}
