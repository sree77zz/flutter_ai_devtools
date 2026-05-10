import '../core/runtime_store.dart';
import '../models/frame_stats.dart';
import 'base_tool.dart';

/// MCP tool: `get_frame_stats`
///
/// Returns a rolling-window summary of frame timing and FPS.
class GetFrameStatsTool extends AnalystTool {
  @override
  String get name => 'get_frame_stats';

  @override
  String get description =>
      'Returns frame timing statistics: average build/raster duration, FPS, '
      'jank percentage, and worst frame. Based on a rolling window of recent '
      'frames.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'windowSize': {
            'type': 'integer',
            'description':
                'Number of recent frames to include in the summary. '
                'Defaults to all available frames.',
          },
          'includeRawFrames': {
            'type': 'boolean',
            'description':
                'If true, include the raw per-frame data in addition to '
                'the summary.',
            'default': false,
          },
          'rawLimit': {
            'type': 'integer',
            'description': 'Maximum raw frames to return when includeRawFrames is true.',
            'default': 60,
          },
        },
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    RuntimeStore store,
  ) async {
    final windowSize = arguments['windowSize'] as int?;
    final includeRaw = arguments['includeRawFrames'] as bool? ?? false;
    final rawLimit = arguments['rawLimit'] as int? ?? 60;

    var frames = store.recentFrames;
    if (windowSize != null && windowSize < frames.length) {
      frames = frames.sublist(frames.length - windowSize);
    }

    final summary = FrameSummary.fromFrames(frames);

    final result = <String, dynamic>{
      'frameCount': frames.length,
      'summary': summary.toJson(),
    };

    if (includeRaw) {
      result['frames'] = frames.reversed
          .take(rawLimit)
          .map((f) => f.toJson())
          .toList();
    }

    return ToolResult.success(result);
  }
}
