import 'dart:io';
import 'dart:convert';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import '../lockfile.dart';

class VmBridge {
  VmService? _service;
  String? _mainIsolateId;

  /// Connect to the Dart VM service at [vmUri].
  /// If [vmUri] is null, falls back to: lockfile → DART_VM_SERVICE_URI env → localhost:8181.
  Future<bool> connect([String? vmUri]) async {
    final uri = vmUri ?? await _resolveUri();
    if (uri == null) return false;

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
        stderr.writeln('[VmBridge] No isolates found');
        _service = null;
        return false;
      }
      _mainIsolateId = isolates.first.id;
      stderr.writeln('[VmBridge] Connected to VM at $uri');
      return true;
    } catch (e) {
      stderr.writeln('[VmBridge] Connection failed: $e');
      _service = null;
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
      return jsonDecode(response.json?['result'] as String? ?? '{}')
          as Map<String, dynamic>;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<void> dispose() async {
    await _service?.dispose();
    _service = null;
    _mainIsolateId = null;
  }

  static Future<String?> _resolveUri() async {
    // 1. Lockfile (works on desktop where the app can write it)
    final lockData = await readLockfile();
    final lockUri = lockData?['vmServiceUri'] as String?;
    if (lockUri != null) return lockUri;

    // 2. Environment variable (set manually or by wrapper scripts)
    final envUri = Platform.environment['DART_VM_SERVICE_URI'];
    if (envUri != null) return envUri;

    // 3. Fixed port (used when flutter run --vm-service-port=8181 --disable-service-auth-codes)
    return 'http://localhost:8181/';
  }
}
