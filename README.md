# flutter_ai_devtools

Exposes Flutter runtime data to Claude Code via MCP (Model Context Protocol). Ask Claude about your running app's routes, widget tree, frame performance, errors, and more — no manual server setup needed.

## How it works

Claude Code launches the MCP bridge automatically (`dart run flutter_ai_devtools:devtools_mcp`). The bridge connects to your running Flutter app's Dart VM service and forwards tool calls as service extension invocations.

```
Claude Code  ←stdio→  devtools_mcp  ←VM service ws→  Flutter app
```

## Setup

**1. Add the dependency**

```yaml
dependencies:
  flutter_ai_devtools: ^0.1.0
```

**2. Initialize in main()**

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterAiDevtools.start();
  runApp(const MyApp());
}
```

Add the navigator observer if you want route tracking:

```dart
MaterialApp(
  navigatorObservers: [FlutterAiDevtools.observer],
  ...
)
```

**3. Generate config files**

```
dart run flutter_ai_devtools:setup
```

This writes `.mcp.json` (stdio transport) and `.vscode/launch.json` (fixed VM port).

**4. Run your app**

```
flutter run
```

That's it. The bridge discovers the VM service URI automatically via a temp-directory lockfile written by `FlutterAiDevtools.start()`.

**5. Connect in Claude Code**

Run `/mcp` — `flutter_ai_devtools` should show connected. No second terminal needed.

## Available tools

| Tool | What it returns |
|------|----------------|
| `get_current_route` | Active route name |
| `get_runtime_summary` | FPS, error count, rebuild counts |
| `get_widget_tree` | Widget hierarchy (configurable depth) |
| `get_recent_errors` | Recent unhandled exceptions |
| `get_frame_stats` | Frame timing and jank rate |
| `get_memory_info` | Heap usage |
| `hot_reload` | Triggers a hot reload |
| `get_service_extensions` | Lists registered VM service extensions |

## Example prompts

- *"What's the current route in my Flutter app?"*
- *"Give me a runtime summary — is anything janky?"*
- *"Show me the widget tree up to 3 levels deep."*
- *"Are there any recent errors?"*

## Requirements

- Flutter 3.x+, Dart 3.3+
- Claude Code with MCP support
- App must be running in debug mode (`flutter run`) — release mode disables the VM service

## SSE transport (alternative)

The default transport is stdio. If you need SSE (e.g. for a browser-based client):

```
dart run flutter_ai_devtools:serve
```

Then configure your client to connect to `http://localhost:8765/sse`.
