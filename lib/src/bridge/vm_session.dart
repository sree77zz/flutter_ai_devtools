import 'dart:io';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

/// Snapshot of the bridge's link to the running app.
class ConnectionStatus {
  const ConnectionStatus({
    required this.connected,
    this.endpoint,
    this.isolateId,
    this.connectedAt,
    this.lastError,
  });

  final bool connected;
  final String? endpoint;
  final String? isolateId;
  final DateTime? connectedAt;
  final String? lastError;

  Map<String, dynamic> toJson() => {
        'connected': connected,
        if (endpoint != null) 'endpoint': endpoint,
        if (isolateId != null) 'isolateId': isolateId,
        if (connectedAt != null) 'connectedAt': connectedAt!.toIso8601String(),
        if (lastError != null) 'lastError': lastError,
      };
}

/// Minimal surface the bridge needs from the VM service. Abstracted so the
/// connection logic can be unit-tested with a fake (no live VM required).
abstract class VmSession {
  String get endpoint;
  String get mainIsolateId;

  Stream<vm.Event> get stdout;
  Stream<vm.Event> get stderr;
  Stream<vm.Event> get logging;

  /// Fires when the main isolate exits / is restarted (hot restart).
  Stream<void> get disconnected;

  Future<Map<String, dynamic>> callExtension(
      String method, Map<String, String> args);
  Future<void> reloadSources();
  Future<Map<String, dynamic>> memoryUsage();
  Future<void> dispose();
}

/// Connects to a real VM service and exposes it as a [VmSession].
/// Returns null on any failure (no isolates, refused connection, etc.).
typedef VmConnector = Future<VmSession?> Function(String wsUri);

Future<VmSession?> connectVmService(String wsUri) async {
  vm.VmService? service;
  try {
    service = await vmServiceConnectUri(wsUri);
    final vmObj = await service.getVM();
    final isolates = vmObj.isolates;
    if (isolates == null || isolates.isEmpty) {
      await service.dispose();
      return null;
    }
    final isolateId = isolates.first.id!;
    await service.streamListen(vm.EventStreams.kStdout);
    await service.streamListen(vm.EventStreams.kStderr);
    await service.streamListen(vm.EventStreams.kLogging);
    await service.streamListen(vm.EventStreams.kIsolate);
    return VmServiceSession(service, wsUri, isolateId);
  } catch (e) {
    await service?.dispose();
    stderr.writeln('[VmSession] connect failed: $e');
    return null;
  }
}

class VmServiceSession implements VmSession {
  VmServiceSession(this._service, this.endpoint, this.mainIsolateId);

  final vm.VmService _service;
  @override
  final String endpoint;
  @override
  final String mainIsolateId;

  @override
  Stream<vm.Event> get stdout => _service.onStdoutEvent;
  @override
  Stream<vm.Event> get stderr => _service.onStderrEvent;
  @override
  Stream<vm.Event> get logging => _service.onLoggingEvent;

  @override
  Stream<void> get disconnected => _service.onIsolateEvent
      .where((e) => e.kind == vm.EventKind.kIsolateExit)
      .map((_) {});

  @override
  Future<Map<String, dynamic>> callExtension(
      String method, Map<String, String> args) async {
    final r = await _service.callServiceExtension(
      method,
      isolateId: mainIsolateId,
      args: args,
    );
    return r.json ?? {};
  }

  @override
  Future<void> reloadSources() async {
    await _service.reloadSources(mainIsolateId);
  }

  @override
  Future<Map<String, dynamic>> memoryUsage() async {
    final m = await _service.getMemoryUsage(mainIsolateId);
    return {
      'heapUsage': m.heapUsage,
      'heapCapacity': m.heapCapacity,
      'externalUsage': m.externalUsage,
    };
  }

  @override
  Future<void> dispose() async {
    await _service.dispose();
  }
}
