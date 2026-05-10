import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_analyst/flutter_ai_analyst.dart';

void main() {
  group('DataNormalizer', () {
    late DataNormalizer normalizer;

    setUp(() => normalizer = DataNormalizer(maxPayloadStringLength: 20));

    test('truncates long strings', () {
      final event = RuntimeEvent(
        id: 'test-1',
        type: RuntimeEventType.flutterError,
        timestamp: DateTime.now(),
        source: 'test',
        payload: {'msg': 'A' * 100},
      );
      final normalized = normalizer.normalize(event);
      expect(
        (normalized.payload['msg'] as String).length,
        lessThanOrEqualTo(30),
      );
      expect(normalized.payload['msg'], contains('[truncated]'));
    });

    test('strips null values', () {
      // DataNormalizer skips null values.
      final event = RuntimeEvent(
        id: 'test-2',
        type: RuntimeEventType.widgetRebuilt,
        timestamp: DateTime.now(),
        source: 'test',
        payload: {'a': 'hello', 'b': null},
      );
      final normalized = normalizer.normalize(event);
      expect(normalized.payload.containsKey('b'), isFalse);
    });
  });

  group('RuntimeStore', () {
    late RuntimeStore store;
    late ConfigManager config;

    setUp(() {
      config = ConfigManager(const AnalystConfig(
        errorHistorySize: 3,
        frameWindowSize: 5,
      ));
      store = RuntimeStore(config);
    });

    test('bounds error history', () {
      for (var i = 0; i < 10; i++) {
        store.addError(ErrorReport(
          id: 'err-$i',
          capturedAt: DateTime.now(),
          category: ErrorCategory.flutter,
          message: 'Error $i',
        ));
      }
      expect(store.recentErrors.length, equals(3));
    });

    test('bounds frame history', () {
      for (var i = 0; i < 20; i++) {
        store.addFrame(FrameStats(
          frameNumber: i,
          buildDurationMicros: 8000,
          rasterDurationMicros: 4000,
          vsyncOverheadMicros: 100,
          capturedAt: DateTime.now(),
        ));
      }
      expect(store.recentFrames.length, equals(5));
    });

    test('deduplicates errors by id', () {
      final report = ErrorReport(
        id: 'dup-id',
        capturedAt: DateTime.now(),
        category: ErrorCategory.platform,
        message: 'Dup error',
      );
      store.addError(report);
      store.addError(report);
      store.addError(report);
      expect(store.recentErrors.length, equals(1));
      expect(store.recentErrors.first.occurrenceCount, equals(3));
    });

    test('increments rebuild counts', () {
      store.incrementRebuild('Text');
      store.incrementRebuild('Text');
      store.incrementRebuild('Container');
      expect(store.widgetRebuildCounts['Text'], equals(2));
      expect(store.widgetRebuildCounts['Container'], equals(1));
    });
  });

  group('FrameStats', () {
    test('isJanky when total > 16666µs', () {
      final janky = FrameStats(
        frameNumber: 1,
        buildDurationMicros: 12000,
        rasterDurationMicros: 6000,
        vsyncOverheadMicros: 0,
        capturedAt: DateTime.now(),
      );
      expect(janky.isJanky, isTrue);
    });

    test('not janky within budget', () {
      final smooth = FrameStats(
        frameNumber: 2,
        buildDurationMicros: 5000,
        rasterDurationMicros: 4000,
        vsyncOverheadMicros: 0,
        capturedAt: DateTime.now(),
      );
      expect(smooth.isJanky, isFalse);
    });
  });

  group('FrameSummary', () {
    test('empty frames returns zeros', () {
      final s = FrameSummary.fromFrames([]);
      expect(s.fps, equals(0));
      expect(s.jankyFrames, equals(0));
    });

    test('calculates janky percent correctly', () {
      final frames = List.generate(10, (i) {
        return FrameStats(
          frameNumber: i,
          buildDurationMicros: i < 5 ? 20000 : 5000,
          rasterDurationMicros: 1000,
          vsyncOverheadMicros: 0,
          capturedAt: DateTime.now(),
        );
      });
      final summary = FrameSummary.fromFrames(frames);
      expect(summary.jankyFrames, equals(5));
      expect(summary.jankyPercent, equals(50.0));
    });
  });

  group('EventBus', () {
    late EventBus bus;

    setUp(() => bus = EventBus());
    tearDown(() => bus.dispose());

    test('broadcasts events to subscribers', () async {
      final events = <RuntimeEvent>[];
      bus.events.listen(events.add);

      final event = RuntimeEvent(
        id: 'ev-1',
        type: RuntimeEventType.navigationPush,
        timestamp: DateTime.now(),
        source: 'test',
        payload: {'route': '/home'},
      );
      bus.publish(event);

      await Future<void>.delayed(Duration.zero);
      expect(events.length, equals(1));
      expect(events.first.id, equals('ev-1'));
    });

    test('on() filters by type', () async {
      final filtered = <RuntimeEvent>[];
      bus.on(RuntimeEventType.flutterError).listen(filtered.add);

      bus.publish(RuntimeEvent(
        id: 'e1',
        type: RuntimeEventType.navigationPush,
        timestamp: DateTime.now(),
        source: 's',
        payload: {},
      ));
      bus.publish(RuntimeEvent(
        id: 'e2',
        type: RuntimeEventType.flutterError,
        timestamp: DateTime.now(),
        source: 's',
        payload: {},
      ));

      await Future<void>.delayed(Duration.zero);
      expect(filtered.length, equals(1));
      expect(filtered.first.id, equals('e2'));
    });
  });

  group('ToolRegistry', () {
    test('registers and finds tools', () {
      final registry = ToolRegistry();
      final tool = GetWidgetTreeTool();
      registry.register(tool);
      expect(registry.find('get_widget_tree'), isNotNull);
      expect(registry.contains('get_widget_tree'), isTrue);
    });

    test('returns null for unknown tool', () {
      final registry = ToolRegistry();
      expect(registry.find('no_such_tool'), isNull);
    });
  });

  group('SecurityMiddleware', () {
    test('permissive when no tokens configured', () {
      final mw = SecurityMiddleware([]);
      expect(mw.authorize(null), isTrue);
      expect(mw.authorize('anything'), isTrue);
    });

    test('rejects missing token when tokens configured', () {
      final mw = SecurityMiddleware(['secret']);
      expect(mw.authorize(null), isFalse);
    });

    test('accepts valid bearer token', () {
      final mw = SecurityMiddleware(['my-secret']);
      expect(mw.authorize('Bearer my-secret'), isTrue);
    });

    test('rejects invalid token', () {
      final mw = SecurityMiddleware(['my-secret']);
      expect(mw.authorize('Bearer wrong'), isFalse);
    });
  });

  group('RuntimeEvent', () {
    test('serializes and deserializes', () {
      final event = RuntimeEvent(
        id: 'abc',
        type: RuntimeEventType.widgetRebuilt,
        timestamp: DateTime(2025, 1, 1),
        source: 'widget_collector',
        payload: {'widgetType': 'Text', 'totalRebuilds': 5},
        severity: EventSeverity.info,
        tags: {'widget'},
      );
      final json = event.toJson();
      final restored = RuntimeEvent.fromJson(json);
      expect(restored.id, equals(event.id));
      expect(restored.type, equals(event.type));
      expect(restored.source, equals(event.source));
      expect(restored.severity, equals(event.severity));
    });
  });
}
