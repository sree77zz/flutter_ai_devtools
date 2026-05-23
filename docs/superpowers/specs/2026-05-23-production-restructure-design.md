# flutter_ai_devtools — Production Restructure Design

**Date:** 2026-05-23  
**Approach:** B — Layered Restructure  
**Status:** Approved

---

## Problem Statement

The current `flutter_ai_devtools` (v0.1.0) has three compounding problems:

1. **Unreliable connections** — SSE has a race condition (client hits `/sse` before `HttpServer` is bound); CLI uses fragile port scanning (8080–8200, 50 ms timeout each).
2. **Complex setup** — 6 async steps, 45 source files, 30+ exported classes, 17-field config object.
3. **Hard to maintain and publish** — no clear layer boundaries, tools/services/engine tangled together, unsuitable for pub.dev as-is.

Goal: fix all three while supporting both in-process and sidecar MCP modes, targeting internal use first, pub.dev later.

---

## Package Structure

Two focused packages in the monorepo:

```
flutter_ai_devtools/           ← app-side (what devs add to their Flutter app)
  lib/
    flutter_ai_devtools.dart   ← entire public API (one file)
    src/
      collectors/
        widget_collector.dart
        error_collector.dart
        route_collector.dart
        frame_collector.dart
        render_collector.dart
      store/
        runtime_store.dart     ← all state + config merged
      emitter/
        vm_service_emitter.dart
      flutter_ai_devtools.dart ← single entry class
  pubspec.yaml                 ← no HTTP dep, no MCP dep

flutter_ai_devtools_mcp/       ← MCP server (in-process OR sidecar CLI)
  lib/
    flutter_ai_devtools_mcp.dart
    src/
      server/
        sse_server.dart        ← SSE only (TCP dropped)
        stdio_server.dart      ← Claude Desktop / CLI mode
      tools/
        tool_dispatcher.dart
        tool_definitions.dart  ← all 8 tools in one file
      bridge/
        vm_bridge.dart         ← CLI: VM Service connection
        in_process_bridge.dart ← in-process: direct store access
  bin/
    devtools_mcp.dart
  pubspec.yaml

example/                       ← unchanged structure
cli/                           ← replaced by flutter_ai_devtools_mcp
```

**File count:** ~8 app-side + ~12 MCP = ~20 total. Down from 45.

---

## Public API

### App-side (`flutter_ai_devtools`)

```dart
// Zero-config — one line
await FlutterAiDevtools.start();

// With options
await FlutterAiDevtools.start(
  port: 8765,
  transport: McpTransport.sse,   // .sse | .stdio | .none
  collectors: const CollectorConfig(
    widgets: true,
    frames: true,
    errors: true,
    routes: true,
    renders: true,
  ),
  extraTools: [MyCustomTool()],
);

// Navigator observer
MaterialApp(
  navigatorObservers: [FlutterAiDevtools.observer],
)

// Shutdown
await FlutterAiDevtools.stop();
```

**Removed from public API:**
- `AnalystConfig` (17 fields) → `CollectorConfig` (5 booleans) + direct params
- `AnalystEngine`, `EventBus`, `ToolRegistry`, `ExtensionRegistry` — internal only
- `McpTransport.tcp` — dropped
- Adapter system (`BlocAdapter`, etc.) — deferred to v0.2

**Exported types (exhaustive list):**
- `FlutterAiDevtools` — the main class
- `McpTransport` — enum: `sse`, `stdio`, `none`
- `CollectorConfig` — data class, 5 bool fields
- `FlutterAiDevtoolsException` — thrown on startup failure

### MCP-side (`flutter_ai_devtools_mcp`)

Used internally by `flutter_ai_devtools` when transport is not `.none`, and directly by the CLI binary. Not part of the Flutter app developer's surface.

---

## Architecture: 3 Layers

### Layer 1 — Collectors

Five single-file collectors. Each hooks into Flutter internals and calls the store directly. No event bus, no async streams between collectors and store.

```
widget_collector.dart   → store.updateWidgetTree(snapshot)
error_collector.dart    → store.addError(report)
route_collector.dart    → store.updateRoute(info)
frame_collector.dart    → store.addFrame(stats)
render_collector.dart   → store.addRenderIssue(issue)
```

### Layer 2 — RuntimeStore

Single file. Bounded circular buffers. Clean read/write API. Replaces: `RuntimeStore`, `ConfigManager`, `MetricsService`, `NotifierService`, `SchedulerService`, `EventBus`, `AnalyzerEngine`.

```dart
class RuntimeStore {
  // Write — called by collectors
  void updateWidgetTree(WidgetSnapshot s);
  void addError(ErrorReport e);
  void updateRoute(RouteInfo r);
  void addFrame(FrameStats f);
  void addRenderIssue(RenderIssue i);
  void incrementRebuild(String widgetType);

  // Read — called by MCP tool handlers
  WidgetSnapshot? get currentWidgetTree;
  List<ErrorReport> get recentErrors;
  RouteInfo? get currentRoute;
  FrameSummary get frameSummary;
  List<RenderIssue> get renderIssues;
  Map<String, int> get rebuildCounts;
}
```

Buffer sizes: errors=100, frames=300, renderIssues=200 — hardcoded sensible defaults, overridable via `CollectorConfig`.

Analysis logic (jank detection, rebuild hotspots) moves into the tool handlers themselves — computed on demand when Claude calls the tool, not on a background 5s timer.

### Layer 3 — MCP Transport (`flutter_ai_devtools_mcp`)

Four files replacing 9 tool files + ToolRegistry + AnalystMcpServer + SessionManager:

**`sse_server.dart`** (~150 lines)
- `HttpServer.bind()` → server ready
- GET `/sse` → open SSE stream per client, `bufferOutput = false`
- POST `/` → receive JSON-RPC, dispatch to `ToolDispatcher`, stream response
- Session map: `Map<String, StreamController>` (inline, no separate SessionManager)

**`stdio_server.dart`** (~60 lines)
- Read stdin line by line
- Parse JSON-RPC, dispatch to `ToolDispatcher`, write to stdout

**`in_process_bridge.dart`** (~20 lines)
- Holds a direct `RuntimeStore` reference passed in from `FlutterAiDevtools.start()`
- No IPC, no VM Service call — the store is in the same Dart isolate
- Used when `flutter_ai_devtools_mcp` is loaded as a library (not a separate process)

**`tool_dispatcher.dart`** (~50 lines)
- `Map<String, ToolHandler>` lookup
- Execute handler, wrap result in MCP content schema
- Single `FlutterAiDevtoolsException` on unknown tool

**`tool_definitions.dart`** (~200 lines)
- All 8 tool schemas + handlers registered as functions
- `analyze_performance` and `analyze_rebuilds` compute inline from store state

```dart
void registerDefaultTools(ToolDispatcher d, RuntimeStore store) {
  d.register('get_widget_tree',     (args) => _widgetTree(args, store));
  d.register('get_recent_errors',   (args) => _recentErrors(args, store));
  d.register('get_current_route',   (args) => _currentRoute(args, store));
  d.register('get_frame_stats',     (args) => _frameStats(args, store));
  d.register('get_render_issues',   (args) => _renderIssues(args, store));
  d.register('analyze_performance', (args) => _analyzePerformance(args, store));
  d.register('analyze_rebuilds',    (args) => _analyzeRebuilds(args, store));
  d.register('get_runtime_summary', (args) => _runtimeSummary(args, store));
}
```

Custom tools: `FlutterAiDevtools.start(extraTools: [MyTool()])` registers additional handlers before the server starts.

---

## Connection Reliability

### Fix 1 — SSE race condition

`start()` only returns after `HttpServer.bind()` resolves and the server is actively listening. The client cannot connect before the port is open.

```dart
Future<void> start(...) async {
  _store = RuntimeStore();
  await _startCollectors();
  await _server.bind(port);  // ← completes only when listening
  _writeLockfile(port);
}
```

### Fix 2 — Lockfile discovery

On start, the app writes:

```
.dart_tool/flutter_ai_devtools.json
{
  "vmServiceUri": "http://127.0.0.1:8181/token/",
  "mcpPort": 8765,
  "pid": 44201,
  "startedAt": "2026-05-23T10:30:00.000Z"
}
```

On stop, the file is deleted. The CLI reads this file first — no port scanning, no env var required.

`.dart_tool/` is already in every Flutter project's `.gitignore`.

### Fix 3 — CLI error states

Three explicit states, always printed to stderr:

| State | CLI output |
|---|---|
| Lockfile found, process alive | `✓ Connected to Flutter app (pid 44201)` |
| Lockfile found, process dead | `✗ App not running. Run: flutter run` |
| No lockfile, waiting | `⧗ Waiting for Flutter app... (Ctrl+C to cancel)` |

Waiting state retries every 2 seconds for up to 30 seconds, then exits with a clear message.

---

## Error Handling

Single exception type: `FlutterAiDevtoolsException(String message, {Object? cause})`.

Thrown by `start()` if:
- Port is already bound → `"Port 8765 is already in use. Choose a different port."`
- `WidgetsFlutterBinding` not initialized → `"Call WidgetsFlutterBinding.ensureInitialized() before FlutterAiDevtools.start()"`
- Collector fails to hook → propagates cause with context

No silent swallowing. No retries inside `start()`. Errors surface immediately so the developer fixes them rather than wondering why Claude can't connect.

---

## Testing Strategy

**Unit tests (app package):**
- `RuntimeStore` — buffer bounds, deduplication, rebuild counts (existing tests kept)
- Each collector — mock Flutter binding hooks, verify store receives correct data
- `FlutterAiDevtoolsException` — thrown on bad init order

**Integration tests (MCP package):**
- `SseServer` — bind, connect real `HttpClient`, send JSON-RPC, verify response
- `StdioServer` — pipe stdin/stdout, verify tool call roundtrip
- `ToolDispatcher` — register tool, call it, verify MCP-wrapped response
- Lockfile — write on start, read by CLI bridge, delete on stop

**No mocks of internal classes.** `RuntimeStore` is the only seam. Tests call collectors directly, read from store, verify output.

---

## Migration from v0.1.0

| Old | New |
|---|---|
| `FlutterAiAnalyst.initialize(config: AnalystConfig(...))` | `FlutterAiDevtools.start()` |
| `FlutterAiAnalyst.navigatorObserver` | `FlutterAiDevtools.observer` |
| `FlutterAiAnalyst.shutdown()` | `FlutterAiDevtools.stop()` |
| `McpTransport.tcp` | removed — use `.sse` |
| `AnalystConfig(mcpPort: 9000)` | `FlutterAiDevtools.start(port: 9000)` |
| CLI: env var / port scan | CLI: reads `.dart_tool/flutter_ai_devtools.json` |

Breaking change is acceptable at v0.1.0.

---

## Out of Scope (v0.2+)

- Framework adapters (BLoC, Riverpod, GetX, Dio, Firebase)
- TCP transport
- Security token middleware
- Custom analyzer pipeline steps
- pub.dev publish workflow
