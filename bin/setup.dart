// bin/setup.dart
import 'dart:convert';
import 'dart:io';

const _defaultPort = 8765;

void main(List<String> args) async {
  final port = _parsePort(args) ?? _defaultPort;

  final config = {
    'mcpServers': {
      'flutter_ai_devtools': {
        'type': 'sse',
        'url': 'http://localhost:$port/sse',
      },
    },
  };

  final mcpFile = File('.mcp.json');

  if (await mcpFile.exists()) {
    stdout.write(
      '.mcp.json already exists. Overwrite? [y/N] ',
    );
    final answer = stdin.readLineSync()?.toLowerCase() ?? 'n';
    if (answer != 'y') {
      stdout.writeln('Skipped. No changes made.');
      exit(0);
    }
  }

  await mcpFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(config)}\n',
  );

  stdout.writeln('✓ Created .mcp.json (port $port)');
  stdout.writeln('');
  stdout.writeln('Next steps:');
  stdout.writeln('  1. Add one line to your main():');
  stdout.writeln('       await FlutterAiDevtools.start();');
  stdout.writeln('  2. Run your Flutter app:  flutter run');
  stdout.writeln('  3. In Claude Code, run:   /mcp');
  stdout.writeln('     flutter_ai_devtools should appear as connected.');
}

int? _parsePort(List<String> args) {
  final idx = args.indexOf('--port');
  if (idx != -1 && idx + 1 < args.length) {
    return int.tryParse(args[idx + 1]);
  }
  return null;
}
