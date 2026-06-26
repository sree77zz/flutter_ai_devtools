import 'package:flutter/material.dart';
import 'package:flutter_ai_devtools/flutter_ai_devtools.dart';

/// Example demonstrating flutter_ai_devtools integration.
///
/// Run this app, then configure Claude Code to connect to the MCP server at
/// localhost:8765. Ask Claude: "What is the current route?" or
/// "Analyze my app's performance."
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterAiDevtools.start();
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_ai_devtools Example',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [FlutterAiDevtools.observer],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeScreen(),
        '/detail': (_) => const DetailScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}

// ── Home Screen ──────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _counter = 0;
  final String _status =
      'DevTools running — Claude connects via the auto-started MCP bridge';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('flutter_ai_devtools'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(status: _status),
            const SizedBox(height: 24),
            Text(
              'Counter: $_counter',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => setState(() => _counter++),
              icon: const Icon(Icons.add),
              label: const Text('Increment (triggers rebuild tracking)'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/detail'),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Go to Detail (route tracking)'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/settings'),
              icon: const Icon(Icons.settings),
              label: const Text('Settings'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _triggerTestError,
              icon: const Icon(Icons.warning, color: Colors.orange),
              label: const Text('Trigger test error (error collector)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _reportHandledError,
              icon: const Icon(Icons.report, color: Colors.red),
              label: const Text('Report a handled error (reportError → get_issues)'),
            ),
            const SizedBox(height: 24),
            const _McpInfoCard(),
          ],
        ),
      ),
    );
  }

  void _triggerTestError() {
    FlutterError.reportError(FlutterErrorDetails(
      exception: Exception('Test error from flutter_ai_devtools example'),
      stack: StackTrace.current,
      library: 'example',
      context: ErrorDescription('triggered manually for demonstration'),
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Test error emitted — check MCP client!')),
    );
  }

  /// Demonstrates surfacing a *handled* error (caught, not rethrown) so it still
  /// shows up in `get_issues` — the kind of error nothing else can see.
  void _reportHandledError() {
    try {
      throw Exception('Simulated API failure: charge declined');
    } catch (e, st) {
      FlutterAiDevtools.reportError(
        e,
        st,
        category: 'api',
        context: {'orderId': _counter, 'endpoint': '/charge'},
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Handled error reported — ask Claude: get_issues')),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.deepPurple.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.circle, color: Colors.green, size: 12),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                status,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _McpInfoCard extends StatelessWidget {
  const _McpInfoCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MCP Bridge',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            const Text('Claude Code → devtools_mcp (stdio) → VM service → app'),
            const SizedBox(height: 8),
            const Text(
              'Bridge auto-starts via .mcp.json (run dart run flutter_ai_devtools:setup once).\n'
              'Tools: get_logs, get_issues, get_runtime_summary, get_current_route,\n'
              'get_widget_tree, get_recent_errors, get_render_issues, get_frame_stats,\n'
              'analyze_performance, analyze_rebuilds, get_connection_status,\n'
              'hot_reload, get_memory_info',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detail Screen ─────────────────────────────────────────────────────────────

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detail')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Route: /detail'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'), 
            ),
          ],
        ),
      ),
    );
  }
}

// ── Settings Screen ───────────────────────────────────────────────────────────

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Route: /settings'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
