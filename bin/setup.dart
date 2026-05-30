// bin/setup.dart
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  await _writeMcpJson();
  await _writeVsCodeLaunch();
  _printInstructions();
}

Future<void> _writeMcpJson() async {
  const config = {
    'mcpServers': {
      'flutter_ai_devtools': {
        'type': 'stdio',
        'command': 'dart',
        'args': ['run', 'flutter_ai_devtools:devtools_mcp'],
      },
    },
  };
  final file = File('.mcp.json');
  if (await file.exists()) {
    stdout.write('.mcp.json already exists. Overwrite? [y/N] ');
    final answer = stdin.readLineSync()?.toLowerCase() ?? 'n';
    if (answer != 'y') {
      stdout.writeln('Skipped .mcp.json.');
      return;
    }
  }
  await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(config)}\n');
  stdout.writeln('✓ Created .mcp.json (stdio transport — no second terminal needed)');
}

Future<void> _writeVsCodeLaunch() async {
  await Directory('.vscode').create(recursive: true);
  final file = File('.vscode/launch.json');
  const config = {
    'version': '0.2.0',
    'configurations': [
      {
        'name': 'Flutter + AI DevTools',
        'request': 'launch',
        'type': 'dart',
        'args': [
          '--vm-service-port=8181',
          '--disable-service-auth-codes',
        ],
      },
    ],
  };
  if (await file.exists()) {
    stdout.write('.vscode/launch.json already exists. Overwrite? [y/N] ');
    final answer = stdin.readLineSync()?.toLowerCase() ?? 'n';
    if (answer != 'y') {
      stdout.writeln('Skipped .vscode/launch.json.');
      return;
    }
  }
  await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(config)}\n');
  stdout.writeln('✓ Created .vscode/launch.json');
}

void _printInstructions() {
  stdout.writeln('''

Setup complete!

1. Add to your main():
     await FlutterAiDevtools.start();

2. Run your Flutter app:
     flutter run --vm-service-port=8181 --disable-service-auth-codes
   or use the "Flutter + AI DevTools" VS Code launch config.

3. In Claude Code, run /mcp — flutter_ai_devtools should show connected.
   Claude Code starts the MCP bridge automatically; no second terminal needed.
''');
}
