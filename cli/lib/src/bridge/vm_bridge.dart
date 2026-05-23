// cli/lib/src/bridge/vm_bridge.dart
import 'dart:io';
import 'dart:convert';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:flutter_ai_devtools/src/lockfile.dart';

class VmBridge {
  VmService? _service;
  String? _mainIsolateId;

  Future<bool> connect() async {
    final lockData = await readLockfile();
    if (lockData == null) return false;

    final lockPid = lockData['pid'] as int?;
    if (lockPid != null && !isProcessAlive(lockPid)) {
      stderr.writeln('✗ App not running. Run: flutter run');
      return false;
    }

    final vmUri = lockData['vmServiceUri'] as String?
        ?? Platform.environment['FLUTTER_VM_SERVICE_URI'];

    if (vmUri == null) {
      stderr.writeln(
        '✗ vmServiceUri not in lockfile and FLUTTER_VM_SERVICE_URI not set.\n'
        'Run the app with: flutter run --vm-service-port 8181',
      );
      return false;
    }

    try {
      final normalized = vmUri.endsWith('/') ? vmUri : '$vmUri/';
      final wsBase = normalized
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      final ws = '${wsBase}ws';
      _service = await vmServiceConnectUri(ws);
      final vm = await _service!.getVM();
      final isolates = vm.isolates;
      if (isolates == null || isolates.isEmpty) {
        stderr.writeln('✗ No isolates found in Flutter app');
        _service = null;
        return false;
      }
      _mainIsolateId = isolates.first.id;
      stderr.writeln('✓ Connected to Flutter app (pid $lockPid)');
      return true;
    } catch (e) {
      stderr.writeln('✗ Connection failed: $e');
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
}
