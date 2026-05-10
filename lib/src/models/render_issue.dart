import 'package:meta/meta.dart';

enum RenderIssueKind {
  overflow,
  unboundedConstraints,
  intrinsicMeasurement,
  largeRepaintBoundary,
  offscreenLayer,
  debugPaintSize,
}

@immutable
class RenderIssue {
  const RenderIssue({
    required this.id,
    required this.kind,
    required this.description,
    required this.widgetType,
    required this.capturedAt,
    this.location,
    this.severity = RenderIssueSeverity.warning,
  });

  final String id;
  final RenderIssueKind kind;
  final String description;
  final String widgetType;
  final DateTime capturedAt;
  final String? location;
  final RenderIssueSeverity severity;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'description': description,
        'widgetType': widgetType,
        'capturedAt': capturedAt.toIso8601String(),
        if (location != null) 'location': location,
        'severity': severity.name,
      };
}

enum RenderIssueSeverity { info, warning, error }
