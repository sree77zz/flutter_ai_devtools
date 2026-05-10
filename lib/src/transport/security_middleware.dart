import '../logging/analyst_logger.dart';

/// Simple bearer-token security middleware for the MCP server.
///
/// When [tokens] is empty, all connections are accepted (development mode).
/// In production, provide one or more secret tokens in [AnalystConfig].
class SecurityMiddleware {
  SecurityMiddleware(List<String> tokens)
      : _tokens = Set.unmodifiable(tokens),
        _permissive = tokens.isEmpty;

  final Set<String> _tokens;
  final bool _permissive;
  final _log = AnalystLogger.forName('SecurityMiddleware');

  bool authorize(String? bearerToken) {
    if (_permissive) return true;
    if (bearerToken == null || bearerToken.isEmpty) {
      _log.warning('Connection rejected: missing bearer token');
      return false;
    }
    final token = bearerToken.startsWith('Bearer ')
        ? bearerToken.substring(7)
        : bearerToken;
    final ok = _tokens.contains(token);
    if (!ok) _log.warning('Connection rejected: invalid token');
    return ok;
  }

  bool get isPermissive => _permissive;
}
