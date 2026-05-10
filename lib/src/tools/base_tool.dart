import '../core/runtime_store.dart';
import '../logging/analyst_logger.dart';

/// Result returned by every [AnalystTool.execute] call.
class ToolResult {
  const ToolResult({
    required this.content,
    this.isError = false,
    this.errorMessage,
  });

  const ToolResult.success(Map<String, dynamic> data)
      : content = data,
        isError = false,
        errorMessage = null;

  const ToolResult.error(String message)
      : content = const {},
        isError = true,
        errorMessage = message;

  final Map<String, dynamic> content;
  final bool isError;
  final String? errorMessage;

  Map<String, dynamic> toJson() => isError
      ? {'error': errorMessage ?? 'Unknown tool error'}
      : content;
}

/// Contract for all MCP-exposed tools.
abstract class AnalystTool {
  /// MCP tool name (snake_case), e.g. `get_widget_tree`.
  String get name;

  /// Short description shown to AI clients in the tool manifest.
  String get description;

  /// JSON Schema for the tool's input parameters.
  Map<String, dynamic> get inputSchema;

  /// Execute the tool with the given [arguments] and return a [ToolResult].
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    RuntimeStore store,
  );

  late final AnalystLogger log = AnalystLogger.forName('tool:$name');
}
