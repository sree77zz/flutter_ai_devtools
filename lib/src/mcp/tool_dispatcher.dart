import 'dart:convert';

typedef ToolHandler = Future<Map<String, dynamic>> Function(Map<String, dynamic> args);

class ToolNotFoundException implements Exception {
  const ToolNotFoundException(this.toolName);
  final String toolName;
  @override
  String toString() => 'Tool not found: $toolName';
}

class ToolDispatcher {
  final _handlers = <String, ToolHandler>{};
  final _schemas = <String, Map<String, dynamic>>{};

  void register(
    String name,
    ToolHandler handler, {
    Map<String, dynamic> schema = const {'type': 'object', 'properties': {}},
    String description = '',
  }) {
    _handlers[name] = handler;
    _schemas[name] = {
      'name': name,
      'description': description,
      'inputSchema': schema,
    };
  }

  Future<Map<String, dynamic>> dispatch(String name, Map<String, dynamic> args) {
    final handler = _handlers[name];
    if (handler == null) throw ToolNotFoundException(name);
    return handler(args);
  }

  List<String> get toolNames => List.unmodifiable(_handlers.keys);
  List<Map<String, dynamic>> get toolManifests => List.unmodifiable(_schemas.values);

  static Map<String, dynamic> mcpResult(Map<String, dynamic> content) => {
    'content': [{'type': 'text', 'text': jsonEncode(content)}],
    'isError': false,
  };

  static Map<String, dynamic> mcpError(String message) => {
    'content': [{'type': 'text', 'text': message}],
    'isError': true,
  };
}
