import 'dart:convert';
import 'dart:io';

Future<void> writeLockfile({int? mcpPort, String? vmServiceUri}) async {
  // Only desktop platforms can expose a lockfile that the CLI can actually read.
  // On Android/iOS the filesystem isn't accessible from the host machine.
  if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) return;
  final file = File(_lockfilePath());
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode({
    if (mcpPort != null) 'mcpPort': mcpPort,
    if (vmServiceUri != null) 'vmServiceUri': vmServiceUri,
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

bool isProcessAlive(int targetPid) {
  if (Platform.isWindows) {
    try {
      // Use tasklist to check if process exists
      final result = Process.runSync(
        'tasklist',
        ['/FI', 'PID eq $targetPid', '/NH', '/FO', 'CSV'],
      );
      return result.stdout.toString().contains('"$targetPid"');
    } catch (_) {
      return true; // assume alive if check fails
    }
  }
  try {
    Process.killPid(targetPid, ProcessSignal.sigusr1);
    return true;
  } catch (_) {
    return false;
  }
}

String _lockfilePath() =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}flutter_ai_devtools.json';
