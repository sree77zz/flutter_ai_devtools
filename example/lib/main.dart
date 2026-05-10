import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ai_devtools/flutter_ai_devtools.dart';

/// Example demonstrating flutter_ai_devtools integration.
///
/// Run this app, then connect Claude Desktop or Cursor to the MCP server at
/// localhost:8765. Ask Claude: "What is the current route?" or
/// "Analyze my app's performance."
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize with TCP transport on port 8765.
  await FlutterAiAnalyst.initialize(
    config: const AnalystConfig(
      mcpPort: 8765,
      mcpHost: 'localhost',
      enableWidgetCollector: true,
      enableErrorCollector: true,
      enableRouteCollector: true,
      enableFrameCollector: true,
      enableRenderCollector: true,
      frameWindowSize: 300,
      errorHistorySize: 100,
    ),
    mcpTransport: McpTransport.sse,
    // Optionally add adapters:
    // adapters: [BlocAdapter(FlutterAiAnalyst.engine.eventBus)],
  );

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_ai_devtools Example',
      debugShowCheckedModeBanner: false,
      // Attach the NavigatorObserver to capture route events.
      navigatorObservers: [FlutterAiAnalyst.navigatorObserver],
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

// â”€â”€ Home Screen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _counter = 0;
  String _status = 'Analyst engine runningâ€¦';

  @override
  void initState() {
    super.initState();
    // Subscribe to events for demo purposes.
    FlutterAiAnalyst.engine.eventBus.events.listen((event) {
      if (!mounted) return;
      setState(() => _status = '${event.type.name}: ${event.source}');
    });
  }

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
            const SizedBox(height: 24),
            _McpInfoCard(),
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
      const SnackBar(content: Text('Test error emitted â€” check MCP client!')),
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
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MCP Server',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            const Text('TCP â†’ localhost:8765'),
            const SizedBox(height: 4),
            const Text(
              'Available tools: get_runtime_summary, get_widget_tree, '
              'get_current_route, get_recent_errors, get_frame_stats, '
              'analyze_performance, analyze_rebuilds, get_render_issues',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Detail Screen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

// â”€â”€ Settings Screen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
