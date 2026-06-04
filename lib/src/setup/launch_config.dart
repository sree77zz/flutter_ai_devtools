import 'dart:convert';

const _kConfigName = 'Flutter + AI DevTools';

const _kCanonicalArgs = [
  '--vm-service-port=8181',
  '--host-vmservice-port=8181',
  '--disable-service-auth-codes',
];

/// Returns a launch.json map containing the canonical AI DevTools debug
/// configuration, merged into [existingJson] (current file contents, or null).
/// Other user configurations are preserved untouched; the entry we manage
/// (matched by name) is refreshed to the canonical args every run — idempotent,
/// and keeps upgraders' args current.
///
/// Throws [FormatException] if [existingJson] is non-empty but not a JSON
/// object (e.g. it contains JSONC `//` comments). Callers should preserve the
/// user's file in that case rather than discard it.
Map<String, dynamic> mergeLaunchConfig(String? existingJson) {
  Map<String, dynamic> doc;
  if (existingJson == null || existingJson.trim().isEmpty) {
    doc = {'version': '0.2.0', 'configurations': <dynamic>[]};
  } else {
    final decoded = jsonDecode(existingJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('launch.json is not a JSON object');
    }
    doc = decoded;
    doc['version'] ??= '0.2.0';
  }
  final raw = doc['configurations'];
  final configs = (raw is List ? raw : <dynamic>[]).cast<dynamic>()
    ..removeWhere((c) => c is Map && c['name'] == _kConfigName)
    ..add({
      'name': _kConfigName,
      'request': 'launch',
      'type': 'dart',
      'args': List<String>.from(_kCanonicalArgs),
    });
  doc['configurations'] = configs;
  return doc;
}

/// Merges the flutter_ai_devtools stdio server entry into [existingJson]
/// (current .mcp.json contents, or null), preserving any other configured MCP
/// servers. Throws [FormatException] if [existingJson] is non-empty but not a
/// JSON object.
String mergeMcpJson(String? existingJson) {
  Map<String, dynamic> doc;
  if (existingJson == null || existingJson.trim().isEmpty) {
    doc = {'mcpServers': <String, dynamic>{}};
  } else {
    final decoded = jsonDecode(existingJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('.mcp.json is not a JSON object');
    }
    doc = decoded;
  }
  final rawServers = doc['mcpServers'];
  final servers =
      (rawServers is Map) ? rawServers.cast<String, dynamic>() : <String, dynamic>{};
  servers['flutter_ai_devtools'] = {
    'type': 'stdio',
    'command': 'dart',
    'args': ['run', 'flutter_ai_devtools:devtools_mcp'],
  };
  doc['mcpServers'] = servers;
  return '${const JsonEncoder.withIndent('  ').convert(doc)}\n';
}

/// The fresh `.mcp.json` contents (no existing file) — thin wrapper over
/// [mergeMcpJson] for callers/tests that want the default document.
String mcpJsonContent() => mergeMcpJson(null);

/// Pretty-prints a launch.json document for writing to disk.
String renderLaunchJson(Map<String, dynamic> doc) =>
    '${const JsonEncoder.withIndent('  ').convert(doc)}\n';
