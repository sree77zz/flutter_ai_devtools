import '../logging/analyst_logger.dart';
import '../tools/base_tool.dart';

/// Registry that maps MCP tool names to [AnalystTool] implementations.
///
/// The MCP server queries this registry when a tool call arrives, keeping
/// the transport layer ignorant of specific tool logic.
class ToolRegistry {
  ToolRegistry();

  final _tools = <String, AnalystTool>{};
  final _log = AnalystLogger.forName('ToolRegistry');

  void register(AnalystTool tool) {
    if (_tools.containsKey(tool.name)) {
      _log.warning('Overwriting tool registration: ${tool.name}');
    }
    _tools[tool.name] = tool;
    _log.info('Registered tool: ${tool.name}');
  }

  void unregister(String name) {
    if (_tools.remove(name) != null) {
      _log.info('Unregistered tool: $name');
    }
  }

  AnalystTool? find(String name) => _tools[name];

  List<AnalystTool> get all => List.unmodifiable(_tools.values);

  bool contains(String name) => _tools.containsKey(name);
}
