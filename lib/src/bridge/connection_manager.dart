import 'dart:async';
import 'vm_session.dart';

/// Resolves the ordered list of candidate WebSocket URIs to try.
typedef CandidateResolver = Future<List<String>> Function();

/// Owns the never-die connect loop and reconnect-on-disconnect behavior.
///
/// [start] kicks off a background loop that keeps trying [candidates] through
/// [connector] until one yields a [VmSession]. When that session signals
/// [VmSession.disconnected] (app exit / hot restart), the loop resumes.
class ConnectionManager {
  ConnectionManager({
    required CandidateResolver candidates,
    required VmConnector connector,
    this.retryDelay = const Duration(seconds: 1),
  })  : _candidates = candidates,
        _connector = connector;

  final CandidateResolver _candidates;
  final VmConnector _connector;
  final Duration retryDelay;

  VmSession? _session;
  ConnectionStatus _status = const ConnectionStatus(connected: false);
  bool _running = false;
  StreamSubscription<void>? _disconnectSub;
  Completer<void>? _loopDone;

  VmSession? get session => _session;
  ConnectionStatus get status => _status;

  void start() {
    if (_running) return;
    _running = true;
    _loopDone = Completer<void>();
    unawaited(_loop());
  }

  Future<void> _loop() async {
    while (_running) {
      try {
        if (_session == null) {
          await _tryConnectOnce();
        }
      } catch (e) {
        _status = ConnectionStatus(connected: false, lastError: e.toString());
      }
      await Future<void>.delayed(retryDelay);
    }
    _loopDone?.complete();
  }

  Future<void> _tryConnectOnce() async {
    String? lastError;
    for (final uri in await _candidates()) {
      final wsUri = _toWs(uri);
      try {
        final s = await _connector(wsUri);
        if (!_running) {
          await s?.dispose();
          return;
        }
        if (s != null) {
          _session = s;
          _status = ConnectionStatus(
            connected: true,
            endpoint: s.endpoint,
            isolateId: s.mainIsolateId,
            connectedAt: DateTime.now(),
          );
          _disconnectSub = s.disconnected.listen(
            (_) => _onDisconnect(),
            onError: (_) => _onDisconnect(),
          );
          return;
        }
      } catch (e) {
        lastError = e.toString();
      }
    }
    _status = ConnectionStatus(connected: false, lastError: lastError);
  }

  void _onDisconnect() {
    _disconnectSub?.cancel();
    _disconnectSub = null;
    final old = _session;
    _session = null;
    _status = const ConnectionStatus(connected: false, lastError: 'app disconnected');
    unawaited(old?.dispose());
  }

  Future<void> dispose() async {
    _running = false;
    await _disconnectSub?.cancel();
    await _session?.dispose();
    _session = null;
    await _loopDone?.future;
  }

  static String _toWs(String uri) {
    if (uri.startsWith('ws://') || uri.startsWith('wss://')) return uri;
    final normalized = uri.endsWith('/') ? uri : '$uri/';
    final wsBase = normalized
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    return '${wsBase}ws';
  }
}
