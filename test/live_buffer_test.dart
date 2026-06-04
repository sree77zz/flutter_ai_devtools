import 'package:flutter_ai_devtools/src/bridge/live_buffer.dart';
import 'package:flutter_ai_devtools/src/models/log_entry.dart';
import 'package:flutter_test/flutter_test.dart';

LogEntry draft(String msg, {LogLevel level = LogLevel.info}) => LogEntry(
      seq: 0,
      timestamp: DateTime(2026),
      level: level,
      source: LogSource.stdout,
      message: msg,
    );

void main() {
  group('LiveBuffer', () {
    test('assigns monotonic seq and advances nextSeq', () {
      final buf = LiveBuffer();
      final a = buf.addLog(draft('a'));
      final b = buf.addLog(draft('b'));
      expect(a.seq, 0);
      expect(b.seq, 1);
      expect(buf.nextSeq, 2);
    });

    test('logsSince returns only entries at/after the cursor', () {
      final buf = LiveBuffer();
      buf.addLog(draft('a')); // seq 0
      buf.addLog(draft('b')); // seq 1
      buf.addLog(draft('c')); // seq 2
      final tail = buf.logsSince(1);
      expect(tail.map((e) => e.message), ['b', 'c']);
    });

    test('evicts oldest beyond maxLogs but keeps seq monotonic', () {
      final buf = LiveBuffer(maxLogs: 2);
      buf.addLog(draft('a')); // seq 0 (evicted)
      buf.addLog(draft('b')); // seq 1
      buf.addLog(draft('c')); // seq 2
      final all = buf.logsSince(0);
      expect(all.map((e) => e.seq), [1, 2]);
    });

    test('filters by minLevel and grep', () {
      final buf = LiveBuffer();
      buf.addLog(draft('hello info'));
      buf.addLog(draft('BAD thing', level: LogLevel.error));
      buf.addLog(draft('other info'));
      expect(buf.logsSince(0, minLevel: LogLevel.warning).map((e) => e.message),
          ['BAD thing']);
      expect(buf.logsSince(0, grep: 'info').map((e) => e.message),
          ['hello info', 'other info']);
    });

    test('limit returns the most recent N', () {
      final buf = LiveBuffer();
      for (var i = 0; i < 5; i++) {
        buf.addLog(draft('m$i'));
      }
      final tail = buf.logsSince(0, limit: 2);
      expect(tail.map((e) => e.message), ['m3', 'm4']);
    });
  });
}
