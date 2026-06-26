// lib/src/store/runtime_store.dart
import 'dart:collection';
import '../models/error_report.dart';
import '../models/frame_stats.dart';
import '../models/issue.dart';
import '../models/render_issue.dart';
import '../models/route_info.dart';
import '../models/widget_snapshot.dart';

class RuntimeStore {
  RuntimeStore({
    this.maxErrors = 100,
    this.maxFrames = 300,
    this.maxRenderIssues = 200,
    this.maxIssues = 200,
    this.recurrenceThreshold = 5,
  });

  final int maxErrors;
  final int maxFrames;
  final int maxRenderIssues;
  final int maxIssues;
  final int recurrenceThreshold;

  WidgetTreeSnapshot? _widgetTree;
  RouteInfo? _currentRoute;
  final _errors = <String, ErrorReport>{};
  final _errorOrder = Queue<String>();
  final _frames = Queue<FrameStats>();
  final _renderIssues = Queue<RenderIssue>();
  final _rebuildCounts = <String, int>{};
  final _issues = <String, Issue>{};

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

  /// Adds or merges [incoming] by signature: repeats increment the count, push
  /// lastSeen forward, keep the highest severity seen, and escalate to critical
  /// once the count reaches [recurrenceThreshold].
  void addIssue(Issue incoming) {
    final existing = _issues[incoming.signature];
    if (existing != null) {
      final count = existing.count + 1;
      var severity = existing.severity.index >= incoming.severity.index
          ? existing.severity
          : incoming.severity;
      if (count >= recurrenceThreshold) severity = IssueSeverity.critical;
      _issues[incoming.signature] = existing.copyWith(
        count: count,
        lastSeen: incoming.lastSeen,
        severity: severity,
      );
      return;
    }
    while (_issues.length >= maxIssues && _issues.isNotEmpty) {
      _issues.remove(_issues.keys.first);
    }
    _issues[incoming.signature] = incoming;
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
  List<Issue> get issues => List.unmodifiable(_issues.values);

  void clear() {
    _widgetTree = null;
    _currentRoute = null;
    _errors.clear();
    _errorOrder.clear();
    _frames.clear();
    _renderIssues.clear();
    _rebuildCounts.clear();
    _issues.clear();
  }
}
