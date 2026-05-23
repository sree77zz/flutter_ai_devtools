import 'dart:convert';
import 'dart:io';

const _lockfileName = '.dart_tool/flutter_ai_devtools.json';

Future<void> writeLockfile({required int mcpPort}) async {
  final file = File(_lockfilePath());
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode({
    'mcpPort': mcpPort,
    'pid': pid,
    'startedAt': DateTime.now().toIso8601String(),
  }));
}

Future<void> deleteLockfile() async {
  final file = File(_lockfilePath());
  if (await file.exists()) await file.delete();
}

Future<Map<String, dynamic>?> readLockfile() async {
  final file = File(_lockfilePath());
  if (!await file.exists()) return null;
  try {
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

bool isProcessAlive(int pid) {
  if (Platform.isWindows) return true; // lockfile presence is the primary signal
  try {
    Process.killPid(pid, ProcessSignal.sigusr1);
    return true;
  } catch (_) {
    return false;
  }
}

String _lockfilePath() =>
    '${Directory.current.path}${Platform.pathSeparator}$_lockfileName';
