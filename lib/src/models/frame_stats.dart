import 'package:meta/meta.dart';

@immutable
class FrameStats {
  const FrameStats({
    required this.frameNumber,
    required this.buildDurationMicros,
    required this.rasterDurationMicros,
    required this.vsyncOverheadMicros,
    required this.capturedAt,
  });

  final int frameNumber;
  final int buildDurationMicros;
  final int rasterDurationMicros;
  final int vsyncOverheadMicros;
  final DateTime capturedAt;

  /// 16666µs = 60 fps threshold.
  static const int _jankyThresholdMicros = 16666;

  bool get isJanky =>
      buildDurationMicros + rasterDurationMicros > _jankyThresholdMicros;

  double get totalDurationMs =>
      (buildDurationMicros + rasterDurationMicros) / 1000.0;

  Map<String, dynamic> toJson() => {
        'frameNumber': frameNumber,
        'buildDurationMicros': buildDurationMicros,
        'rasterDurationMicros': rasterDurationMicros,
        'vsyncOverheadMicros': vsyncOverheadMicros,
        'totalDurationMs': totalDurationMs,
        'isJanky': isJanky,
        'capturedAt': capturedAt.toIso8601String(),
      };
}

/// Rolling window summary of frame performance.
class FrameSummary {
  FrameSummary({
    required this.sampleCount,
    required this.jankyFrames,
    required this.averageBuildMs,
    required this.averageRasterMs,
    required this.fps,
    required this.p99BuildMs,
    required this.worstFrameMs,
  });

  final int sampleCount;
  final int jankyFrames;
  final double averageBuildMs;
  final double averageRasterMs;
  final double fps;
  final double p99BuildMs;
  final double worstFrameMs;

  double get jankyPercent =>
      sampleCount == 0 ? 0 : (jankyFrames / sampleCount) * 100;

  Map<String, dynamic> toJson() => {
        'sampleCount': sampleCount,
        'jankyFrames': jankyFrames,
        'jankyPercent': jankyPercent.toStringAsFixed(1),
        'averageBuildMs': averageBuildMs,
        'averageRasterMs': averageRasterMs,
        'fps': fps,
        'p99BuildMs': p99BuildMs,
        'worstFrameMs': worstFrameMs,
      };

  static FrameSummary fromFrames(List<FrameStats> frames) {
    if (frames.isEmpty) {
      return FrameSummary(
        sampleCount: 0,
        jankyFrames: 0,
        averageBuildMs: 0,
        averageRasterMs: 0,
        fps: 0,
        p99BuildMs: 0,
        worstFrameMs: 0,
      );
    }
    final builds = frames.map((f) => f.buildDurationMicros / 1000.0).toList()
      ..sort();
    final rasters = frames.map((f) => f.rasterDurationMicros / 1000.0).toList();
    final avgBuild = builds.reduce((a, b) => a + b) / builds.length;
    final avgRaster = rasters.reduce((a, b) => a + b) / rasters.length;
    final janky = frames.where((f) => f.isJanky).length;
    final p99Index =
        ((builds.length * 0.99) - 1).round().clamp(0, builds.length - 1);
    final totalMs = frames.fold<double>(0, (s, f) => s + f.totalDurationMs);
    final fps = totalMs > 0 ? (frames.length / (totalMs / 1000)) : 0.0;
    return FrameSummary(
      sampleCount: frames.length,
      jankyFrames: janky,
      averageBuildMs: avgBuild,
      averageRasterMs: avgRaster,
      fps: fps,
      p99BuildMs: builds[p99Index],
      worstFrameMs: builds.last,
    );
  }
}
