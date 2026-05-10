## 0.1.0

* Initial release.
* Core engine with EventBus, RuntimeStore, AnalyzerEngine.
* Collectors: Widget, Error, Route, Frame, Render.
* Adapters: Bloc, Riverpod, GetX, Dio, Firebase.
* MCP tools: get_widget_tree, get_current_route, get_recent_errors,
  get_render_issues, get_frame_stats, analyze_performance,
  analyze_rebuilds, get_runtime_summary.
* MCP transport: stdio and TCP (JSON-RPC 2.0).
* Built-in analyzer steps: jank, rebuild, render issue detectors.
