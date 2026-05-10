import 'package:flutter/scheduler.dart';
import 'package:uuid/uuid.dart';

import '../core/runtime_store.dart';
import '../models/frame_stats.dart';
import '../models/runtime_event.dart';
import 'base_collector.dart';

/// Tracks per-frame build and rasterization timing using [SchedulerBinding].
///
/// Flutter exposes [SchedulerBinding.addTimingsCallback] which fires after
/// each frame with microsecond-accurate build and raster durations. This
/// collector feeds that data directly into [RuntimeStore].
class FrameCollector extends BaseCollector {
  FrameCollector({
    required super.eventBus,
    required super.config,
    required RuntimeStore store,
  }) : _store = store;

  final RuntimeStore _store;
  final _uuid = const Uuid();
  int _frameCounter = 0;

  @override
  String get id => 'frame_collector';

  @override
  Future<void> onStart() async {
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  @override
  Future<void> onStop() async {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frameCounter++;
      final stats = FrameStats(
        frameNumber: _frameCounter,
        buildDurationMicros: timing.buildDuration.inMicroseconds,
        rasterDurationMicros: timing.rasterDuration.inMicroseconds,
        vsyncOverheadMicros: timing.vsyncOverhead.inMicroseconds,
        capturedAt: DateTime.now(),
      );
      _store.addFrame(stats);

      final isJanky = stats.isJanky;
      eventBus.publish(RuntimeEvent(
        id: _uuid.v4(),
        type: isJanky ? RuntimeEventType.frameJanked : RuntimeEventType.frameRendered,
        timestamp: stats.capturedAt,
        source: id,
        severity: isJanky ? EventSeverity.warning : EventSeverity.debug,
        payload: stats.toJson(),
      ));
    }
  }
}
