import '../core/event_bus.dart';
import '../core/runtime_store.dart';
import '../models/render_issue.dart';
import '../services/metrics_service.dart';
import '../logging/analyst_logger.dart';

/// A single analyzer step in the pipeline.
abstract class AnalyzerStep {
  String get name;
  Future<void> analyze(AnalysisContext ctx);
}

/// Context passed through the analyzer pipeline each tick.
class AnalysisContext {
  AnalysisContext({required this.store, required this.eventBus});
  final RuntimeStore store;
  final EventBus eventBus;
  final insights = <AnalysisInsight>[];
}

/// Structured finding produced by an [AnalyzerStep].
class AnalysisInsight {
  const AnalysisInsight({
    required this.step,
    required this.title,
    required this.description,
    this.severity = InsightSeverity.info,
    this.data = const {},
  });

  final String step;
  final String title;
  final String description;
  final InsightSeverity severity;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
        'step': step,
        'title': title,
        'description': description,
        'severity': severity.name,
        'data': data,
      };
}

enum InsightSeverity { info, warning, error }

/// Orchestrates a sequence of [AnalyzerStep]s against the current [RuntimeStore].
///
/// Runs on a timer driven by [SchedulerService]; results are stored as the
/// most-recent insight list and published as a summary event on the bus.
class AnalyzerEngine {
  AnalyzerEngine({
    required EventBus eventBus,
    required RuntimeStore store,
  })  : _eventBus = eventBus,
        _store = store;

  final EventBus _eventBus;
  final RuntimeStore _store;
  final _steps = <AnalyzerStep>[];
  final _log = AnalystLogger.forName('AnalyzerEngine');

  List<AnalysisInsight> _lastInsights = const [];
  List<AnalysisInsight> get lastInsights => _lastInsights;

  void addStep(AnalyzerStep step) {
    _steps.add(step);
    _log.debug('Added analyzer step: ${step.name}');
  }

  Future<List<AnalysisInsight>> runPipeline() async {
    final ctx = AnalysisContext(store: _store, eventBus: _eventBus);
    final stopwatch = Stopwatch()..start();
    for (final step in _steps) {
      try {
        await step.analyze(ctx);
      } catch (e, st) {
        _log.warning('Analyzer step "${step.name}" threw', e, st);
      }
    }
    stopwatch.stop();
    MetricsService.instance
        .record('analyzer.pipelineMs', stopwatch.elapsedMilliseconds.toDouble());
    _lastInsights = List.unmodifiable(ctx.insights);
    _log.debug(
      'Pipeline complete: ${_lastInsights.length} insights '
      'in ${stopwatch.elapsedMilliseconds}ms',
    );
    return _lastInsights;
  }
}

// ── Built-in analyzer steps ───────────────────────────────────────────────────

/// Flags sustained jank — more than 20 % janky frames in the recent window.
class JankAnalyzerStep implements AnalyzerStep {
  @override
  String get name => 'jank_detector';

  @override
  Future<void> analyze(AnalysisContext ctx) async {
    final frames = ctx.store.recentFrames;
    if (frames.isEmpty) return;
    final janky = frames.where((f) => f.isJanky).length;
    final ratio = janky / frames.length;
    if (ratio > 0.20) {
      ctx.insights.add(AnalysisInsight(
        step: name,
        title: 'Sustained frame jank detected',
        description:
            '${(ratio * 100).toStringAsFixed(1)} % of the last ${frames.length} '
            'frames exceeded the 16 ms threshold.',
        severity: InsightSeverity.warning,
        data: {'jankyFrames': janky, 'totalFrames': frames.length},
      ));
    }
  }
}

/// Flags widgets rebuilt an excessive number of times.
class RebuildAnalyzerStep implements AnalyzerStep {
  RebuildAnalyzerStep({this.threshold = 100});
  final int threshold;

  @override
  String get name => 'rebuild_detector';

  @override
  Future<void> analyze(AnalysisContext ctx) async {
    final counts = ctx.store.widgetRebuildCounts;
    final hot = counts.entries
        .where((e) => e.value >= threshold)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in hot.take(5)) {
      ctx.insights.add(AnalysisInsight(
        step: name,
        title: 'Excessive widget rebuilds: ${entry.key}',
        description:
            '${entry.key} has been rebuilt ${entry.value} times. '
            'Consider wrapping in const or using selective rebuilds.',
        severity: InsightSeverity.warning,
        data: {'widgetType': entry.key, 'rebuildCount': entry.value},
      ));
    }
  }
}

/// Surfaces any unresolved render issues.
class RenderIssueAnalyzerStep implements AnalyzerStep {
  @override
  String get name => 'render_issue_detector';

  @override
  Future<void> analyze(AnalysisContext ctx) async {
    final issues = ctx.store.recentRenderIssues;
    for (final issue in issues.take(10)) {
      ctx.insights.add(AnalysisInsight(
        step: name,
        title: 'Render issue: ${issue.kind.name}',
        description: issue.description,
        severity: _insightSeverityFrom(issue.severity),
        data: issue.toJson(),
      ));
    }
  }
}

InsightSeverity _insightSeverityFrom(RenderIssueSeverity s) => switch (s) {
      RenderIssueSeverity.info => InsightSeverity.info,
      RenderIssueSeverity.warning => InsightSeverity.warning,
      RenderIssueSeverity.error => InsightSeverity.error,
    };
