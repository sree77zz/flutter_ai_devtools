import 'dart:async';
import 'dart:io';
import 'package:vm_service/vm_service.dart' as vm;
import '../lockfile.dart';
import '../models/log_entry.dart';
import 'connection_manager.dart';
import 'live_buffer.dart';
import 'log_normalizer.dart';
import 'vm_session.dart';

/// Resilient bridge between the MCP server and a running Flutter app's VM service.
///
/// Never throws on a missing app: [start] launches a background connect loop,
/// and [liveBuffer] fills from the app's stdout/stderr/logging streams whenever
/// a session is live. Tool handlers call [callTool]/[hotReload]/[memoryInfo]/
/// [status]; when disconnected these return a clear, actionable result.
class VmBridge {
  VmBridge({
    LiveBuffer? liveBuffer,
    VmConnector connector = connectVmService,
    Duration retryDelay = const Duration(seconds: 1),
  })  : liveBuffer = liveBuffer ?? LiveBuffer(),
        _manager = ConnectionManager(
          candidates: _candidateUris,
          connector: connector,
          retryDelay: retryDelay,
        );

  final LiveBuffer liveBuffer;
  final ConnectionManager _manager;
  final _logSubs = <StreamSubscription<vm.Event>>[];
  VmSession? _ingestingSession;
  Timer? _ingestionTimer;

  /// Begins the resilient connect loop and (re)attaches log ingestion as
  /// sessions come and go.
  void start() {
    _manager.start();
    _ingestionTimer = Timer.periodic(
        const Duration(milliseconds: 500), (_) => _syncIngestion());
  }

  void _syncIngestion() {
    final s = _manager.session;
    if (identical(s, _ingestingSession)) return;
    for (final sub in _logSubs) {
      sub.cancel();
    }
    _logSubs.clear();
    _ingestingSession = s;
    if (s == null) return;
    _logSubs.add(s.stdout.listen((e) => _ingest(e, LogSource.stdout)));
    _logSubs.add(s.stderr.listen((e) => _ingest(e, LogSource.stderr)));
    _logSubs.add(s.logging.listen((e) => _ingest(e, LogSource.developerLog)));
  }

  void _ingest(vm.Event event, LogSource source) {
    final entry = normalizeVmEvent(event, source: source);
    if (entry != null) liveBuffer.addLog(entry);
  }

  ConnectionStatus get status => _manager.status;
  bool get connected => _manager.status.connected;

  Future<Map<String, dynamic>> callTool(
      String name, Map<String, dynamic> args) async {
    final s = _manager.session;
    if (s == null) return _notConnected();
    try {
      return await s.callExtension(
        'ext.flutter_ai_devtools.$name',
        args.map((k, v) => MapEntry(k, v.toString())),
      );
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> hotReload() async {
    final s = _manager.session;
    if (s == null) return _notConnected();
    try {
      await s.reloadSources();
      return {'reloaded': true};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> memoryInfo() async {
    final s = _manager.session;
    if (s == null) return _notConnected();
    try {
      return await s.memoryUsage();
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<void> dispose() async {
    _ingestionTimer?.cancel();
    _ingestionTimer = null;
    for (final sub in _logSubs) {
      await sub.cancel();
    }
    _logSubs.clear();
    await _manager.dispose();
  }

  static Map<String, dynamic> _notConnected() => {
        'error': 'Flutter app not connected. Launch the "Flutter + AI DevTools" '
            'run configuration (or: flutter run --host-vmservice-port=8181 '
            '--disable-service-auth-codes).',
      };

  /// Ordered discovery: pinned port → desktop lockfile → env override.
  static Future<List<String>> _candidateUris() async {
    final candidates = <String>['http://127.0.0.1:8181/'];
    final lockData = await readLockfile();
    if (lockData != null) {
      final lockUri = lockData['vmServiceUri'] as String?;
      final lockPid = lockData['pid'] as int?;
      if (lockUri != null && (lockPid == null || isProcessAlive(lockPid))) {
        candidates.add(lockUri);
      }
    }
    final envUri = Platform.environment['DART_VM_SERVICE_URI'];
    if (envUri != null) candidates.add(envUri);
    return candidates;
  }
}
