# flutter_ai_devtools

Exposes a running Flutter app's runtime to Claude Code (and other MCP clients) via the Model Context Protocol. Ask Claude about your app's **live logs, detected issues, routes, widget tree, frame performance, and errors** — and report your own handled errors so Claude sees them too. No manual server, no second terminal.

## How it works

Claude Code launches the MCP bridge automatically (`dart run flutter_ai_devtools:devtools_mcp`). The bridge is a resilient daemon: it connects to your running app's Dart VM service, **auto-reconnects** on hot-restart/app-death, continuously **ingests the app's console** (stdout/stderr/`developer.log`), and forwards tool calls as VM service-extension invocations.

```
Claude Code  ←stdio→  devtools_mcp (daemon)  ←VM service ws→  Flutter app
```

## Setup

**1. Add the dependency**

```yaml
dependencies:
  flutter_ai_devtools: ^0.1.0
  # until published, use a path/git dependency:
  # flutter_ai_devtools: { git: https://github.com/sree77zz/flutter_ai_devtools.git }
```

**2. Initialize in `main()`**

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterAiDevtools.start();
  runApp(const MyApp());
}
```

Route tracking is **observer-free** — it works with `MaterialApp.routes`, `go_router`, and Navigator 2.0 out of the box. The observer is optional; add it only if you also want a precise push/pop timeline:

```dart
MaterialApp(
  navigatorObservers: [FlutterAiDevtools.observer], // optional
  ...
)
```

**3. Generate config files (one time)**

```
dart run flutter_ai_devtools:setup
```

This writes `.mcp.json` (stdio transport) and merges a **"Flutter + AI DevTools"** debug configuration into `.vscode/launch.json` (it preserves your other configs and MCP servers). The config pins the host VM-service port so the bridge connects deterministically — including on physical devices/emulators.

**4. Run your app via the debug config**

In VS Code's **Run and Debug** panel, pick **"Flutter + AI DevTools"** and press Run. (Terminal equivalent: `flutter run --host-vmservice-port=8181 --disable-service-auth-codes`.)

**5. Connect in Claude Code**

Run `/mcp` — `flutter_ai_devtools` should show connected. The bridge starts automatically; no second terminal needed.

## Available tools

| Tool | What it returns |
|------|----------------|
| `get_logs` | Live console tail (stdout/stderr/`developer.log`) since a cursor; filter by level/grep |
| `get_issues` | Deduplicated issues — exceptions, layout/render, lifecycle, and reported — filter by category/severity |
| `get_runtime_summary` | Health snapshot: FPS, jank, error/issue counts, current route, top rebuilds |
| `get_current_route` | Active route (observer-free) |
| `get_widget_tree` | Widget hierarchy (configurable depth) |
| `get_recent_errors` | Recent unhandled exceptions |
| `get_render_issues` | Render problems (overflow, constraints) |
| `get_frame_stats` | Frame timing and jank rate |
| `analyze_performance` | Performance insights (jank, excessive rebuilds, render issues) |
| `analyze_rebuilds` | Most frequently rebuilding widgets |
| `get_connection_status` | Whether the bridge is connected to the app |
| `hot_reload` | Triggers a hot reload |
| `get_memory_info` | Heap usage |

## Reporting handled errors

Errors you `catch` and handle (and don't log) are invisible to any tool. Surface them with one line so they appear in `get_issues`:

```dart
try {
  await api.charge(order);
} catch (e, st) {
  FlutterAiDevtools.reportError(e, st, category: 'api', context: {'orderId': order.id});
}

// Non-exception problems (validation failures, invariant breaks):
FlutterAiDevtools.reportIssue('Cart total mismatch',
    severity: IssueSeverity.error, context: {'expected': 1200, 'actual': 1150});
```

Both are no-ops when devtools isn't started, so they're safe to leave in production code paths.

## Example prompts

- *"Show me the live logs"* / *"any errors in the logs?"*
- *"What issues does my app have right now?"* (`get_issues`)
- *"Give me a runtime summary — is anything janky?"*
- *"What's the current route?"*
- *"Which widgets rebuild the most?"*

## Requirements

- Flutter 3.x+, Dart 3.3+
- An MCP client (Claude Code, etc.)
- App must run in **debug mode** — release mode disables the VM service

## SSE transport (alternative)

The default transport is stdio. For an SSE client (e.g. browser-based):

```
dart run flutter_ai_devtools:serve
```

Then connect your client to `http://localhost:8765/sse`.
