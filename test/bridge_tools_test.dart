import 'package:flutter_ai_devtools/src/bridge/live_buffer.dart';
import 'package:flutter_ai_devtools/src/bridge/vm_bridge.dart';
import 'package:flutter_ai_devtools/src/models/log_entry.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_definitions.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bridge tools', () {
    late LiveBuffer buffer;
    late VmBridge bridge;
    late ToolDispatcher d;

    setUp(() {
      buffer = LiveBuffer();
      // connector that never connects keeps the bridge offline for the test.
      bridge = VmBridge(liveBuffer: buffer, connector: (_) async => null);
      d = ToolDispatcher();
      registerBridgeTools(d, bridge);
    });

    tearDown(() => bridge.dispose());

    test('get_logs returns tail entries and nextSeq', () async {
      buffer.addLog(LogEntry(
        seq: 0,
        timestamp: DateTime(2026),
        level: LogLevel.info,
        source: LogSource.stdout,
        message: 'first',
      ));
      buffer.addLog(LogEntry(
        seq: 0,
        timestamp: DateTime(2026),
        level: LogLevel.error,
        source: LogSource.stderr,
        message: 'second',
      ));

      final res = await d.dispatch('get_logs', {'sinceSeq': 0});
      final logs = res['logs'] as List;
      expect(logs, hasLength(2));
      expect((logs.first as Map)['message'], 'first');
      expect(res['nextSeq'], 2);
    });

    test('get_logs honors sinceSeq cursor and level filter', () async {
      buffer.addLog(LogEntry(
          seq: 0, timestamp: DateTime(2026), level: LogLevel.info,
          source: LogSource.stdout, message: 'a'));
      buffer.addLog(LogEntry(
          seq: 0, timestamp: DateTime(2026), level: LogLevel.error,
          source: LogSource.stderr, message: 'b'));

      final res = await d.dispatch('get_logs', {'sinceSeq': 1, 'level': 'error'});
      final logs = res['logs'] as List;
      expect(logs, hasLength(1));
      expect((logs.first as Map)['message'], 'b');
    });

    test('get_connection_status reports disconnected when offline', () async {
      final res = await d.dispatch('get_connection_status', {});
      expect(res['connected'], isFalse);
    });

    test('hot_reload returns actionable error when offline', () async {
      final res = await d.dispatch('hot_reload', {});
      expect(res['error'], contains('not connected'));
    });

    test('get_memory_info returns actionable error when offline', () async {
      final res = await d.dispatch('get_memory_info', {});
      expect(res['error'], contains('not connected'));
    });
  });
}
