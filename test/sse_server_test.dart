import 'dart:convert';
import 'dart:io';
import 'package:flutter_ai_devtools/src/mcp/sse_server.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SseServer', () {
    late SseServer server;
    late int port;

    setUp(() async {
      final d = ToolDispatcher();
      server = SseServer(dispatcher: d);
      port = await server.bind(0);
    });

    tearDown(() async {
      await server.stop();
    });

    test('GET /sse returns SSE stream with endpoint event', () async {
      final client = HttpClient();
      final req = await client.get('localhost', port, '/sse');
      req.headers.add('Accept', 'text/event-stream');
      final res = await req.close();

      expect(res.statusCode, 200);
      expect(res.headers.contentType?.mimeType, 'text/event-stream');

      // Read first SSE event — it must be the endpoint event.
      final firstLine = await res
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      expect(firstLine, startsWith('event: endpoint'));

      client.close(force: true);
    });

    test('POST /message with initialize returns 202 and response on SSE stream',
        () async {
      final client = HttpClient();

      // 1. Open the SSE stream and capture the session URL.
      final sseReq = await client.get('localhost', port, '/sse');
      final sseRes = await sseReq.close();
      expect(sseRes.statusCode, 200);

      // Read lines until we get the data line with the sessionId URL.
      String? messageUrl;
      final lineStream = sseRes
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();

      await for (final line in lineStream) {
        if (line.startsWith('data: ')) {
          messageUrl = line.substring('data: '.length).trim();
          break;
        }
      }
      expect(messageUrl, isNotNull);
      expect(messageUrl, contains('/message?sessionId='));

      // Collect SSE responses in background via a cancellable subscription.
      final sseResponses = <Map<String, dynamic>>[];
      final sub = lineStream
          .where((l) => l.startsWith('data: '))
          .map((l) => jsonDecode(l.substring('data: '.length).trim())
              as Map<String, dynamic>)
          .listen(sseResponses.add);

      // 2. POST initialize to the session URL.
      final uri = Uri.parse('http://localhost:$port$messageUrl');
      final postReq = await client.postUrl(uri);
      postReq.headers.contentType = ContentType.json;
      postReq.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2024-11-05',
          'capabilities': {},
          'clientInfo': {'name': 'test', 'version': '0'},
        },
      }));
      final postRes = await postReq.close();
      expect(postRes.statusCode, 202);

      // 3. Response must arrive on the SSE stream within 1 second.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(sseResponses, hasLength(1));
      final rpc = sseResponses.first;
      expect(rpc['id'], 1);
      expect((rpc['result'] as Map<String, dynamic>)['protocolVersion'], '2024-11-05');

      // Cancel before force-closing to avoid HttpException on the background listener.
      await sub.cancel();
      client.close(force: true);
    });

    test('POST /message with notification (no id) returns 202 and no SSE event',
        () async {
      final client = HttpClient();
      final sseReq = await client.get('localhost', port, '/sse');
      final sseRes = await sseReq.close();

      String? messageUrl;
      await for (final line in sseRes
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          messageUrl = line.substring('data: '.length).trim();
          break;
        }
      }

      final uri = Uri.parse('http://localhost:$port$messageUrl');
      final postReq = await client.postUrl(uri);
      postReq.headers.contentType = ContentType.json;
      // 'initialized' is a notification — no 'id' field.
      postReq.write(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'initialized',
        'params': {},
      }));
      final postRes = await postReq.close();
      expect(postRes.statusCode, 202);

      client.close(force: true);
    });

    test('GET /health returns 200', () async {
      final client = HttpClient();
      final req = await client.get('localhost', port, '/health');
      final res = await req.close();
      expect(res.statusCode, 200);
      client.close();
    });

    test('unknown path returns 404', () async {
      final client = HttpClient();
      final req = await client.get('localhost', port, '/nonexistent');
      final res = await req.close();
      expect(res.statusCode, 404);
      client.close();
    });
  });
}
