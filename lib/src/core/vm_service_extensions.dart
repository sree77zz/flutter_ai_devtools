import 'dart:convert';
import 'dart:developer';

import '../core/runtime_store.dart';
import '../core/tool_registry.dart';
import '../logging/analyst_logger.dart';

/// Registers flutter_ai_devtools tools as VM Service extensions.
///
/// Each MCP tool becomes callable via:
///   ext.flutter_ai_devtools.<toolName>
///
/// The companion CLI (bin/devtools_mcp.dart) calls these extensions
/// via the VM Service protocol and serves them as MCP tools to Claude Code.
class VmServiceExtensions {
  VmServiceExtensions({
    required ToolRegistry toolRegistry,
    required RuntimeStore store,
  })  : _toolRegistry = toolRegistry,
        _store = store;

  final ToolRegistry _toolRegistry;
  final RuntimeStore _store;
  final _log = AnalystLogger.forName('VmServiceExtensions');

  void registerAll() {
    for (final tool in _toolRegistry.all) {
      _register(tool.name);
    }
    // Also register a meta endpoint listing all tools.
    registerExtension('ext.flutter_ai_devtools.list_tools', (_, __) async {
      final tools = _toolRegistry.all.map((t) => {
            'name': t.name,
            'description': t.description,
            'inputSchema': t.inputSchema,
          }).toList();
      return ServiceExtensionResponse.result(
        jsonEncode({'tools': tools}),
      );
    });
    _log.info('Registered ${_toolRegistry.all.length + 1} VM service extensions');
  }

  void _register(String toolName) {
    final extName = 'ext.flutter_ai_devtools.$toolName';
    registerExtension(extName, (method, params) async {
      try {
        final tool = _toolRegistry.find(toolName);
        if (tool == null) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError,
            'Tool not found: $toolName',
          );
        }
        final args = params.map(
          (k, v) => MapEntry(k, _parseValue(v)),
        );
        final result = await tool.execute(args, _store);
        return ServiceExtensionResponse.result(jsonEncode(result.toJson()));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          e.toString(),
        );
      }
    });
  }

  /// Attempts to parse JSON-encoded strings back to their native type.
  dynamic _parseValue(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }
}