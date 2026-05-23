// lib/src/store/runtime_store.dart
import 'dart:collection';
import '../models/error_report.dart';
import '../models/frame_stats.dart';
import '../models/render_issue.dart';
import '../models/route_info.dart';
import '../models/widget_snapshot.dart';

class RuntimeStore {
  RuntimeStore({
    this.maxErrors = 100,
    this.maxFrames = 300,
    this.maxRenderIssues = 200,
  });

  final int maxErrors;
  final int maxFrames;
  final int maxRenderIssues;

  WidgetTreeSnapshot? _widgetTree;
  RouteInfo? _currentRoute;
  final _errors = <String, ErrorReport>{};
  final _errorOrder = Queue<String>();
  final _frames = Queue<FrameStats>();
  final _renderIssues = Queue<RenderIssue>();
  final _rebuildCounts = <String, int>{};

  // ── Write ──────────────────────────────────────────────────────────────────

  void updateWidgetTree(WidgetTreeSnapshot snapshot) {
    _widgetTree = snapshot;
  }

  void updateRoute(RouteInfo route) {
    _currentRoute = route;
  }

  void addError(ErrorReport report) {
    final existing = _errors[report.id];
    if (existing != null) {
      _errors[report.id] = existing.incrementOccurrence();
      return;
    }
    while (_errorOrder.length >= maxErrors) {
      _errors.remove(_errorOrder.removeFirst());
    }
    _errors[report.id] = report;
    _errorOrder.addLast(report.id);
  }

  void addFrame(FrameStats stats) {
    if (_frames.length >= maxFrames) _frames.removeFirst();
    _frames.addLast(stats);
  }

  void addRenderIssue(RenderIssue issue) {
    if (_renderIssues.length >= maxRenderIssues) _renderIssues.removeFirst();
    _renderIssues.addLast(issue);
  }

  void incrementRebuild(String widgetType) {
    _rebuildCounts[widgetType] = (_rebuildCounts[widgetType] ?? 0) + 1;
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  WidgetTreeSnapshot? get currentWidgetTree => _widgetTree;
  RouteInfo? get currentRoute => _currentRoute;
  List<ErrorReport> get recentErrors =>
      _errorOrder.map((id) => _errors[id]!).toList(growable: false);
  List<FrameStats> get recentFrames => List.unmodifiable(_frames);
  FrameSummary get frameSummary => FrameSummary.fromFrames(recentFrames);
  List<RenderIssue> get renderIssues => List.unmodifiable(_renderIssues);
  Map<String, int> get widgetRebuildCounts => Map.unmodifiable(_rebuildCounts);

  void clear() {
    _widgetTree = null;
    _currentRoute = null;
    _errors.clear();
    _errorOrder.clear();
    _frames.clear();
    _renderIssues.clear();
    _rebuildCounts.clear();
  }
}
