import '../logging/analyst_logger.dart';

/// Tracks active MCP client sessions.
class SessionInfo {
  SessionInfo({
    required this.sessionId,
    required this.clientId,
    required this.connectedAt,
    this.metadata = const {},
  });

  final String sessionId;
  final String clientId;
  final DateTime connectedAt;
  final Map<String, String> metadata;
  int requestCount = 0;
  DateTime lastActiveAt = DateTime.now();

  Duration get duration => DateTime.now().difference(connectedAt);

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'clientId': clientId,
        'connectedAt': connectedAt.toIso8601String(),
        'lastActiveAt': lastActiveAt.toIso8601String(),
        'durationSeconds': duration.inSeconds,
        'requestCount': requestCount,
        'metadata': metadata,
      };
}

/// Manages active MCP sessions — creation, lookup, update, and expiry.
class SessionManager {
  SessionManager({this.sessionTimeoutSeconds = 300});

  final int sessionTimeoutSeconds;
  final _sessions = <String, SessionInfo>{};
  final _log = AnalystLogger.forName('SessionManager');

  SessionInfo createSession({
    required String sessionId,
    required String clientId,
    Map<String, String> metadata = const {},
  }) {
    final session = SessionInfo(
      sessionId: sessionId,
      clientId: clientId,
      connectedAt: DateTime.now(),
      metadata: metadata,
    );
    _sessions[sessionId] = session;
    _log.info('Session created: $sessionId (client: $clientId)');
    _evictExpired();
    return session;
  }

  SessionInfo? getSession(String sessionId) => _sessions[sessionId];

  void touchSession(String sessionId) {
    final s = _sessions[sessionId];
    if (s != null) {
      s.lastActiveAt = DateTime.now();
      s.requestCount++;
    }
  }

  void removeSession(String sessionId) {
    if (_sessions.remove(sessionId) != null) {
      _log.info('Session removed: $sessionId');
    }
  }

  List<SessionInfo> get activeSessions =>
      List.unmodifiable(_sessions.values);

  void _evictExpired() {
    final now = DateTime.now();
    final expired = _sessions.values
        .where((s) =>
            now.difference(s.lastActiveAt).inSeconds > sessionTimeoutSeconds)
        .map((s) => s.sessionId)
        .toList();
    for (final id in expired) {
      _sessions.remove(id);
      _log.debug('Evicted expired session: $id');
    }
  }
}
