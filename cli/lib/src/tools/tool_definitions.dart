import 'package:flutter_ai_devtools/flutter_ai_devtools.dart';
import 'tool_dispatcher.dart';

void registerDefaultTools(ToolDispatcher d, RuntimeStore store) {
  d.register(
    'get_widget_tree',
    (args) async {
      final tree = store.currentWidgetTree;
      if (tree == null) return {'error': 'No widget tree captured yet'};
      final maxDepth = (args['maxDepth'] as num?)?.toInt() ?? 10;
      return {
        'capturedAt': tree.capturedAt.toIso8601String(),
        'totalNodes': tree.totalNodes,
        'maxDepth': tree.maxDepth,
        'tree': tree.root == null ? null : _pruneTree(tree.root!.toJson(), maxDepth, 0),
      };
    },
    description: 'Get the current widget tree snapshot',
    schema: {
      'type': 'object',
      'properties': {
        'maxDepth': {'type': 'integer', 'default': 10},
      },
    },
  );

  d.register(
    'get_current_route',
    (_) async {
      final route = store.currentRoute;
      if (route == null) return {'error': 'No route captured yet'};
      return route.toJson();
    },
    description: 'Get the active navigation route',
  );

  d.register(
    'get_recent_errors',
    (args) async {
      final limit = (args['limit'] as num?)?.toInt() ?? 20;
      final fatalOnly = args['fatalOnly'] as bool? ?? false;
      var errors = store.recentErrors;
      if (fatalOnly) errors = errors.where((e) => e.isFatal).toList();
      return {
        'count': errors.length,
        'errors': errors.take(limit).map((e) => e.toJson()).toList(),
      };
    },
    description: 'Get recent error history',
    schema: {
      'type': 'object',
      'properties': {
        'limit': {'type': 'integer', 'default': 20},
        'fatalOnly': {'type': 'boolean', 'default': false},
      },
    },
  );

  d.register(
    'get_render_issues',
    (_) async => {
      'count': store.renderIssues.length,
      'issues': store.renderIssues.map((r) => r.toJson()).toList(),
    },
    description: 'Get rendering problems (overflow, constraint errors)',
  );

  d.register(
    'get_frame_stats',
    (_) async {
      final s = store.frameSummary;
      return {
        'fps': s.fps,
        'jankyFrames': s.jankyFrames,
        'jankyPercent': s.jankyPercent,
        'avgBuildMs': s.averageBuildMs,
        'avgRasterMs': s.averageRasterMs,
        'totalFrames': store.recentFrames.length,
      };
    },
    description: 'Get frame timing metrics (FPS, jank)',
  );

  d.register(
    'analyze_performance',
    (_) async {
      final s = store.frameSummary;
      final insights = <Map<String, dynamic>>[];
      if (s.jankyPercent > 20) {
        insights.add({
          'title': 'High jank rate',
          'severity': 'warning',
          'description': '${s.jankyPercent.toStringAsFixed(1)}% of frames exceeded 16ms.',
          'data': {'jankyPercent': s.jankyPercent, 'fps': s.fps},
        });
      }
      final topRebuilds = (store.widgetRebuildCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .where((e) => e.value > 50)
          .take(5)
          .toList();
      if (topRebuilds.isNotEmpty) {
        insights.add({
          'title': 'Excessive widget rebuilds',
          'severity': 'warning',
          'description': 'Some widgets are rebuilding very frequently.',
          'data': {for (final e in topRebuilds) e.key: e.value},
        });
      }
      if (store.renderIssues.isNotEmpty) {
        insights.add({
          'title': 'Render issues detected',
          'severity': 'error',
          'description': '${store.renderIssues.length} render issue(s) found.',
          'data': {'count': store.renderIssues.length},
        });
      }
      return {'insights': insights, 'analysedAt': DateTime.now().toIso8601String()};
    },
    description: 'Run performance analysis pipeline',
  );

  d.register(
    'analyze_rebuilds',
    (_) async {
      final sorted = store.widgetRebuildCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return {
        'topRebuilds': sorted.take(10).map((e) => {'widget': e.key, 'count': e.value}).toList(),
        'totalTracked': sorted.length,
      };
    },
    description: 'Identify the most frequently rebuilding widgets',
  );

  d.register(
    'get_runtime_summary',
    (args) async {
      final s = store.frameSummary;
      return {
        'route': store.currentRoute?.toJson(),
        'errorCount': store.recentErrors.length,
        'fatalErrors': store.recentErrors.where((e) => e.isFatal).length,
        'renderIssues': store.renderIssues.length,
        'fps': s.fps,
        'jankyPercent': s.jankyPercent,
        'widgetTreeNodes': store.currentWidgetTree?.totalNodes,
        'topRebuilds': (store.widgetRebuildCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .take(5)
            .map((e) => {'widget': e.key, 'count': e.value})
            .toList(),
        'capturedAt': DateTime.now().toIso8601String(),
      };
    },
    description: 'Complete runtime health snapshot',
  );
}

Map<String, dynamic> _pruneTree(Map<String, dynamic> node, int maxDepth, int depth) {
  if (depth >= maxDepth) return {...node, 'children': []};
  final children = (node['children'] as List? ?? [])
      .map((c) => _pruneTree(c as Map<String, dynamic>, maxDepth, depth + 1))
      .toList();
  return {...node, 'children': children};
}
