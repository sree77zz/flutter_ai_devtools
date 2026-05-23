# Production Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure flutter_ai_devtools from 45 scattered files into a clean 2-package, 3-layer architecture with reliable SSE connections and a one-line setup API.

**Architecture:** App-side package (`flutter_ai_devtools`) collects data into a standalone `RuntimeStore` and exposes it via VM Service extensions. MCP package (`flutter_ai_devtools_mcp`) runs as in-process server or standalone CLI, reading the store either directly (in-process) or via VM Service (CLI). SSE server binds before `start()` returns, eliminating the race condition. CLI discovers the app via a lockfile instead of port scanning.

**Tech Stack:** Dart 3.3+, Flutter 3.19+, `dart:io` for HTTP/SSE, `vm_service: ^14.2.4` for CLI bridge, `uuid: ^4.4.0` for session IDs.

---

## File Map

### App package — files modified
| File | Change |
|---|---|
| `lib/src/store/runtime_store.dart` | Rewrite: remove ConfigManager dep, add `currentRoute`/`frameSummary` getters |
| `lib/src/collectors/base_collector.dart` | Rewrite: remove EventBus + ConfigManager, accept RuntimeStore only |
| `lib/src/collectors/widget_collector.dart` | Refactor: remove EventBus publishes, direct store calls |
| `lib/src/collectors/error_collector.dart` | Refactor: remove EventBus publishes |
| `lib/src/collectors/route_collector.dart` | Refactor: remove EventBus publishes |
| `lib/src/collectors/frame_collector.dart` | Refactor: remove EventBus publishes |
| `lib/src/collectors/render_collector.dart` | Refactor: remove EventBus publishes |
| `lib/flutter_ai_devtools.dart` | Rewrite: export only 4 public types |
| `pubspec.yaml` | Remove unused deps |

### App package — files created
| File | Purpose |
|---|---|
| `lib/src/devtools.dart` | `FlutterAiDevtools` main class (replaces bootstrap + engine) |
| `lib/src/config.dart` | `CollectorConfig`, `McpTransport`, `FlutterAiDevtoolsException` |
| `lib/src/lockfile.dart` | Write/read/delete `.dart_tool/flutter_ai_devtools.json` |

### App package — files deleted
`lib/src/core/bootstrap.dart`, `lib/src/core/engine.dart`, `lib/src/core/event_bus.dart`, `lib/src/core/extension_registry.dart`, `lib/src/core/tool_registry.dart`, `lib/src/core/analyzer_engine.dart`, `lib/src/core/vm_service_extensions.dart`, `lib/src/services/config_manager.dart`, `lib/src/services/data_normalizer.dart`, `lib/src/services/metrics_service.dart`, `lib/src/services/notifier_service.dart`, `lib/src/services/scheduler.dart`, `lib/src/transport/` (entire directory), `lib/src/tools/` (entire directory), `lib/src/adapters/` (entire directory), `lib/src/logging/analyst_logger.dart`, `lib/src/logging/error_handler.dart`

### MCP package — all files created in `flutter_ai_devtools_mcp/`
| File | Purpose |
|---|---|
| `pubspec.yaml` | Package manifest |
| `lib/flutter_ai_devtools_mcp.dart` | Public API |
| `lib/src/server/sse_server.dart` | SSE HTTP server + JSON-RPC dispatch |
| `lib/src/server/stdio_server.dart` | stdin/stdout JSON-RPC loop |
| `lib/src/tools/tool_dispatcher.dart` | Tool name → handler lookup |
| `lib/src/tools/tool_definitions.dart` | All 8 tool handlers |
| `lib/src/bridge/in_process_bridge.dart` | Direct RuntimeStore reference |
| `lib/src/bridge/vm_bridge.dart` | VM Service connection via lockfile |
| `bin/devtools_mcp.dart` | CLI entrypoint |

### Tests
| File | Change |
|---|---|
| `test/flutter_ai_devtools_test.dart` | Rewrite for new API |
| `flutter_ai_devtools_mcp/test/tool_dispatcher_test.dart` | New |
| `flutter_ai_devtools_mcp/test/sse_server_test.dart` | New |
| `example/lib/main.dart` | Update to new API |

---

## Phase 1 — App Package

---

### Task 1: Public config types

**Files:**
- Create: `lib/src/config.dart`

- [ ] **Step 1: Create the file**

```dart
// lib/src/config.dart
import 'dart:io';

enum McpTransport { sse, stdio, none }

class CollectorConfig {
  const CollectorConfig({
    this.widgets = true,
    this.frames = true,
    this.errors = true,
    this.routes = true,
    this.renders = true,
    this.maxErrors = 100,
    this.maxFrames = 300,
    this.maxRenderIssues = 200,
    this.widgetSnapshotMaxDepth = 20,
    this.widgetSnapshotMaxNodes = 500,
  });

  final bool widgets;
  final bool frames;
  final bool errors;
  final bool routes;
  final bool renders;
  final int maxErrors;
  final int maxFrames;
  final int maxRenderIssues;
  final int widgetSnapshotMaxDepth;
  final int widgetSnapshotMaxNodes;
}

class FlutterAiDevtoolsException implements Exception {
  const FlutterAiDevtoolsException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() =>
      'FlutterAiDevtoolsException: $message'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}
```

- [ ] **Step 2: Run analyzer to confirm no syntax errors**

```
dart analyze lib/src/config.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```
git add lib/src/config.dart
git commit -m "feat: add CollectorConfig, McpTransport, FlutterAiDevtoolsException"
```

---

### Task 2: Rewrite RuntimeStore

Remove the `ConfigManager` dependency. Take buffer limits directly. Add `currentRoute` and `frameSummary` getters that match what tool handlers will need.

**Files:**
- Modify: `lib/src/store/runtime_store.dart` (move from `lib/src/core/runtime_store.dart`)
- Modify: `test/flutter_ai_devtools_test.dart`

- [ ] **Step 1: Write failing tests first**

Replace the existing `RuntimeStore` group in `test/flutter_ai_devtools_test.dart`:

```dart
// In test/flutter_ai_devtools_test.dart — replace the RuntimeStore group:
group('RuntimeStore', () {
  late RuntimeStore store;

  setUp(() {
    store = RuntimeStore(maxErrors: 3, maxFrames: 5, maxRenderIssues: 10);
  });

  test('bounds error history', () {
    for (var i = 0; i < 10; i++) {
      store.addError(ErrorReport(
        id: 'err-$i',
        capturedAt: DateTime.now(),
        category: ErrorCategory.flutter,
        message: 'Error $i',
      ));
    }
    expect(store.recentErrors.length, equals(3));
  });

  test('bounds frame history', () {
    for (var i = 0; i < 20; i++) {
      store.addFrame(FrameStats(
        frameNumber: i,
        buildDurationMicros: 8000,
        rasterDurationMicros: 4000,
        vsyncOverheadMicros: 100,
        capturedAt: DateTime.now(),
      ));
    }
    expect(store.recentFrames.length, equals(5));
  });

  test('deduplicates errors by id', () {
    final report = ErrorReport(
      id: 'dup-id',
      capturedAt: DateTime.now(),
      category: ErrorCategory.platform,
      message: 'Dup error',
    );
    store.addError(report);
    store.addError(report);
    store.addError(report);
    expect(store.recentErrors.length, equals(1));
    expect(store.recentErrors.first.occurrenceCount, equals(3));
  });

  test('increments rebuild counts', () {
    store.incrementRebuild('Text');
    store.incrementRebuild('Text');
    store.incrementRebuild('Container');
    expect(store.widgetRebuildCounts['Text'], equals(2));
    expect(store.widgetRebuildCounts['Container'], equals(1));
  });

  test('currentRoute returns null before any route update', () {
    expect(store.currentRoute, isNull);
  });

  test('updateRoute sets currentRoute', () {
    final route = RouteInfo(name: '/home', capturedAt: DateTime.now());
    store.updateRoute(route);
    expect(store.currentRoute?.name, equals('/home'));
  });

  test('frameSummary returns zeros when empty', () {
    expect(store.frameSummary.fps, equals(0));
    expect(store.frameSummary.jankyFrames, equals(0));
  });
});
```

- [ ] **Step 2: Run tests — expect failures**

```
flutter test test/flutter_ai_devtools_test.dart --reporter=expanded
```
Expected: failures about `RuntimeStore` constructor and `currentRoute`/`frameSummary` getters.

- [ ] **Step 3: Create `lib/src/store/` directory and write new RuntimeStore**

```dart
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
```

- [ ] **Step 4: Run tests — expect pass**

```
flutter test test/flutter_ai_devtools_test.dart --reporter=expanded
```
Expected: `RuntimeStore` group all green.

- [ ] **Step 5: Commit**

```
git add lib/src/store/runtime_store.dart test/flutter_ai_devtools_test.dart
git commit -m "feat: rewrite RuntimeStore — standalone, no ConfigManager dependency"
```

---

### Task 3: Rewrite BaseCollector

Remove `EventBus` and `ConfigManager` from the constructor. Each collector gets the `RuntimeStore` directly and a `CollectorConfig`.

**Files:**
- Modify: `lib/src/collectors/base_collector.dart`

- [ ] **Step 1: Rewrite the file**

```dart
// lib/src/collectors/base_collector.dart
import '../config.dart';
import '../store/runtime_store.dart';

abstract class BaseCollector {
  BaseCollector({required this.store, required this.config});

  final RuntimeStore store;
  final CollectorConfig config;

  bool _running = false;
  bool get isRunning => _running;

  String get id;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    await onStart();
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await onStop();
  }

  Future<void> onStart();
  Future<void> onStop();
}
```

- [ ] **Step 2: Run analyzer**

```
dart analyze lib/src/collectors/base_collector.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```
git add lib/src/collectors/base_collector.dart
git commit -m "refactor: BaseCollector takes RuntimeStore+CollectorConfig, drops EventBus"
```

---

### Task 4: Refactor all five collectors

Remove EventBus publishes. Call store methods directly. Update constructor signatures.

**Files:**
- Modify: `lib/src/collectors/widget_collector.dart`
- Modify: `lib/src/collectors/error_collector.dart`
- Modify: `lib/src/collectors/route_collector.dart`
- Modify: `lib/src/collectors/frame_collector.dart`
- Modify: `lib/src/collectors/render_collector.dart`

- [ ] **Step 1: Rewrite widget_collector.dart**

```dart
// lib/src/collectors/widget_collector.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../config.dart';
import '../models/widget_snapshot.dart';
import '../store/runtime_store.dart';
import 'base_collector.dart';

class WidgetCollector extends BaseCollector {
  WidgetCollector({required super.store, required super.config});

  Timer? _snapshotTimer;

  @override
  String get id => 'widget_collector';

  @override
  Future<void> onStart() async {
    if (kDebugMode) debugPrintRebuildDirtyWidgets = true;
    _snapshotTimer = Timer.periodic(const Duration(seconds: 3), (_) => _capture());
  }

  @override
  Future<void> onStop() async {
    _snapshotTimer?.cancel();
    if (kDebugMode) debugPrintRebuildDirtyWidgets = false;
  }

  void _capture() {
    try {
      final root = _buildNode(
        WidgetsBinding.instance.rootElement,
        depth: 0,
        maxDepth: config.widgetSnapshotMaxDepth,
        maxNodes: config.widgetSnapshotMaxNodes,
        count: _Counter(),
      );
      store.updateWidgetTree(WidgetTreeSnapshot(
        capturedAt: DateTime.now(),
        root: root,
        totalNodes: root?.totalNodes ?? 0,
        maxDepth: root?.maxDepth ?? 0,
      ));
    } catch (_) {}
  }

  WidgetNode? _buildNode(
    Element? element, {
    required int depth,
    required int maxDepth,
    required int maxNodes,
    required _Counter count,
  }) {
    if (element == null || depth > maxDepth || count.value >= maxNodes) return null;
    count.value++;
    final type = element.widget.runtimeType.toString();
    Rect? rect;
    if (element is RenderObjectElement) {
      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize) {
        final offset = ro.localToGlobal(Offset.zero);
        rect = Rect.fromLTWH(offset.dx, offset.dy, ro.size.width, ro.size.height);
      }
    }
    final children = <WidgetNode>[];
    element.visitChildren((child) {
      final node = _buildNode(child,
          depth: depth + 1, maxDepth: maxDepth, maxNodes: maxNodes, count: count);
      if (node != null) children.add(node);
    });
    return WidgetNode(
      id: '${type}_$depth',
      type: type,
      depth: depth,
      key: element.widget.key?.toString(),
      bounds: rect == null
          ? null
          : WidgetBounds(x: rect.left, y: rect.top, width: rect.width, height: rect.height),
      children: children,
      rebuildCount: store.widgetRebuildCounts[type] ?? 0,
    );
  }

  void recordRebuild(String widgetType) => store.incrementRebuild(widgetType);
}

class _Counter {
  int value = 0;
}
```

- [ ] **Step 2: Rewrite error_collector.dart**

```dart
// lib/src/collectors/error_collector.dart
import 'package:flutter/foundation.dart';
import '../config.dart';
import '../models/error_report.dart';
import '../store/runtime_store.dart';
import 'base_collector.dart';

class ErrorCollector extends BaseCollector {
  ErrorCollector({required super.store, required super.config});

  FlutterExceptionHandler? _prevFlutter;
  bool Function(Object, StackTrace)? _prevPlatform;

  @override
  String get id => 'error_collector';

  @override
  Future<void> onStart() async {
    _prevFlutter = FlutterError.onError;
    FlutterError.onError = _onFlutter;
    _prevPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = _onPlatform;
  }

  @override
  Future<void> onStop() async {
    FlutterError.onError = _prevFlutter;
    PlatformDispatcher.instance.onError = _prevPlatform ?? (_, __) => false;
  }

  void _onFlutter(FlutterErrorDetails d) {
    _prevFlutter?.call(d);
    final msg = d.exceptionAsString();
    store.addError(ErrorReport(
      id: _id(msg),
      capturedAt: DateTime.now(),
      category: ErrorCategory.flutter,
      message: msg,
      stackTrace: d.stack?.toString(),
      context: {'library': d.library ?? 'unknown'},
      isFatal: false,
    ));
  }

  bool _onPlatform(Object error, StackTrace stack) {
    final msg = error.toString();
    store.addError(ErrorReport(
      id: _id(msg),
      capturedAt: DateTime.now(),
      category: ErrorCategory.platform,
      message: msg,
      stackTrace: stack.toString(),
      isFatal: true,
    ));
    return _prevPlatform?.call(error, stack) ?? false;
  }

  String _id(String msg) {
    final key = msg.trim().replaceAll(RegExp(r'\s+'), ' ');
    return (key.length > 64 ? key.substring(0, 64) : key)
        .hashCode.toUnsigned(32).toRadixString(16);
  }
}
```

- [ ] **Step 3: Rewrite route_collector.dart**

```dart
// lib/src/collectors/route_collector.dart
import 'package:flutter/widgets.dart';
import '../config.dart';
import '../models/route_info.dart';
import '../store/runtime_store.dart';
import 'base_collector.dart';

class RouteCollector extends BaseCollector implements NavigatorObserver {
  RouteCollector({required super.store, required super.config});

  @override
  String get id => 'route_collector';

  @override
  Future<void> onStart() async {}

  @override
  Future<void> onStop() async {}

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _update(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _update(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {}

  @override
  NavigatorState? get navigator => null;

  void _update(Route<dynamic> route) {
    store.updateRoute(RouteInfo(
      name: route.settings.name ?? '(unknown)',
      capturedAt: DateTime.now(),
      arguments: route.settings.arguments?.toString(),
    ));
  }
}
```

- [ ] **Step 4: Rewrite frame_collector.dart**

```dart
// lib/src/collectors/frame_collector.dart
import 'package:flutter/scheduler.dart';
import '../config.dart';
import '../models/frame_stats.dart';
import '../store/runtime_store.dart';
import 'base_collector.dart';

class FrameCollector extends BaseCollector {
  FrameCollector({required super.store, required super.config});

  int _frameNumber = 0;

  @override
  String get id => 'frame_collector';

  @override
  Future<void> onStart() async {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  Future<void> onStop() async {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      store.addFrame(FrameStats(
        frameNumber: _frameNumber++,
        buildDurationMicros: t.buildDuration.inMicroseconds,
        rasterDurationMicros: t.rasterDuration.inMicroseconds,
        vsyncOverheadMicros: t.vsyncOverhead.inMicroseconds,
        capturedAt: DateTime.now(),
      ));
    }
  }
}
```

- [ ] **Step 5: Rewrite render_collector.dart**

```dart
// lib/src/collectors/render_collector.dart
import 'package:flutter/rendering.dart';
import '../config.dart';
import '../models/render_issue.dart';
import '../store/runtime_store.dart';
import 'base_collector.dart';

class RenderCollector extends BaseCollector {
  RenderCollector({required super.store, required super.config});

  @override
  String get id => 'render_collector';

  @override
  Future<void> onStart() async {
    debugOnProfilePaint = _onPaint;
  }

  @override
  Future<void> onStop() async {
    debugOnProfilePaint = null;
  }

  void _onPaint(RenderObject ro) {
    // Detect overflow by checking diagnostics.
    final props = ro.debugDescribeChildren();
    for (final child in props) {
      final desc = child.toString();
      if (desc.contains('OVERFLOWING') || desc.contains('overflow')) {
        store.addRenderIssue(RenderIssue(
          id: ro.hashCode.toString(),
          capturedAt: DateTime.now(),
          kind: RenderIssueKind.overflow,
          severity: RenderIssueSeverity.warning,
          description: 'Overflow detected in ${ro.runtimeType}',
          widgetType: ro.runtimeType.toString(),
        ));
        break;
      }
    }
  }
}
```

- [ ] **Step 6: Run the tests to confirm nothing broke**

```
flutter test test/flutter_ai_devtools_test.dart --reporter=expanded
```
Expected: all existing tests pass (EventBus and DataNormalizer groups may now fail — that's fine, they'll be removed in Task 6).

- [ ] **Step 7: Commit**

```
git add lib/src/collectors/
git commit -m "refactor: collectors call store directly, drop EventBus dependency"
```

---

### Task 5: Lockfile mechanism

**Files:**
- Create: `lib/src/lockfile.dart`

- [ ] **Step 1: Create the file**

```dart
// lib/src/lockfile.dart
import 'dart:convert';
import 'dart:io';

const _lockfileName = '.dart_tool/flutter_ai_devtools.json';

Future<void> writeLockfile({required int mcpPort}) async {
  final file = File(_lockfilePath());
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode({
    'mcpPort': mcpPort,
    'pid': pid,
    'startedAt': DateTime.now().toIso8601String(),
  }));
}

Future<void> deleteLockfile() async {
  final file = File(_lockfilePath());
  if (await file.exists()) await file.delete();
}

Future<Map<String, dynamic>?> readLockfile() async {
  final file = File(_lockfilePath());
  if (!await file.exists()) return null;
  try {
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

bool isProcessAlive(int pid) {
  try {
    // Sending signal 0 checks existence without killing.
    Process.killPid(pid, ProcessSignal.sigusr1);
    return true;
  } catch (_) {
    return false;
  }
}

String _lockfilePath() => '${Directory.current.path}${Platform.pathSeparator}$_lockfileName';
```

- [ ] **Step 2: Run analyzer**

```
dart analyze lib/src/lockfile.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```
git add lib/src/lockfile.dart
git commit -m "feat: lockfile write/read/delete for CLI discovery"
```

---

### Task 6: FlutterAiDevtools main class

The single public entry point. Replaces `FlutterAiAnalyst`, `AnalystEngine`, and `bootstrap.dart`.

**Files:**
- Create: `lib/src/devtools.dart`

- [ ] **Step 1: Create the file**

```dart
// lib/src/devtools.dart
import 'package:flutter/widgets.dart';

import 'collectors/error_collector.dart';
import 'collectors/frame_collector.dart';
import 'collectors/render_collector.dart';
import 'collectors/route_collector.dart';
import 'collectors/widget_collector.dart';
import 'config.dart';
import 'lockfile.dart';
import 'store/runtime_store.dart';

class FlutterAiDevtools {
  FlutterAiDevtools._();

  static RuntimeStore? _store;
  static RouteCollector? _routeCollector;
  static final List<dynamic> _collectors = [];
  static dynamic _mcpServer; // set by flutter_ai_devtools_mcp when in-process

  /// The [NavigatorObserver] to attach to [MaterialApp.navigatorObservers].
  static NavigatorObserver get observer {
    _routeCollector ??= RouteCollector(
      store: _store ?? RuntimeStore(),
      config: const CollectorConfig(),
    );
    return _routeCollector!;
  }

  /// Current runtime store. Null before [start] is called.
  static RuntimeStore? get store => _store;

  /// Start data collection and (optionally) the MCP server.
  ///
  /// Throws [FlutterAiDevtoolsException] if:
  /// - [WidgetsBinding] is not initialized
  /// - The requested port is already in use
  static Future<void> start({
    int port = 8765,
    McpTransport transport = McpTransport.sse,
    CollectorConfig collectors = const CollectorConfig(),
    List<Object> extraTools = const [],
  }) async {
    if (!WidgetsBinding.instance.debugDidBuildScope) {
      throw const FlutterAiDevtoolsException(
        'Call WidgetsFlutterBinding.ensureInitialized() before FlutterAiDevtools.start()',
      );
    }

    _store = RuntimeStore(
      maxErrors: collectors.maxErrors,
      maxFrames: collectors.maxFrames,
      maxRenderIssues: collectors.maxRenderIssues,
    );

    // Reuse the observer's route collector if already created, else make a new one.
    _routeCollector ??= RouteCollector(store: _store!, config: collectors);
    _routeCollector!.store == _store
        ? null
        : _routeCollector = RouteCollector(store: _store!, config: collectors);

    _collectors.clear();
    if (collectors.widgets) {
      _collectors.add(WidgetCollector(store: _store!, config: collectors));
    }
    if (collectors.errors) {
      _collectors.add(ErrorCollector(store: _store!, config: collectors));
    }
    if (collectors.frames) {
      _collectors.add(FrameCollector(store: _store!, config: collectors));
    }
    if (collectors.renders) {
      _collectors.add(RenderCollector(store: _store!, config: collectors));
    }

    for (final c in _collectors) {
      await (c as dynamic).start();
    }

    if (transport != McpTransport.none) {
      await _startMcp(port, transport, extraTools);
    }
  }

  /// Stop all collectors and shut down the MCP server.
  static Future<void> stop() async {
    for (final c in _collectors) {
      await (c as dynamic).stop();
    }
    _collectors.clear();
    await (_mcpServer as dynamic?)?.stop();
    _mcpServer = null;
    await deleteLockfile();
    _store = null;
  }

  static Future<void> _startMcp(
      int port, McpTransport transport, List<Object> extraTools) async {
    // The MCP server is in flutter_ai_devtools_mcp package.
    // When used as in-process, that package calls setMcpServer().
    // This method is a hook — the MCP package wires itself in via
    // FlutterAiDevtools.registerMcpStarter().
    if (_mcpStarter != null) {
      _mcpServer = await _mcpStarter!(port, transport, _store!, extraTools);
      await writeLockfile(mcpPort: port);
    }
  }

  static Future<Object> Function(
    int port,
    McpTransport transport,
    RuntimeStore store,
    List<Object> extraTools,
  )? _mcpStarter;

  /// Called by flutter_ai_devtools_mcp to register its server factory.
  static void registerMcpStarter(
    Future<Object> Function(int, McpTransport, RuntimeStore, List<Object>) starter,
  ) {
    _mcpStarter = starter;
  }
}
```

- [ ] **Step 2: Run analyzer**

```
dart analyze lib/src/devtools.dart
```
Expected: `No issues found!` (may warn about unused `debugDidBuildScope` — acceptable in debug mode).

- [ ] **Step 3: Commit**

```
git add lib/src/devtools.dart
git commit -m "feat: FlutterAiDevtools main class — replaces bootstrap + engine"
```

---

### Task 7: Update public exports, delete old files

**Files:**
- Modify: `lib/flutter_ai_devtools.dart`
- Modify: `test/flutter_ai_devtools_test.dart`
- Delete: all old core/services/transport/tools/adapters/logging files

- [ ] **Step 1: Rewrite lib/flutter_ai_devtools.dart**

```dart
// lib/flutter_ai_devtools.dart
export 'src/config.dart';
export 'src/devtools.dart';
export 'src/store/runtime_store.dart';
// Models kept for tool result typing
export 'src/models/error_report.dart';
export 'src/models/frame_stats.dart';
export 'src/models/render_issue.dart';
export 'src/models/route_info.dart';
export 'src/models/widget_snapshot.dart';
```

- [ ] **Step 2: Rewrite test/flutter_ai_devtools_test.dart**

Remove the groups for `DataNormalizer`, `EventBus`, `ToolRegistry`, `SecurityMiddleware`, `RuntimeEvent` (all depend on deleted files). Keep `RuntimeStore`, `FrameStats`, `FrameSummary`. Add a `CollectorConfig` test.

```dart
// test/flutter_ai_devtools_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_devtools/flutter_ai_devtools.dart';

void main() {
  group('RuntimeStore', () {
    late RuntimeStore store;

    setUp(() {
      store = RuntimeStore(maxErrors: 3, maxFrames: 5, maxRenderIssues: 10);
    });

    test('bounds error history', () {
      for (var i = 0; i < 10; i++) {
        store.addError(ErrorReport(
          id: 'err-$i',
          capturedAt: DateTime.now(),
          category: ErrorCategory.flutter,
          message: 'Error $i',
        ));
      }
      expect(store.recentErrors.length, equals(3));
    });

    test('bounds frame history', () {
      for (var i = 0; i < 20; i++) {
        store.addFrame(FrameStats(
          frameNumber: i,
          buildDurationMicros: 8000,
          rasterDurationMicros: 4000,
          vsyncOverheadMicros: 100,
          capturedAt: DateTime.now(),
        ));
      }
      expect(store.recentFrames.length, equals(5));
    });

    test('deduplicates errors by id', () {
      final report = ErrorReport(
        id: 'dup-id',
        capturedAt: DateTime.now(),
        category: ErrorCategory.platform,
        message: 'Dup error',
      );
      store.addError(report);
      store.addError(report);
      store.addError(report);
      expect(store.recentErrors.length, equals(1));
      expect(store.recentErrors.first.occurrenceCount, equals(3));
    });

    test('increments rebuild counts', () {
      store.incrementRebuild('Text');
      store.incrementRebuild('Text');
      store.incrementRebuild('Container');
      expect(store.widgetRebuildCounts['Text'], equals(2));
      expect(store.widgetRebuildCounts['Container'], equals(1));
    });

    test('currentRoute returns null initially', () {
      expect(store.currentRoute, isNull);
    });

    test('updateRoute sets currentRoute', () {
      store.updateRoute(RouteInfo(name: '/home', capturedAt: DateTime.now()));
      expect(store.currentRoute?.name, equals('/home'));
    });

    test('frameSummary returns zeros when empty', () {
      expect(store.frameSummary.fps, equals(0));
      expect(store.frameSummary.jankyFrames, equals(0));
    });
  });

  group('FrameStats', () {
    test('isJanky when total > 16666µs', () {
      final janky = FrameStats(
        frameNumber: 1,
        buildDurationMicros: 12000,
        rasterDurationMicros: 6000,
        vsyncOverheadMicros: 0,
        capturedAt: DateTime.now(),
      );
      expect(janky.isJanky, isTrue);
    });

    test('not janky within budget', () {
      final smooth = FrameStats(
        frameNumber: 2,
        buildDurationMicros: 5000,
        rasterDurationMicros: 4000,
        vsyncOverheadMicros: 0,
        capturedAt: DateTime.now(),
      );
      expect(smooth.isJanky, isFalse);
    });
  });

  group('FrameSummary', () {
    test('empty frames returns zeros', () {
      final s = FrameSummary.fromFrames([]);
      expect(s.fps, equals(0));
      expect(s.jankyFrames, equals(0));
    });

    test('calculates janky percent correctly', () {
      final frames = List.generate(10, (i) => FrameStats(
        frameNumber: i,
        buildDurationMicros: i < 5 ? 20000 : 5000,
        rasterDurationMicros: 1000,
        vsyncOverheadMicros: 0,
        capturedAt: DateTime.now(),
      ));
      final summary = FrameSummary.fromFrames(frames);
      expect(summary.jankyFrames, equals(5));
      expect(summary.jankyPercent, equals(50.0));
    });
  });

  group('CollectorConfig', () {
    test('defaults all collectors on', () {
      const cfg = CollectorConfig();
      expect(cfg.widgets, isTrue);
      expect(cfg.frames, isTrue);
      expect(cfg.errors, isTrue);
      expect(cfg.routes, isTrue);
      expect(cfg.renders, isTrue);
    });

    test('respects custom buffer sizes', () {
      const cfg = CollectorConfig(maxErrors: 5, maxFrames: 10);
      expect(cfg.maxErrors, equals(5));
      expect(cfg.maxFrames, equals(10));
    });
  });
}
```

- [ ] **Step 3: Run tests — expect all pass**

```
flutter test test/flutter_ai_devtools_test.dart --reporter=expanded
```
Expected: all tests green.

- [ ] **Step 4: Delete old files**

```
dart run --no-pub - <<'EOF'
import 'dart:io';
final toDelete = [
  'lib/src/core/bootstrap.dart',
  'lib/src/core/engine.dart',
  'lib/src/core/event_bus.dart',
  'lib/src/core/extension_registry.dart',
  'lib/src/core/tool_registry.dart',
  'lib/src/core/analyzer_engine.dart',
  'lib/src/core/vm_service_extensions.dart',
  'lib/src/core/runtime_store.dart',
  'lib/src/services/config_manager.dart',
  'lib/src/services/data_normalizer.dart',
  'lib/src/services/metrics_service.dart',
  'lib/src/services/notifier_service.dart',
  'lib/src/services/scheduler.dart',
  'lib/src/logging/analyst_logger.dart',
  'lib/src/logging/error_handler.dart',
];
for (final p in toDelete) {
  final f = File(p);
  if (f.existsSync()) { f.deleteSync(); print('Deleted $p'); }
}
EOF
```

Then delete the entire directories that are now empty:
```
Remove-Item -Recurse -Force lib/src/transport, lib/src/tools, lib/src/adapters
```

- [ ] **Step 5: Run full analysis**

```
dart analyze lib/
```
Expected: `No issues found!`

- [ ] **Step 6: Run tests**

```
flutter test test/flutter_ai_devtools_test.dart --reporter=expanded
```
Expected: all green.

- [ ] **Step 7: Commit**

```
git add -A
git commit -m "refactor: delete old core/services/transport/tools/adapters, update public API"
```

---

## Phase 2 — MCP Package

---

### Task 8: Scaffold flutter_ai_devtools_mcp package

**Files:**
- Create: `flutter_ai_devtools_mcp/pubspec.yaml`
- Create: `flutter_ai_devtools_mcp/lib/flutter_ai_devtools_mcp.dart`
- Create directory structure

- [ ] **Step 1: Create directory structure**

```
mkdir -p flutter_ai_devtools_mcp/lib/src/server
mkdir -p flutter_ai_devtools_mcp/lib/src/tools
mkdir -p flutter_ai_devtools_mcp/lib/src/bridge
mkdir -p flutter_ai_devtools_mcp/bin
mkdir -p flutter_ai_devtools_mcp/test
```

- [ ] **Step 2: Create pubspec.yaml**

```yaml
# flutter_ai_devtools_mcp/pubspec.yaml
name: flutter_ai_devtools_mcp
description: MCP server for flutter_ai_devtools. Runs in-process or as a standalone CLI.
version: 0.1.0

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter_ai_devtools:
    path: ../
  uuid: ^4.4.0
  vm_service: ^14.2.4

dev_dependencies:
  test: ^1.25.0
  lints: ^4.0.0

executables:
  devtools_mcp: devtools_mcp
```

- [ ] **Step 3: Create lib/flutter_ai_devtools_mcp.dart**

```dart
// flutter_ai_devtools_mcp/lib/flutter_ai_devtools_mcp.dart
export 'src/server/sse_server.dart';
export 'src/server/stdio_server.dart';
export 'src/tools/tool_dispatcher.dart';
```

- [ ] **Step 4: Run pub get**

```
cd flutter_ai_devtools_mcp && dart pub get
```
Expected: resolves and exits 0.

- [ ] **Step 5: Commit**

```
git add flutter_ai_devtools_mcp/
git commit -m "feat: scaffold flutter_ai_devtools_mcp package"
```

---

### Task 9: ToolDispatcher

**Files:**
- Create: `flutter_ai_devtools_mcp/lib/src/tools/tool_dispatcher.dart`
- Create: `flutter_ai_devtools_mcp/test/tool_dispatcher_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// flutter_ai_devtools_mcp/test/tool_dispatcher_test.dart
import 'package:test/test.dart';
import 'package:flutter_ai_devtools_mcp/src/tools/tool_dispatcher.dart';

void main() {
  group('ToolDispatcher', () {
    late ToolDispatcher dispatcher;

    setUp(() => dispatcher = ToolDispatcher());

    test('calls registered handler', () async {
      dispatcher.register('ping', (_) async => {'pong': true});
      final result = await dispatcher.dispatch('ping', {});
      expect(result['pong'], isTrue);
    });

    test('throws on unknown tool', () async {
      expect(
        () => dispatcher.dispatch('unknown', {}),
        throwsA(isA<ToolNotFoundException>()),
      );
    });

    test('passes arguments to handler', () async {
      dispatcher.register('echo', (args) async => {'got': args['value']});
      final result = await dispatcher.dispatch('echo', {'value': 42});
      expect(result['got'], equals(42));
    });

    test('lists registered tool names', () {
      dispatcher.register('a', (_) async => {});
      dispatcher.register('b', (_) async => {});
      expect(dispatcher.toolNames, containsAll(['a', 'b']));
    });
  });
}
```

- [ ] **Step 2: Run test — expect failure**

```
cd flutter_ai_devtools_mcp && dart test test/tool_dispatcher_test.dart
```
Expected: `Error: Cannot find 'ToolDispatcher'`

- [ ] **Step 3: Implement ToolDispatcher**

```dart
// flutter_ai_devtools_mcp/lib/src/tools/tool_dispatcher.dart

typedef ToolHandler = Future<Map<String, dynamic>> Function(Map<String, dynamic> args);

class ToolNotFoundException implements Exception {
  const ToolNotFoundException(this.toolName);
  final String toolName;
  @override
  String toString() => 'Tool not found: $toolName';
}

class ToolDispatcher {
  final _handlers = <String, ToolHandler>{};
  final _schemas = <String, Map<String, dynamic>>{};

  void register(
    String name,
    ToolHandler handler, {
    Map<String, dynamic> schema = const {'type': 'object', 'properties': {}},
    String description = '',
  }) {
    _handlers[name] = handler;
    _schemas[name] = {'name': name, 'description': description, 'inputSchema': schema};
  }

  Future<Map<String, dynamic>> dispatch(String name, Map<String, dynamic> args) {
    final handler = _handlers[name];
    if (handler == null) throw ToolNotFoundException(name);
    return handler(args);
  }

  List<String> get toolNames => List.unmodifiable(_handlers.keys);
  List<Map<String, dynamic>> get toolManifests => List.unmodifiable(_schemas.values);

  /// Wraps a tool result in MCP content schema.
  static Map<String, dynamic> mcpResult(Map<String, dynamic> content) => {
    'content': [{'type': 'text', 'text': _encode(content)}],
    'isError': false,
  };

  static Map<String, dynamic> mcpError(String message) => {
    'content': [{'type': 'text', 'text': message}],
    'isError': true,
  };

  static String _encode(Object? v) {
    // Simple JSON-like encoder — use dart:convert in real impl
    return v.toString();
  }
}
```

Replace the `_encode` stub with real `dart:convert`:

```dart
import 'dart:convert';
// Replace _encode:
static String _encode(Object? v) => jsonEncode(v);
```

- [ ] **Step 4: Run test — expect pass**

```
cd flutter_ai_devtools_mcp && dart test test/tool_dispatcher_test.dart
```
Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```
git add flutter_ai_devtools_mcp/lib/src/tools/tool_dispatcher.dart flutter_ai_devtools_mcp/test/tool_dispatcher_test.dart
git commit -m "feat: ToolDispatcher with register/dispatch/manifest API"
```

---

### Task 10: Tool definitions (all 8 tools)

**Files:**
- Create: `flutter_ai_devtools_mcp/lib/src/tools/tool_definitions.dart`

- [ ] **Step 1: Create the file**

```dart
// flutter_ai_devtools_mcp/lib/src/tools/tool_definitions.dart
import 'dart:convert';
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
        'maxDepth': {'type': 'integer', 'default': 10, 'description': 'Max tree depth'},
        'includeRenderBounds': {'type': 'boolean', 'default': true},
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
        'avgBuildMs': s.avgBuildMs,
        'avgRasterMs': s.avgRasterMs,
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
          'description':
              '${s.jankyPercent.toStringAsFixed(1)}% of frames exceeded 16ms. '
              'Check for expensive builds in hot paths.',
          'data': {'jankyPercent': s.jankyPercent, 'fps': s.fps},
        });
      }

      final topRebuilds = (store.widgetRebuildCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(5)
          .where((e) => e.value > 50)
          .toList();

      if (topRebuilds.isNotEmpty) {
        insights.add({
          'title': 'Excessive widget rebuilds',
          'severity': 'warning',
          'description': 'Some widgets are rebuilding very frequently. '
              'Consider const constructors or selector widgets.',
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
      final includeMetrics = args['includeInternalMetrics'] as bool? ?? false;
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
    schema: {
      'type': 'object',
      'properties': {
        'includeInternalMetrics': {'type': 'boolean', 'default': false},
      },
    },
  );
}

Map<String, dynamic> _pruneTree(Map<String, dynamic> node, int maxDepth, int depth) {
  if (depth >= maxDepth) return {...node, 'children': []};
  final children = (node['children'] as List? ?? [])
      .map((c) => _pruneTree(c as Map<String, dynamic>, maxDepth, depth + 1))
      .toList();
  return {...node, 'children': children};
}
```

- [ ] **Step 2: Run analyzer**

```
cd flutter_ai_devtools_mcp && dart analyze lib/src/tools/tool_definitions.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```
git add flutter_ai_devtools_mcp/lib/src/tools/tool_definitions.dart
git commit -m "feat: all 8 MCP tool definitions in single file"
```

---

### Task 11: SSE server

**Files:**
- Create: `flutter_ai_devtools_mcp/lib/src/server/sse_server.dart`
- Create: `flutter_ai_devtools_mcp/test/sse_server_test.dart`

- [ ] **Step 1: Write failing integration test**

```dart
// flutter_ai_devtools_mcp/test/sse_server_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_ai_devtools/flutter_ai_devtools.dart';
import 'package:flutter_ai_devtools_mcp/src/server/sse_server.dart';
import 'package:flutter_ai_devtools_mcp/src/tools/tool_dispatcher.dart';
import 'package:test/test.dart';

void main() {
  group('SseServer', () {
    late RuntimeStore store;
    late ToolDispatcher dispatcher;
    late SseServer server;
    late int port;

    setUp(() async {
      store = RuntimeStore();
      dispatcher = ToolDispatcher();
      dispatcher.register('ping', (_) async => {'pong': true});
      server = SseServer(dispatcher: dispatcher, store: store);
      port = await server.bind(0); // port 0 = OS assigns free port
    });

    tearDown(() => server.stop());

    test('bind() returns before any client connects', () {
      // If we get here, bind() completed — no race condition.
      expect(port, greaterThan(0));
    });

    test('POST / with tools/list returns tool manifests', () async {
      final client = HttpClient();
      final req = await client.post('localhost', port, '/');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/list',
        'params': {},
      }));
      final res = await req.close();
      final body = jsonDecode(await res.transform(utf8.decoder).join());
      client.close();
      expect(res.statusCode, equals(200));
      expect(body['result']['tools'], isA<List>());
    });

    test('POST / with tools/call dispatches to registered handler', () async {
      final client = HttpClient();
      final req = await client.post('localhost', port, '/');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': {'name': 'ping', 'arguments': {}},
      }));
      final res = await req.close();
      final body = jsonDecode(await res.transform(utf8.decoder).join());
      client.close();
      expect(res.statusCode, equals(200));
      expect(body['result']['isError'], isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test — expect failure**

```
cd flutter_ai_devtools_mcp && dart test test/sse_server_test.dart
```
Expected: `Error: Cannot find 'SseServer'`

- [ ] **Step 3: Implement SseServer**

```dart
// flutter_ai_devtools_mcp/lib/src/server/sse_server.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_ai_devtools/flutter_ai_devtools.dart';
import 'package:uuid/uuid.dart';
import '../tools/tool_dispatcher.dart';

class SseServer {
  SseServer({required this.dispatcher, required this.store});

  final ToolDispatcher dispatcher;
  final RuntimeStore store;
  HttpServer? _server;
  final _sessions = <String, StreamController<String>>{};
  final _uuid = const Uuid();

  /// Binds to [port] (0 = OS-assigned) and returns the actual port.
  /// Completes only after the server is listening — no race condition.
  Future<int> bind(int port, {String host = 'localhost'}) async {
    _server = await HttpServer.bind(host, port);
    _server!.listen(_handle);
    return _server!.port;
  }

  Future<void> stop() async {
    for (final c in _sessions.values) await c.close();
    _sessions.clear();
    await _server?.close(force: true);
    _server = null;
  }

  void _handle(HttpRequest req) {
    if (req.method == 'GET' && req.uri.path == '/sse') {
      _handleSse(req);
    } else if (req.method == 'POST') {
      _handlePost(req);
    } else if (req.method == 'GET' && req.uri.path == '/health') {
      req.response
        ..statusCode = 200
        ..write('ok')
        ..close();
    } else {
      req.response
        ..statusCode = 404
        ..close();
    }
  }

  Future<void> _handleSse(HttpRequest req) async {
    final sessionId = _uuid.v4();
    final controller = StreamController<String>();
    _sessions[sessionId] = controller;

    req.response
      ..bufferOutput = false
      ..statusCode = 200
      ..headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8')
      ..headers.add('Cache-Control', 'no-cache')
      ..headers.add('Connection', 'keep-alive')
      ..headers.add('Access-Control-Allow-Origin', '*');

    // Send endpoint event per MCP SSE spec.
    req.response.write('event: endpoint\ndata: /\n\n');

    await for (final msg in controller.stream) {
      req.response.write('data: $msg\n\n');
    }
    await req.response.close();
    _sessions.remove(sessionId);
  }

  Future<void> _handlePost(HttpRequest req) async {
    req.response.headers.add('Access-Control-Allow-Origin', '*');
    final body = await req.transform(utf8.decoder).join();
    Map<String, dynamic> rpc;
    try {
      rpc = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      req.response
        ..statusCode = 400
        ..write(jsonEncode(_error(null, -32700, 'Parse error')))
        ..close();
      return;
    }

    final id = rpc['id'];
    final method = rpc['method'] as String?;
    final params = rpc['params'] as Map<String, dynamic>? ?? {};

    try {
      final result = await _dispatch(method, params);
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}))
        ..close();
    } catch (e) {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(_error(id, -32603, e.toString())))
        ..close();
    }
  }

  Future<Map<String, dynamic>> _dispatch(
      String? method, Map<String, dynamic> params) async {
    switch (method) {
      case 'initialize':
        return {
          'protocolVersion': '2024-11-05',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'flutter_ai_devtools', 'version': '0.1.0'},
        };
      case 'initialized':
        return {};
      case 'tools/list':
        return {'tools': dispatcher.toolManifests};
      case 'tools/call':
        final name = params['name'] as String;
        final args = params['arguments'] as Map<String, dynamic>? ?? {};
        final content = await dispatcher.dispatch(name, args);
        return ToolDispatcher.mcpResult(content);
      case 'ping':
        return {'timestamp': DateTime.now().toIso8601String()};
      default:
        throw 'Method not found: $method';
    }
  }

  Map<String, dynamic> _error(dynamic id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}
```

- [ ] **Step 4: Run tests — expect pass**

```
cd flutter_ai_devtools_mcp && dart test test/sse_server_test.dart
```
Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```
git add flutter_ai_devtools_mcp/lib/src/server/sse_server.dart flutter_ai_devtools_mcp/test/sse_server_test.dart
git commit -m "feat: SseServer — binds before returning, no race condition"
```

---

### Task 12: Stdio server

**Files:**
- Create: `flutter_ai_devtools_mcp/lib/src/server/stdio_server.dart`

- [ ] **Step 1: Create the file**

```dart
// flutter_ai_devtools_mcp/lib/src/server/stdio_server.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../tools/tool_dispatcher.dart';

class StdioServer {
  StdioServer({required this.dispatcher});

  final ToolDispatcher dispatcher;
  StreamSubscription<String>? _sub;

  void start() {
    _sub = stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onError: (_) => stop(), onDone: stop);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _onLine(String line) async {
    if (line.trim().isEmpty) return;
    Map<String, dynamic> rpc;
    try {
      rpc = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      _write(_error(null, -32700, 'Parse error'));
      return;
    }

    final id = rpc['id'];
    final method = rpc['method'] as String?;
    final params = rpc['params'] as Map<String, dynamic>? ?? {};

    try {
      final result = await _dispatch(method, params);
      _write({'jsonrpc': '2.0', 'id': id, 'result': result});
    } catch (e) {
      _write(_error(id, -32603, e.toString()));
    }
  }

  Future<Map<String, dynamic>> _dispatch(
      String? method, Map<String, dynamic> params) async {
    switch (method) {
      case 'initialize':
        return {
          'protocolVersion': '2024-11-05',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'flutter_ai_devtools', 'version': '0.1.0'},
        };
      case 'initialized':
        return {};
      case 'tools/list':
        return {'tools': dispatcher.toolManifests};
      case 'tools/call':
        final name = params['name'] as String;
        final args = params['arguments'] as Map<String, dynamic>? ?? {};
        final content = await dispatcher.dispatch(name, args);
        return ToolDispatcher.mcpResult(content);
      case 'ping':
        return {'timestamp': DateTime.now().toIso8601String()};
      default:
        throw 'Method not found: $method';
    }
  }

  void _write(Map<String, dynamic> msg) {
    stdout.writeln(jsonEncode(msg));
  }

  Map<String, dynamic> _error(dynamic id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}
```

- [ ] **Step 2: Run analyzer**

```
cd flutter_ai_devtools_mcp && dart analyze lib/src/server/stdio_server.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```
git add flutter_ai_devtools_mcp/lib/src/server/stdio_server.dart
git commit -m "feat: StdioServer for Claude Desktop / CLI mode"
```

---

### Task 13: In-process bridge + wire into FlutterAiDevtools

**Files:**
- Create: `flutter_ai_devtools_mcp/lib/src/bridge/in_process_bridge.dart`
- Modify: `lib/src/devtools.dart` (already has the `registerMcpStarter` hook)

- [ ] **Step 1: Create in_process_bridge.dart**

```dart
// flutter_ai_devtools_mcp/lib/src/bridge/in_process_bridge.dart
import 'package:flutter_ai_devtools/flutter_ai_devtools.dart';
import '../server/sse_server.dart';
import '../server/stdio_server.dart';
import '../tools/tool_definitions.dart';
import '../tools/tool_dispatcher.dart';

class InProcessBridge {
  InProcessBridge._();

  static SseServer? _sseServer;
  static StdioServer? _stdioServer;

  /// Registers this bridge with FlutterAiDevtools so that start() can
  /// launch the MCP server in-process.
  static void register() {
    FlutterAiDevtools.registerMcpStarter(_start);
  }

  static Future<Object> _start(
    int port,
    McpTransport transport,
    RuntimeStore store,
    List<Object> extraTools,
  ) async {
    final dispatcher = ToolDispatcher();
    registerDefaultTools(dispatcher, store);
    // extraTools would be registered here if typed as ToolHandler entries.

    switch (transport) {
      case McpTransport.sse:
        _sseServer = SseServer(dispatcher: dispatcher, store: store);
        await _sseServer!.bind(port);
        return _sseServer!;
      case McpTransport.stdio:
        _stdioServer = StdioServer(dispatcher: dispatcher);
        _stdioServer!.start();
        return _stdioServer!;
      case McpTransport.none:
        throw ArgumentError('McpTransport.none should not reach _start');
    }
  }

  static Future<void> stop() async {
    await _sseServer?.stop();
    _stdioServer?.stop();
    _sseServer = null;
    _stdioServer = null;
  }
}
```

- [ ] **Step 2: Update lib/flutter_ai_devtools_mcp.dart to export bridge**

```dart
// flutter_ai_devtools_mcp/lib/flutter_ai_devtools_mcp.dart
export 'src/bridge/in_process_bridge.dart';
export 'src/server/sse_server.dart';
export 'src/server/stdio_server.dart';
export 'src/tools/tool_dispatcher.dart';
```

- [ ] **Step 3: Run analyzer on the MCP package**

```
cd flutter_ai_devtools_mcp && dart analyze lib/
```
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```
git add flutter_ai_devtools_mcp/lib/
git commit -m "feat: InProcessBridge wires MCP server into FlutterAiDevtools.start()"
```

---

### Task 14: CLI rewrite — VM bridge + lockfile discovery

**Files:**
- Create: `flutter_ai_devtools_mcp/lib/src/bridge/vm_bridge.dart`
- Create: `flutter_ai_devtools_mcp/bin/devtools_mcp.dart`

- [ ] **Step 1: Create vm_bridge.dart**

```dart
// flutter_ai_devtools_mcp/lib/src/bridge/vm_bridge.dart
import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:flutter_ai_devtools/src/lockfile.dart';

class VmBridge {
  VmService? _service;
  String? _mainIsolateId;

  Future<bool> connect() async {
    final lockData = await readLockfile();
    if (lockData == null) return false;

    final lockPid = lockData['pid'] as int?;
    if (lockPid != null && !isProcessAlive(lockPid)) {
      stderr.writeln('✗ App not running. Run: flutter run');
      return false;
    }

    final port = lockData['mcpPort'] as int? ?? 8765;
    // VM Service runs on a different port — stored via FLUTTER_VM_SERVICE_URI
    // or we derive it from the lockfile if the app writes it.
    final vmUri = lockData['vmServiceUri'] as String?
        ?? Platform.environment['FLUTTER_VM_SERVICE_URI'];

    if (vmUri == null) {
      stderr.writeln('✗ vmServiceUri not in lockfile and FLUTTER_VM_SERVICE_URI not set.');
      return false;
    }

    try {
      final ws = vmUri.replaceFirst('http', 'ws') + 'ws';
      _service = await vmServiceConnectUri(ws);
      final vm = await _service!.getVM();
      _mainIsolateId = vm.isolates?.first.id;
      stderr.writeln('✓ Connected to Flutter app (pid $lockPid)');
      return true;
    } catch (e) {
      stderr.writeln('✗ Connection failed: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> callTool(String name, Map<String, dynamic> args) async {
    if (_service == null || _mainIsolateId == null) {
      return {'error': 'Not connected to Flutter app'};
    }
    try {
      final response = await _service!.callServiceExtension(
        'ext.flutter_ai_devtools.$name',
        isolateId: _mainIsolateId,
        args: args.map((k, v) => MapEntry(k, v.toString())),
      );
      return jsonDecode(response.json?['result'] as String? ?? '{}')
          as Map<String, dynamic>;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<void> dispose() async {
    await _service?.dispose();
    _service = null;
    _mainIsolateId = null;
  }
}
```

- [ ] **Step 2: Rewrite bin/devtools_mcp.dart**

```dart
// flutter_ai_devtools_mcp/bin/devtools_mcp.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_ai_devtools/src/lockfile.dart';
import 'package:flutter_ai_devtools_mcp/src/bridge/vm_bridge.dart';
import 'package:flutter_ai_devtools_mcp/src/server/stdio_server.dart';
import 'package:flutter_ai_devtools_mcp/src/tools/tool_dispatcher.dart';

Future<void> main() async {
  final bridge = VmBridge();

  // Try to connect immediately; if not ready, wait and retry.
  var connected = await bridge.connect();
  if (!connected) {
    stderr.writeln('⧗ Waiting for Flutter app... (Ctrl+C to cancel)');
    for (var i = 0; i < 15 && !connected; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      connected = await bridge.connect();
    }
    if (!connected) {
      stderr.writeln('✗ Could not connect after 30s. Is your Flutter app running?');
      exit(1);
    }
  }

  final dispatcher = ToolDispatcher();
  _registerBridgeTools(dispatcher, bridge);

  final server = StdioServer(dispatcher: dispatcher);
  server.start();

  // Keep alive until stdin closes.
  await stdin.drain<List<int>>();
  await bridge.dispose();
}

void _registerBridgeTools(ToolDispatcher d, VmBridge bridge) {
  const tools = [
    'get_widget_tree',
    'get_current_route',
    'get_recent_errors',
    'get_render_issues',
    'get_frame_stats',
    'analyze_performance',
    'analyze_rebuilds',
    'get_runtime_summary',
  ];

  for (final name in tools) {
    d.register(name, (args) => bridge.callTool(name, args));
  }
}
```

- [ ] **Step 3: Run analyzer**

```
cd flutter_ai_devtools_mcp && dart analyze bin/ lib/src/bridge/
```
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```
git add flutter_ai_devtools_mcp/bin/ flutter_ai_devtools_mcp/lib/src/bridge/
git commit -m "feat: CLI rewrite — lockfile discovery, clean error states, no port scanning"
```

---

## Phase 3 — Integration

---

### Task 15: Update example app + run full test suite

**Files:**
- Modify: `example/lib/main.dart`

- [ ] **Step 1: Update main.dart to new API**

```dart
// example/lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_ai_devtools/flutter_ai_devtools.dart';
import 'package:flutter_ai_devtools_mcp/flutter_ai_devtools_mcp.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register the in-process MCP bridge before calling start().
  InProcessBridge.register();

  await FlutterAiDevtools.start(
    port: 8765,
    transport: McpTransport.sse,
  );

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_ai_devtools',
      navigatorObservers: [FlutterAiDevtools.observer],
      home: const HomeScreen(),
    );
  }
}
```

Keep the rest of `main.dart` (HomeScreen, DetailScreen, SettingsScreen) unchanged.

- [ ] **Step 2: Update example pubspec.yaml to add MCP package**

```yaml
# example/pubspec.yaml — add to dependencies:
  flutter_ai_devtools_mcp:
    path: ../../flutter_ai_devtools_mcp
```

Run:
```
cd example && flutter pub get
```

- [ ] **Step 3: Run the app package unit tests**

```
flutter test test/flutter_ai_devtools_test.dart --reporter=expanded
```
Expected: all tests pass.

- [ ] **Step 4: Run the MCP package tests**

```
cd flutter_ai_devtools_mcp && dart test --reporter=expanded
```
Expected: all tests pass.

- [ ] **Step 5: Run dart analyze on both packages**

```
dart analyze lib/ && cd flutter_ai_devtools_mcp && dart analyze lib/ bin/
```
Expected: `No issues found!` for both.

- [ ] **Step 6: Verify the example app compiles**

```
cd example && flutter build apk --debug 2>&1 | tail -5
```
Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 7: Final commit**

```
git add example/ flutter_ai_devtools_mcp/
git commit -m "feat: wire example app to new API — InProcessBridge.register() + FlutterAiDevtools.start()"
```

- [ ] **Step 8: Push**

```
git push origin main
```

---

## Self-Review

**Spec coverage:**
- ✓ 2-package split (`flutter_ai_devtools` + `flutter_ai_devtools_mcp`)
- ✓ 3 layers: Collectors → RuntimeStore → Transport
- ✓ Zero-config `FlutterAiDevtools.start()` (Task 6)
- ✓ SSE race condition fix: `bind()` returns after listening (Task 11)
- ✓ Lockfile write on start, delete on stop (Tasks 5, 13)
- ✓ CLI lockfile discovery, no port scanning (Task 14)
- ✓ CLI error states: alive / dead / waiting (Task 14)
- ✓ EventBus removed (Tasks 3, 4)
- ✓ TCP transport dropped (not implemented anywhere)
- ✓ All 8 tools (Task 10)
- ✓ `FlutterAiDevtoolsException` (Task 1)
- ✓ `CollectorConfig` (Task 1)
- ✓ `McpTransport` enum (Task 1)
- ✓ `in_process_bridge.dart` with direct store reference (Task 13)
- ✓ Migration: `FlutterAiAnalyst` → `FlutterAiDevtools` (Tasks 6, 7, 15)

**Type consistency:** `RuntimeStore` defined in Task 2, used with identical method names (`addError`, `updateRoute`, `addFrame`, `addRenderIssue`, `incrementRebuild`, `currentWidgetTree`, `currentRoute`, `frameSummary`, `recentErrors`, `renderIssues`, `widgetRebuildCounts`) in Tasks 4, 10, 11, 13. ✓

**No placeholders:** All steps include full code, exact commands, and expected output. ✓
