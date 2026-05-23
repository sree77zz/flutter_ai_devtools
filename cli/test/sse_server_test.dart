import 'dart:convert';
import 'dart:io';
import 'package:flutter_ai_devtools/src/store/runtime_store.dart';
import 'package:flutter_ai_devtools_mcp/src/server/sse_server.dart';
import 'package:flutter_ai_devtools_mcp/src/tools/tool_dispatcher.dart';
import 'package:test/test.dart';

void main() {
  group('SseServer', () {
    late RuntimeStore store;
    late ToolDispatcher dispatcher;
    late SseServer server;
    late int port;

    setUp(() async {
      store = RuntimeStore();
      dispatcher = ToolDispatcher();
      dispatcher.register('ping', (_) async => {'pong': true});
      server = SseServer(dispatcher: dispatcher, store: store);
      port = await server.bind(0); // port 0 = OS assigns free port
    });

    tearDown(() => server.stop());

    test('bind() returns before any client connects', () {
      // If we get here, bind() completed — no race condition.
      expect(port, greaterThan(0));
    });

    test('POST / with tools/list returns tool manifests', () async {
      final client = HttpClient();
      final req = await client.post('localhost', port, '/');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/list',
        'params': {},
      }));
      final res = await req.close();
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      client.close();
      expect(res.statusCode, equals(200));
      expect((body['result'] as Map<String, dynamic>)['tools'], isA<List<dynamic>>());
    });

    test('POST / with tools/call dispatches to registered handler', () async {
      final client = HttpClient();
      final req = await client.post('localhost', port, '/');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': {'name': 'ping', 'arguments': {}},
      }));
      final res = await req.close();
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      client.close();
      expect(res.statusCode, equals(200));
      expect((body['result'] as Map<String, dynamic>)['isError'], isFalse);
    });
  });
}
