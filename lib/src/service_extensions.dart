import 'dart:convert';
import 'dart:developer' as dev;

import 'store/runtime_store.dart';

void registerServiceExtensions(RuntimeStore store) {
  _register('get_runtime_summary', (params) {
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
  });

  _register('get_widget_tree', (params) {
    final tree = store.currentWidgetTree;
    if (tree == null) return {'error': 'No widget tree captured yet'};
    final maxDepth = int.tryParse(params['maxDepth'] ?? '') ?? 10;
    return {
      'capturedAt': tree.capturedAt.toIso8601String(),
      'totalNodes': tree.totalNodes,
      'maxDepth': tree.maxDepth,
      'tree': tree.root == null
          ? null
          : _pruneTree(tree.root!.toJson(), maxDepth, 0),
    };
  });

  _register('get_current_route', (params) {
    final route = store.currentRoute;
    if (route == null) return {'error': 'No route captured yet'};
    return route.toJson();
  });

  _register('get_recent_errors', (params) {
    final limit = int.tryParse(params['limit'] ?? '') ?? 20;
    final fatalOnly = params['fatalOnly'] == 'true';
    var errors = store.recentErrors;
    if (fatalOnly) errors = errors.where((e) => e.isFatal).toList();
    return {
      'count': errors.length,
      'errors': errors.take(limit).map((e) => e.toJson()).toList(),
    };
  });

  _register('get_render_issues', (params) => {
    'count': store.renderIssues.length,
    'issues': store.renderIssues.map((r) => r.toJson()).toList(),
  });

  _register('get_frame_stats', (params) {
    final s = store.frameSummary;
    return {
      'fps': s.fps,
      'jankyFrames': s.jankyFrames,
      'jankyPercent': s.jankyPercent,
      'avgBuildMs': s.averageBuildMs,
      'avgRasterMs': s.averageRasterMs,
      'totalFrames': store.recentFrames.length,
    };
  });

  _register('analyze_performance', (params) {
    final s = store.frameSummary;
    final insights = <Map<String, dynamic>>[];
    if (s.jankyPercent > 20) {
      insights.add({
        'title': 'High jank rate',
        'severity': 'warning',
        'description':
            '${s.jankyPercent.toStringAsFixed(1)}% of frames exceeded 16ms.',
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
    return {
      'insights': insights,
      'analysedAt': DateTime.now().toIso8601String(),
    };
  });

  _register('analyze_rebuilds', (params) {
    final sorted = store.widgetRebuildCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {
      'topRebuilds': sorted
          .take(10)
          .map((e) => {'widget': e.key, 'count': e.value})
          .toList(),
      'totalTracked': sorted.length,
    };
  });
}

void _register(
  String name,
  Map<String, dynamic> Function(Map<String, String> params) handler,
) {
  dev.registerExtension('ext.flutter_ai_devtools.$name', (method, params) async {
    try {
      final result = handler(params);
      return dev.ServiceExtensionResponse.result(jsonEncode(result));
    } catch (e) {
      return dev.ServiceExtensionResponse.error(
        dev.ServiceExtensionResponse.extensionError,
        jsonEncode({'error': e.toString()}),
      );
    }
  });
}

Map<String, dynamic> _pruneTree(
    Map<String, dynamic> node, int maxDepth, int depth) {
  if (depth >= maxDepth) return {...node, 'children': []};
  final children = (node['children'] as List? ?? [])
      .map((c) => _pruneTree(c as Map<String, dynamic>, maxDepth, depth + 1))
      .toList();
  return {...node, 'children': children};
}
