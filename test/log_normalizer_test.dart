import 'dart:convert';
import 'package:flutter_ai_devtools/src/bridge/log_normalizer.dart';
import 'package:flutter_ai_devtools/src/models/log_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart' as vm;

void main() {
  group('normalizeVmEvent', () {
    test('decodes a stdout WriteEvent', () {
      final e = vm.Event(
        kind: vm.EventKind.kWriteEvent,
        bytes: base64.encode(utf8.encode('hello world\n')),
      );
      final entry = normalizeVmEvent(e, source: LogSource.stdout);
      expect(entry, isNotNull);
      expect(entry!.message, 'hello world');
      expect(entry.source, LogSource.stdout);
      expect(entry.level, LogLevel.info);
    });

    test('marks stderr WriteEvent as error level', () {
      final e = vm.Event(
        kind: vm.EventKind.kWriteEvent,
        bytes: base64.encode(utf8.encode('boom')),
      );
      final entry = normalizeVmEvent(e, source: LogSource.stderr);
      expect(entry!.level, LogLevel.error);
      expect(entry.source, LogSource.stderr);
    });

    test('returns null for empty/whitespace write', () {
      final e = vm.Event(
        kind: vm.EventKind.kWriteEvent,
        bytes: base64.encode(utf8.encode('   \n')),
      );
      expect(normalizeVmEvent(e, source: LogSource.stdout), isNull);
    });

    test('maps a Logging record with level + logger name', () {
      final e = vm.Event(
        kind: vm.EventKind.kLogging,
        logRecord: vm.LogRecord(
          level: 900, // SEVERE
          message: vm.InstanceRef(
            id: '',
            kind: 'String',
            valueAsString: 'db failed',
          ),
          loggerName: vm.InstanceRef(
            id: '',
            kind: 'String',
            valueAsString: 'AuthRepo',
          ),
        ),
      );
      final entry = normalizeVmEvent(e, source: LogSource.developerLog);
      expect(entry!.message, 'db failed');
      expect(entry.loggerName, 'AuthRepo');
      expect(entry.level, LogLevel.error);
      expect(entry.source, LogSource.developerLog);
    });

    test('returns null for unrelated event kinds', () {
      final e = vm.Event(kind: vm.EventKind.kGC);
      expect(normalizeVmEvent(e, source: LogSource.stdout), isNull);
    });
  });
}
