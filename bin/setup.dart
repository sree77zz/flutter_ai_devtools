// bin/setup.dart
import 'dart:convert';
import 'dart:io';

const _defaultMcpPort = 8765;
const _defaultVmPort = 8181;

Future<void> main(List<String> args) async {
  final mcpPort = _argInt(args, '--port') ?? _defaultMcpPort;

  await _writeMcpJson(mcpPort);
  await _writeVsCodeLaunch();

  stdout.writeln('');
  stdout.writeln('Setup complete!');
  stdout.writeln('');
  stdout.writeln('Add one line to your main():');
  stdout.writeln('  await FlutterAiDevtools.start();');
  stdout.writeln('');
  stdout.writeln('Then, two terminals when developing:');
  stdout.writeln(
      '  Terminal 1: Use the "Flutter + AI DevTools" VS Code launch config');
  stdout.writeln(
      '               OR: flutter run --vm-service-port=$_defaultVmPort --disable-service-auth-codes');
  stdout.writeln('  Terminal 2: dart run flutter_ai_devtools:serve');
  stdout.writeln('');
  stdout.writeln(
      'In Claude Code: /mcp → flutter_ai_devtools should show connected.');
}

Future<void> _writeMcpJson(int mcpPort) async {
  final config = {
    'mcpServers': {
      'flutter_ai_devtools': {
        'type': 'sse',
        'url': 'http://localhost:$mcpPort/sse',
      },
    },
  };
  final mcpFile = File('.mcp.json');
  if (await mcpFile.exists()) {
    stdout.write('.mcp.json already exists. Overwrite? [y/N] ');
    final answer = stdin.readLineSync()?.toLowerCase() ?? 'n';
    if (answer != 'y') {
      stdout.writeln('Skipped .mcp.json.');
      return;
    }
  }
  await _writeJson(mcpFile, config);
  stdout.writeln('✓ Created .mcp.json');
}

Future<void> _writeVsCodeLaunch() async {
  final dir = Directory('.vscode');
  if (!await dir.exists()) await dir.create();

  final launchFile = File('.vscode/launch.json');
  final config = {
    'version': '0.2.0',
    'configurations': [
      {
        'name': 'Flutter + AI DevTools',
        'request': 'launch',
        'type': 'dart',
        'args': [
          '--vm-service-port=$_defaultVmPort',
          '--disable-service-auth-codes',
        ],
      },
    ],
  };

  if (await launchFile.exists()) {
    stdout.write('.vscode/launch.json already exists. Overwrite? [y/N] ');
    final answer = stdin.readLineSync()?.toLowerCase() ?? 'n';
    if (answer != 'y') {
      stdout.writeln('Skipped .vscode/launch.json.');
      return;
    }
  }
  await _writeJson(launchFile, config);
  stdout.writeln('✓ Created .vscode/launch.json (launch config with fixed VM port)');
}

Future<void> _writeJson(File file, Object data) async {
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(data)}\n',
  );
}

int? _argInt(List<String> args, String flag) {
  final idx = args.indexOf(flag);
  if (idx != -1 && idx + 1 < args.length) return int.tryParse(args[idx + 1]);
  return null;
}
