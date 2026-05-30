import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import '../lockfile.dart';

class VmBridge {
  VmService? _service;
  String? _mainIsolateId;

  /// Connect to the Dart VM service.
  ///
  /// If [vmUri] is supplied, connects directly to that URI.
  /// Otherwise tries each candidate in order: lockfile → DART_VM_SERVICE_URI
  /// env var → fixed port 8181.  A stale lockfile URI (dead process) is
  /// skipped automatically.
  Future<bool> connect([String? vmUri]) async {
    if (_service != null && _mainIsolateId != null) return true;
    if (vmUri != null) return _connectTo(vmUri);

    for (final uri in await _candidateUris()) {
      if (await _connectTo(uri)) return true;
    }
    return false;
  }

  Future<bool> _connectTo(String uri) async {
    try {
      final normalized = uri.endsWith('/') ? uri : '$uri/';
      final wsBase = normalized
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      final ws = '${wsBase}ws';
      _service = await vmServiceConnectUri(ws);
      final vm = await _service!.getVM();
      final isolates = vm.isolates;
      if (isolates == null || isolates.isEmpty) {
        stderr.writeln('[VmBridge] No isolates found at $uri');
        _service = null;
        _mainIsolateId = null;
        return false;
      }
      _mainIsolateId = isolates.first.id;
      stderr.writeln('[VmBridge] Connected to VM at $uri');
      return true;
    } catch (e) {
      stderr.writeln('[VmBridge] Connection failed: $e');
      _service = null;
      _mainIsolateId = null;
      return false;
    }
  }

  Future<Map<String, dynamic>> callTool(
      String name, Map<String, dynamic> args) async {
    if (_service == null || _mainIsolateId == null) {
      return {'error': 'Not connected to Flutter app'};
    }
    try {
      final response = await _service!.callServiceExtension(
        'ext.flutter_ai_devtools.$name',
        isolateId: _mainIsolateId,
        args: args.map((k, v) => MapEntry(k, v.toString())),
      );
      // response.json IS the decoded data map the extension returned.
      // There is no nested 'result' string field.
      return response.json ?? {};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<void> dispose() async {
    await _service?.dispose();
    _service = null;
    _mainIsolateId = null;
  }

  static Future<List<String>> _candidateUris() async {
    final candidates = <String>[];

    // 1. Lockfile (written by the Flutter app on desktop).
    //    Skip if the app process is no longer alive (stale entry).
    final lockData = await readLockfile();
    if (lockData != null) {
      final lockUri = lockData['vmServiceUri'] as String?;
      final lockPid = lockData['pid'] as int?;
      if (lockUri != null &&
          (lockPid == null || isProcessAlive(lockPid))) {
        candidates.add(lockUri);
      }
    }

    // 2. Environment variable (manual override or wrapper scripts).
    final envUri = Platform.environment['DART_VM_SERVICE_URI'];
    if (envUri != null) candidates.add(envUri);

    // 3. Fixed port — works when flutter run uses
    //    --vm-service-port=8181 --disable-service-auth-codes.
    candidates.add('http://localhost:8181/');

    return candidates;
  }
}
