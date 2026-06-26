// bin/setup.dart
import 'dart:io';

import 'package:flutter_ai_devtools/src/setup/launch_config.dart';

Future<void> main(List<String> args) async {
  await _writeMcpJson();
  await _writeVsCodeLaunch();
  _printInstructions();
}

Future<void> _writeMcpJson() async {
  final file = File('.mcp.json');
  final existing = await file.exists() ? await file.readAsString() : null;
  try {
    await file.writeAsString(mergeMcpJson(existing));
    stdout.writeln('✓ Merged flutter_ai_devtools into .mcp.json (stdio transport)');
  } on FormatException {
    stdout.writeln('⚠ .mcp.json exists but could not be parsed — leaving it '
        'unchanged. Add a "flutter_ai_devtools" stdio server (command: dart, '
        'args: [run, flutter_ai_devtools:devtools_mcp]) manually.');
  }
}

Future<void> _writeVsCodeLaunch() async {
  await Directory('.vscode').create(recursive: true);
  final file = File('.vscode/launch.json');
  final existing = await file.exists() ? await file.readAsString() : null;
  try {
    final merged = mergeLaunchConfig(existing);
    await file.writeAsString(renderLaunchJson(merged));
    stdout.writeln('✓ Merged "Flutter + AI DevTools" into .vscode/launch.json');
  } on FormatException {
    stdout.writeln('⚠ .vscode/launch.json exists but could not be parsed '
        '(e.g. contains // comments) — leaving it unchanged. Add a dart launch '
        'config named "Flutter + AI DevTools" with args '
        '--host-vmservice-port=8181 --disable-service-auth-codes manually.');
  }
}

void _printInstructions() {
  stdout.writeln('''

Setup complete!

1. Add to your main():
     await FlutterAiDevtools.start();

2. In VSCode's Run panel, pick "Flutter + AI DevTools" and press Run.
   (This pins the VM-service port so the bridge connects deterministically.)

3. In Claude Code, run /mcp — flutter_ai_devtools shows connected.
   Claude Code starts the bridge automatically; no second terminal needed.
''');
}
