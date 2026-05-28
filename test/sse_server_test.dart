import 'dart:convert';
import 'dart:io';
import 'package:flutter_ai_devtools/src/mcp/sse_server.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SseServer accepts dispatcher-only constructor and handles tools/call', () async {
    final d = ToolDispatcher();
    d.register('ping', (_) async => {'pong': true});
    final server = SseServer(dispatcher: d);
    final port = await server.bind(0);
    expect(port, greaterThan(0));

    final client = HttpClient();
    final req = await client.post('localhost', port, '/');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({
      'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call',
      'params': {'name': 'ping', 'arguments': {}},
    }));
    final res = await req.close();
    expect(res.statusCode, 200);
    client.close();
    await server.stop();
  });
}
