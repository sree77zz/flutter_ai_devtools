class CollectorConfig {
  const CollectorConfig({
    this.widgets = true,
    this.frames = true,
    this.errors = true,
    this.routes = true,
    this.renders = true,
    this.lifecycle = true,
    this.maxErrors = 100,
    this.maxFrames = 300,
    this.maxRenderIssues = 200,
    this.maxIssues = 200,
    this.recurrenceThreshold = 5,
    this.widgetSnapshotMaxDepth = 20,
    this.widgetSnapshotMaxNodes = 500,
  });

  final bool widgets;
  final bool frames;
  final bool errors;
  final bool routes;
  final bool renders;
  final bool lifecycle;
  final int maxErrors;
  final int maxFrames;
  final int maxRenderIssues;
  final int maxIssues;
  final int recurrenceThreshold;
  final int widgetSnapshotMaxDepth;
  final int widgetSnapshotMaxNodes;
}

class FlutterAiDevtoolsException implements Exception {
  const FlutterAiDevtoolsException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'FlutterAiDevtoolsException: $message'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}
