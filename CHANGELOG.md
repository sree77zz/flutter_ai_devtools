# Changelog

## 0.1.0

Initial release.

- Resilient `devtools_mcp` bridge: auto-discovers the running app's Dart VM
  service, retries until it appears, and auto-reconnects on hot-restart or
  app death. Launch via the generated **"Flutter + AI DevTools"** debug config —
  no second terminal needed.
- **Live console** (`get_logs`): cursor-based tail of stdout/stderr/`developer.log`,
  filterable by level and substring.
- **Structured issues** (`get_issues`): deduplicated, severity-ranked issues —
  exceptions, layout/render, lifecycle, and developer-reported — with filters.
- **`FlutterAiDevtools.reportError()` / `reportIssue()`** to surface handled
  errors (caught but not logged) so AI clients can see them.
- **Observer-free route detection** — works with `MaterialApp.routes`,
  `go_router`, and Navigator 2.0; the navigator observer is optional.
- Performance + inspection tools: `get_runtime_summary`, `get_widget_tree`,
  `get_recent_errors`, `get_render_issues`, `get_frame_stats`,
  `analyze_performance`, `analyze_rebuilds`, `get_connection_status`,
  `hot_reload`, `get_memory_info`.
- `setup` command writes `.mcp.json` and idempotently merges a VS Code debug
  configuration (preserving existing configs and MCP servers).
- Optional SSE transport via `serve` for non-stdio MCP clients.
