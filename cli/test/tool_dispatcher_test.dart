import 'package:test/test.dart';
import 'package:flutter_ai_devtools_mcp/src/tools/tool_dispatcher.dart';

void main() {
  group('ToolDispatcher', () {
    late ToolDispatcher dispatcher;

    setUp(() => dispatcher = ToolDispatcher());

    test('calls registered handler', () async {
      dispatcher.register('ping', (_) async => {'pong': true});
      final result = await dispatcher.dispatch('ping', {});
      expect(result['pong'], isTrue);
    });

    test('throws on unknown tool', () async {
      expect(
        () => dispatcher.dispatch('unknown', {}),
        throwsA(isA<ToolNotFoundException>()),
      );
    });

    test('passes arguments to handler', () async {
      dispatcher.register('echo', (args) async => {'got': args['value']});
      final result = await dispatcher.dispatch('echo', {'value': 42});
      expect(result['got'], equals(42));
    });

    test('lists registered tool names', () {
      dispatcher.register('a', (_) async => {});
      dispatcher.register('b', (_) async => {});
      expect(dispatcher.toolNames, containsAll(['a', 'b']));
    });
  });
}
