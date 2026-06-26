import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_devtools/flutter_ai_devtools.dart';

void main() {
  group('RuntimeStore', () {
    late RuntimeStore store;

    setUp(() {
      store = RuntimeStore(maxErrors: 3, maxFrames: 5, maxRenderIssues: 10);
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

    test('currentRoute returns null initially', () {
      expect(store.currentRoute, isNull);
    });

    test('frameSummary returns zeros when empty', () {
      expect(store.frameSummary.fps, equals(0));
      expect(store.frameSummary.jankyFrames, equals(0));
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
      final frames = List.generate(
          10,
          (i) => FrameStats(
                frameNumber: i,
                buildDurationMicros: i < 5 ? 20000 : 5000,
                rasterDurationMicros: 1000,
                vsyncOverheadMicros: 0,
                capturedAt: DateTime.now(),
              ));
      final summary = FrameSummary.fromFrames(frames);
      expect(summary.jankyFrames, equals(5));
      expect(summary.jankyPercent, equals(50.0));
    });
  });

  group('CollectorConfig', () {
    test('defaults all collectors on', () {
      const cfg = CollectorConfig();
      expect(cfg.widgets, isTrue);
      expect(cfg.frames, isTrue);
      expect(cfg.errors, isTrue);
      expect(cfg.routes, isTrue);
      expect(cfg.renders, isTrue);
    });

    test('respects custom buffer sizes', () {
      const cfg = CollectorConfig(maxErrors: 5, maxFrames: 10);
      expect(cfg.maxErrors, equals(5));
      expect(cfg.maxFrames, equals(10));
    });
  });

  group('FlutterAiDevtoolsException', () {
    test('toString includes message', () {
      const e = FlutterAiDevtoolsException('test error');
      expect(e.toString(), contains('test error'));
    });

    test('toString includes cause when present', () {
      const e = FlutterAiDevtoolsException('test', cause: 'root cause');
      expect(e.toString(), contains('root cause'));
    });
  });
}
