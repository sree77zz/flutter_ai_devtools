# flutter_ai_devtools — Connection & Live-Diagnostics Rework

**Date:** 2026-06-04
**Approach:** C — Hybrid capture (app-side structured collectors + bridge-side VM-stream ingestion)
**Status:** Approved (design)

---

## Problem Statement

Three compounding problems make the current v0.1.0 plugin hard to use:

1. **Messy connection / start.** Developers run `flutter run` in one terminal and a
   second `serve`/bridge process in another. Connections are fragile (lockfile-only
   discovery, connect-or-die bridge) and frequently fail. It should work from the IDE
   with no terminal step and connect to the MCP server reliably.
2. **Weak, polling-only error detection.** Issues are captured only via in-app
   `FlutterError.onError` hooks and surfaced only when Claude polls. There is no live
   console/log listening, and detection covers thrown exceptions but not the broader
   class of "issues."
3. **Fragile route tracking.** Route capture requires manually wiring
   `navigatorObservers: [FlutterAiDevtools.observer]`. With `MaterialApp.routes`,
   `MaterialApp.router`, or `go_router`, forgetting the observer silently disables
   route tracking.

**Goal:** terminal-free launch from the IDE, deterministic MCP connection, live
console + issue detection across three categories, and zero-setup route tracking —
across both **desktop** and **Android/iOS** targets.

---

## Decisions (locked during brainstorming)

| Topic | Decision |
|---|---|
| Target platforms | Desktop (macOS/Windows/Linux) **and** Android/iOS device/emulator |
| Launch model | Provided **"Flutter + AI DevTools"** debug config that pins the VM-service port (pure Dart, no companion extension) |
| Issue categories | **Console/log stream**, **Layout/render**, **Lifecycle/state** (existing perf collectors kept but not expanded) |
| Route tracking | **Observer-free auto-detect** from the live element tree; observer becomes optional enrichment |
| "Live" model | **Always-fresh on pull**: bridge ingests continuously in the background; tools return an up-to-the-millisecond tail via a cursor |
| Capture architecture | **Hybrid**: app-side structured collectors + bridge-side VM-stream ingestion, merged in a `LiveBuffer` |
| Handled-error capture | Opt-in `FlutterAiDevtools.reportError()` / `reportIssue()` to surface caught API/business errors that are neither logged nor rethrown |

### Capture boundary (what "all issues" means)

A tool can only surface an error that is **thrown uncaught**, **logged/printed**, or
**explicitly reported**. An error that is `catch`-handled and silently swallowed is
invisible to every observability tool — `reportError()` exists precisely to close that
gap. After this rework Claude reads all such signals **directly from the running app**
with no copy-paste; the developer never opens or pastes a log.

---

## Architecture Overview

Two capture planes, split by **who can actually observe each signal**, merged at the
bridge. The app can see its own widget tree / rebuilds / render + lifecycle assertions
but cannot reliably self-capture raw `print()` / stdout / framework logs. The bridge,
connected to the VM service, can see the raw streams but not the app's structured
internals. Hybrid uses each for what it alone can see.

```
 ┌────────────────────── Flutter app (your isolate) ───────────────────────┐
 │  collectors → RuntimeStore (deep structured state, queried on demand)    │
 │      │  also emit each issue in real time ↓                              │
 │      └── dev.postEvent('ext.flutter_ai_devtools.issue', {...})           │
 │  service extensions: ext.flutter_ai_devtools.<tool> (on-demand reads)    │
 └───────────────────────────────│─────────────────────────────────────────┘
        VM service streams         │  Extension stream (structured issues)
   Stdout · Stderr · Logging  ─────┤  Isolate stream (restart / exit)
                                   ▼
 ┌──────────────────────────── devtools_mcp bridge ────────────────────────┐
 │  VmBridge: resilient connect loop + auto-reconnect                       │
 │  LiveBuffer:  logs[]   (ring + monotonic seq cursor)                     │
 │               issues[] (deduped, aggregated, severity, escalation)       │
 │  detectors run continuously over the raw log stream                      │
 │  on-demand reads proxied to service extensions (tree, frames, route…)    │
 │  ToolDispatcher → MCP JSON-RPC                                            │
 └──────────────────────────────────────────────────────────────────────────┘
                                   ▲  stdio JSON-RPC (always-fresh on pull)
                              Claude Code
```

---

## Section 1 — Connection & Launch Reliability

### 1.1 Deterministic VM-service endpoint

The provided **"Flutter + AI DevTools"** debug config pins the VM service to a known
address with no auth token:

```jsonc
{
  "name": "Flutter + AI DevTools",
  "request": "launch",
  "type": "dart",
  "args": [
    "--vm-service-port=8181",
    "--host-vmservice-port=8181",
    "--disable-service-auth-codes"
  ]
}
```

- **Desktop:** the app exposes `ws://127.0.0.1:8181/ws` directly.
- **Mobile:** launching via this config makes the Dart-Code extension forward the
  device VM service to the same host port, so the bridge endpoint is identical.

The endpoint is therefore deterministic on both targets, with no token to discover.

### 1.2 Resilient bridge daemon

Replaces today's connect-or-die `VmBridge`:

- Claude Code auto-spawns the bridge via `.mcp.json` (stdio). It **starts instantly
  and never exits** on connection failure.
- A background **connect loop** retries roughly every 1s until the VM service appears,
  so launching the app *after* Claude is connected still works.
- Before connection, tool calls return a clear, actionable result (not a hard error):
  *"App not running — launch the 'Flutter + AI DevTools' config."*
- **Auto-reconnect:** the bridge watches the `Isolate` stream for exit / hot-restart,
  tears down stale stream subscriptions, re-resolves the main isolate, and
  re-subscribes — no manual restart of the bridge or Claude.
- **Layered discovery** (robustness fallback, pinned port primary):
  `pinned port 8181` → desktop lockfile → `DART_VM_SERVICE_URI` env var.

### 1.3 `setup` upgrade

- **Idempotently merges** the debug config into an existing `.vscode/launch.json`
  (preserving the user's other configurations) instead of overwriting.
- Writes/refreshes `.mcp.json` (stdio transport).
- Resolves the package bin path correctly.

Net flow: one-time `dart run flutter_ai_devtools:setup`, then pick the config in the
Run panel. No terminals, no second process.

---

## Section 2 — Hybrid Live-Capture

### 2.1 App → bridge real-time channel

App-side collectors continue writing structured snapshots/events to `RuntimeStore`
(for on-demand reads) **and** broadcast each new structured issue via
`dev.postEvent('ext.flutter_ai_devtools.issue', payload)` on the VM `Extension` stream
for real-time delivery.

### 2.2 Bridge ingestion

The bridge calls `streamListen` on:

- `Stdout` / `Stderr` → raw console lines (bytes base64-decoded).
- `Logging` → `dart:developer.log` records (level, name, time, message, error, stack).
- `Extension` → events prefixed `ext.flutter_ai_devtools.*` (structured app issues).
- `Isolate` → `IsolateExit` / hot-restart triggers reconnect/refresh.

### 2.3 `LiveBuffer`

A bridge-side aggregation structure:

- `logs`: bounded ring buffer of normalized entries with a **monotonic `seq`** cursor.
  `get_logs(sinceSeq)` returns the tail plus `nextSeq`.
- `issues`: deduplicated/aggregated detected issues (see Section 3).
- Detectors run continuously over the raw log stream; structured app issues arrive
  pre-classified via the `Extension` stream and are merged by signature.

### 2.4 Always-fresh on pull & degradation

Because the bridge ingests continuously even while Claude is idle, every
`get_logs` / `get_issues` call returns up-to-the-millisecond data, and the log buffer
keeps filling even when the isolate is janky. **Graceful degradation:** if the app is
an older build without `postEvent`, the bridge still delivers raw logs plus
text-scraped issues.

---

## Section 3 — Issue Detection

### 3.1 Common shape

```dart
Issue {
  String id;                 // stable per signature
  IssueCategory category;    // console | layoutRender | lifecycleState
  IssueSeverity severity;    // info | warning | error | critical
  String source;             // detected | reported
  String signature;          // dedup key
  String? domainCategory;    // free-form tag from reportError/reportIssue (e.g. 'api')
  String title;
  String detail;
  DateTime firstSeen;
  DateTime lastSeen;
  int count;                 // aggregated occurrences
  Evidence evidence;         // { widget?, size?, stack?, logSeq, context? }
}
```

Issues are **deduplicated and aggregated** by signature, so Claude sees
*"Overflow in Row (×42, last seen 2s ago)"* rather than 42 raw entries.

### 3.2 Category ① — Console / log stream (bridge-side)

- Source: `Stdout`, `Stderr`, `Logging` VM streams.
- Normalized entry: `{seq, ts, level, source, message, error?, stack?}`.
- `level` inference: `Stderr` → warn/error; `Logging` carries its own level;
  `Stdout` → info.
- Served by `get_logs(sinceSeq, level?, grep?, limit?)`.

### 3.3 Category ② — Layout / render (app-side classify + bridge text fallback)

- `RenderCollector` expanded to classify and capture the **offending widget, size,
  and a diagnostics snippet**, covering: RenderFlex overflow, unbounded/infinite
  constraints, intrinsic-measurement, missing `Directionality`, duplicate `GlobalKey`,
  incorrect `ParentDataWidget`, image-decode failures.
- Each emitted as a structured issue via `postEvent`.
- The bridge also pattern-matches the raw log stream as a fallback for anything not
  routed through `FlutterError`.

### 3.4 Category ③ — Lifecycle / state (app-side `LifecycleCollector`)

- Classifies from the `FlutterError` / log stream: `setState()` / `markNeedsBuild`
  **after dispose**, "used after being disposed" (controllers / tickers / timers),
  "mounted" violations, and "Another exception was thrown" (flagged as a **cascade**).
- **Recurring-pattern escalation:** when an error signature repeats beyond a threshold
  within a time window, severity escalates to `critical` with the repeat count —
  converting log noise into a single high-signal finding.
- **Out of scope:** general memory-leak detection without a Flutter-emitted signal. We
  detect the *symptoms* Flutter surfaces (disposed-use assertions), not arbitrary leaks.

### 3.5 Explicit developer-reported issues (`reportError` / `reportIssue`)

A public app-side API for surfacing **handled** errors that would otherwise be invisible
(caught API/business-logic failures that are neither logged nor rethrown):

```dart
try {
  await api.charge(order);
} catch (e, st) {
  FlutterAiDevtools.reportError(
    e, st,
    category: 'api',                       // free-form domain tag
    context: {'orderId': order.id},        // structured evidence
  );
}

// Non-exception conditions (validation failures, invariant breaks):
FlutterAiDevtools.reportIssue(
  'Cart total mismatch',
  severity: IssueSeverity.error,
  context: {'expected': 1200, 'actual': 1150},
);
```

- No-ops when devtools is not started, so calls are safe to leave in code paths.
- Routed through the **same `Issue` pipeline** (signature dedup, severity, aggregation)
  and broadcast via `postEvent`, so reported items appear in `get_issues` alongside
  detected ones, tagged `source: 'reported'`.
- `category` is preserved verbatim; reported issues are filterable by it.

Served by `get_issues(category?, severity?, sinceSeq?)`.

---

## Section 4 — Observer-Free Route Detection

The current route is derived from the **live element tree** during the existing
periodic snapshot, so it works with `MaterialApp.routes`, `MaterialApp.router`,
`go_router`, and Navigator 2.0 with **zero setup**.

- **Mechanism:** resolve the active `ModalRoute` from a stable element in the tree
  (read-only, inside a post-frame callback, guarded by try/catch so it never perturbs
  the app), then read `route.settings.name` / `runtimeType`. The exact no-side-effect
  accessor (`ModalRoute.of` vs. an inherited-widget lookup that does not register a
  build dependency) is pinned and test-proven during implementation.
- The optional `FlutterAiDevtools.observer` is **enrichment only**: attach it and you
  additionally get a precise push/pop/replace **timeline with timing**; omit it and you
  still get the current route. Nothing silently breaks.
- `get_current_route` returns the route plus a `source: 'auto' | 'observer'` field and,
  when the observer is attached, recent transitions.

---

## Section 5 — MCP Tool Surface

**New:**

| Tool | Returns |
|---|---|
| `get_logs` | Cursor tail of live console: `sinceSeq`, `level?`, `grep?`, `limit?` → entries + `nextSeq` |
| `get_issues` | Deduped/aggregated detected issues: `category?`, `severity?`, `sinceSeq?` |
| `get_connection_status` | Connected?, isolate id, app uptime, endpoint, last reconnect |
| `hot_reload` | Triggers `reloadSources` via VM service (fulfills README promise) |
| `get_memory_info` | Heap usage via `getMemoryUsage` (fulfills README promise) |

**Enhanced:**

- `get_runtime_summary` → adds connection status, live error/warn counts, top open
  issues, and the auto-detected route.
- `get_current_route` → observer-free, with `source` field.

**Unchanged:** `get_widget_tree`, `get_frame_stats`, `analyze_performance`,
`analyze_rebuilds`.

**Folded for backward compatibility:** `get_recent_errors` and `get_render_issues`
become thin filtered views over `get_issues` (kept as aliases — nothing breaks).

**App-side public API additions** (not MCP tools — they feed `get_issues`):
`FlutterAiDevtools.reportError(error, stack, {category, context})` and
`FlutterAiDevtools.reportIssue(title, {severity, category, context})` (Section 3.5),
plus the `IssueSeverity` enum exported for callers.

### 5.1 Continuous monitoring usage

Claude Code is pull-based, so "monitor my app" is realized as a **watch task**: the
developer asks once (*"watch the app and flag anything that breaks"*), and Claude polls
`get_logs(sinceSeq)` / `get_issues(sinceSeq)` on a cadence within that running task,
advancing the cursor so it only sees what is new. No background push and no unprompted
interruption are promised — those are outside any current MCP client's model.

---

## Section 6 — Consolidation & Cleanup

- **Delete the duplicate `cli/` package.** A single MCP layer lives in `lib/src/mcp/`
  + `bin/devtools_mcp.dart` (what `.mcp.json` already invokes). This is what the
  original production-restructure design intended (`cli/` was to be replaced).
- **Reconcile the README** tool table with the real tool surface; the `serve`/SSE path
  reuses the same `LiveBuffer` + `ToolDispatcher`, so SSE remains a real alternative
  rather than a divergent code path.
- **Fix the example app's stale text** ("MCP on localhost:8765") to reflect the
  stdio + debug-config flow.

---

## Section 7 — Testing Strategy

- **Unit:**
  - `LiveBuffer` — cursor monotonicity, ring eviction, dedup/aggregation, severity
    escalation.
  - Each detector — feed sample log/error lines → assert the expected `Issue`.
  - `reportError` / `reportIssue` — assert no-op before `start()`, and that after
    `start()` the call produces an `Issue` with `source: 'reported'`, the given
    `category`, and dedup/aggregation on repeat.
  - Route resolver — `WidgetTester`-pumped app across `MaterialApp.routes`, `go_router`,
    and Navigator 2.0 → assert correct current route with no observer wired.
- **Connection (headline fix):** inject a fake VM connector →
  - app-absent: tool returns the actionable message **and the bridge stays alive**;
  - app appears: subsequent tool call succeeds;
  - `IsolateExit` / hot-restart: assert auto-reconnect and re-subscription.
- **Integration:**
  - stdio JSON-RPC roundtrip (`initialize` → `tools/list` → `tools/call`).
  - VM-stream ingestion with a fake `VmService` feeding `Stdout`/`Logging`/`Extension`
    → assert entries surface in `get_logs` / `get_issues`.
  - Widget test that pumps the app, triggers an overflow + a setState-after-dispose,
    and asserts the issues arrive via the service-extension / `postEvent` path.
- Keep existing `RuntimeStore` and SSE tests passing.

---

## Out of Scope (this iteration)

- Companion VSCode extension (chosen against in favor of the debug config).
- MCP push notifications / external dashboard (always-fresh-on-pull chosen instead).
- Expanded performance detection beyond existing frame/rebuild collectors.
- General memory-leak detection without a Flutter-emitted signal.
- Framework adapters (BLoC, Riverpod, Dio, etc.).
