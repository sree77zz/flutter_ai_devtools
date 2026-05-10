import 'dart:collection';

import '../models/error_report.dart';
import '../models/frame_stats.dart';
import '../models/render_issue.dart';
import '../models/route_info.dart';
import '../models/runtime_event.dart';
import '../models/widget_snapshot.dart';
import '../services/config_manager.dart';
import '../logging/analyst_logger.dart';

/// Immutable state snapshot produced by [RuntimeStore.snapshot].
class RuntimeStoreSnapshot {
  const RuntimeStoreSnapshot({
    required this.widgetTree,
    required this.navigationState,
    required this.recentErrors,
    required this.recentFrames,
    required this.recentRenderIssues,
    required this.widgetRebuildCounts,
    required this.capturedAt,
  });

  final WidgetTreeSnapshot? widgetTree;
  final NavigationState? navigationState;
  final List<ErrorReport> recentErrors;
  final List<FrameStats> recentFrames;
  final List<RenderIssue> recentRenderIssues;
  final Map<String, int> widgetRebuildCounts;
  final DateTime capturedAt;

  Map<String, dynamic> toJson() => {
        'capturedAt': capturedAt.toIso8601String(),
        if (widgetTree != null) 'widgetTree': widgetTree!.toJson(),
        if (navigationState != null) 'navigation': navigationState!.toJson(),
        'recentErrors': recentErrors.map((e) => e.toJson()).toList(),
        'recentFrames': recentFrames.map((f) => f.toJson()).toList(),
        'recentRenderIssues':
            recentRenderIssues.map((r) => r.toJson()).toList(),
        'widgetRebuildCounts': widgetRebuildCounts,
      };
}

/// Thread-safe (single-isolate) central store for all collected runtime data.
///
/// Mutable internals are bounded by [AnalystConfig] limits so memory usage
/// stays predictable. All reads return defensive copies.
class RuntimeStore {
  RuntimeStore(this._config);

  final ConfigManager _config;
  final _log = AnalystLogger.forName('RuntimeStore');

  WidgetTreeSnapshot? _widgetTree;
  NavigationState? _navigationState;
  final _errors = <String, ErrorReport>{};
  final _errorOrder = Queue<String>();
  final _frames = Queue<FrameStats>();
  final _renderIssues = Queue<RenderIssue>();
  final _rebuildCounts = <String, int>{};
  final _adapterData = <String, Map<String, dynamic>>{};

  // ── Widget tree ─────────────────────────────────────────────────────────────

  void updateWidgetTree(WidgetTreeSnapshot snapshot) {
    _widgetTree = snapshot;
    _log.debug(
      'Widget tree updated: ${snapshot.totalNodes} nodes, '
      'depth ${snapshot.maxDepth}',
    );
  }

  WidgetTreeSnapshot? get widgetTree => _widgetTree;

  // ── Navigation ──────────────────────────────────────────────────────────────

  void updateNavigation(NavigationState state) {
    _navigationState = state;
  }

  NavigationState? get navigationState => _navigationState;

  // ── Errors ──────────────────────────────────────────────────────────────────

  void addError(ErrorReport report) {
    final existing = _errors[report.id];
    if (existing != null) {
      _errors[report.id] = existing.incrementOccurrence();
      return;
    }
    final limit = _config.current.errorHistorySize;
    while (_errorOrder.length >= limit) {
      _errors.remove(_errorOrder.removeFirst());
    }
    _errors[report.id] = report;
    _errorOrder.addLast(report.id);
  }

  List<ErrorReport> get recentErrors =>
      _errorOrder.map((id) => _errors[id]!).toList(growable: false);

  // ── Frames ──────────────────────────────────────────────────────────────────

  void addFrame(FrameStats stats) {
    final limit = _config.current.frameWindowSize;
    if (_frames.length >= limit) _frames.removeFirst();
    _frames.addLast(stats);
  }

  List<FrameStats> get recentFrames => List.unmodifiable(_frames);

  // ── Render issues ────────────────────────────────────────────────────────────

  void addRenderIssue(RenderIssue issue) {
    final limit = _config.current.renderIssueHistorySize;
    if (_renderIssues.length >= limit) _renderIssues.removeFirst();
    _renderIssues.addLast(issue);
  }

  List<RenderIssue> get recentRenderIssues =>
      List.unmodifiable(_renderIssues);

  // ── Rebuild tracking ────────────────────────────────────────────────────────

  void incrementRebuild(String widgetType) {
    _rebuildCounts[widgetType] = (_rebuildCounts[widgetType] ?? 0) + 1;
  }

  Map<String, int> get widgetRebuildCounts =>
      Map.unmodifiable(_rebuildCounts);

  // ── Adapter data ────────────────────────────────────────────────────────────

  void setAdapterData(String adapterId, Map<String, dynamic> data) {
    _adapterData[adapterId] = Map.unmodifiable(data);
  }

  Map<String, dynamic>? getAdapterData(String adapterId) =>
      _adapterData[adapterId];

  // ── Snapshot ────────────────────────────────────────────────────────────────

  RuntimeStoreSnapshot snapshot() => RuntimeStoreSnapshot(
        widgetTree: _widgetTree,
        navigationState: _navigationState,
        recentErrors: recentErrors,
        recentFrames: recentFrames,
        recentRenderIssues: recentRenderIssues,
        widgetRebuildCounts: widgetRebuildCounts,
        capturedAt: DateTime.now(),
      );

  void clear() {
    _widgetTree = null;
    _navigationState = null;
    _errors.clear();
    _errorOrder.clear();
    _frames.clear();
    _renderIssues.clear();
    _rebuildCounts.clear();
    _adapterData.clear();
    _log.info('RuntimeStore cleared');
  }

  // ── Event ingestion helper ──────────────────────────────────────────────────

  /// Routes a normalized [RuntimeEvent] into the correct store bucket.
  void ingest(RuntimeEvent event) {
    switch (event.type) {
      case RuntimeEventType.widgetTreeSnapshot:
        // Deserialization handled by widget collector; store expects snapshots
        // pushed directly via updateWidgetTree.
        break;
      case RuntimeEventType.widgetRebuilt:
        final wt = event.payload['widgetType'] as String?;
        if (wt != null) incrementRebuild(wt);
        break;
      case RuntimeEventType.frameRendered:
      case RuntimeEventType.frameJanked:
        // FrameCollector pushes via addFrame directly.
        break;
      default:
        break;
    }
  }
}
