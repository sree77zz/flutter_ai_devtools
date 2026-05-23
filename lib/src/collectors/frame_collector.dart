// lib/src/collectors/frame_collector.dart
import 'package:flutter/scheduler.dart';
import '../models/frame_stats.dart';
import 'base_collector.dart';

class FrameCollector extends BaseCollector {
  FrameCollector({required super.store, required super.config});

  int _frameNumber = 0;

  @override
  String get id => 'frame_collector';

  @override
  Future<void> onStart() async {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  Future<void> onStop() async {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      store.addFrame(FrameStats(
        frameNumber: _frameNumber++,
        buildDurationMicros: t.buildDuration.inMicroseconds,
        rasterDurationMicros: t.rasterDuration.inMicroseconds,
        vsyncOverheadMicros: t.vsyncOverhead.inMicroseconds,
        capturedAt: DateTime.now(),
      ));
    }
  }
}
