import 'package:meta/meta.dart';

/// Lightweight, serializable representation of a widget in the tree.
@immutable
class WidgetNode {
  const WidgetNode({
    required this.id,
    required this.type,
    required this.depth,
    this.key,
    this.bounds,
    this.properties = const {},
    this.children = const [],
    this.rebuildCount = 0,
  });

  final String id;
  final String type;
  final int depth;
  final String? key;
  final WidgetBounds? bounds;
  final Map<String, String> properties;
  final List<WidgetNode> children;
  final int rebuildCount;

  factory WidgetNode.fromJson(Map<String, dynamic> json) => WidgetNode(
        id: json['id'] as String,
        type: json['type'] as String,
        depth: json['depth'] as int,
        key: json['key'] as String?,
        bounds: json['bounds'] == null
            ? null
            : WidgetBounds.fromJson(
                Map<String, dynamic>.from(json['bounds'] as Map)),
        properties: Map<String, String>.from(json['properties'] as Map? ?? {}),
        children: (json['children'] as List? ?? [])
            .map((c) => WidgetNode.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList(),
        rebuildCount: json['rebuildCount'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'depth': depth,
        if (key != null) 'key': key,
        if (bounds != null) 'bounds': bounds!.toJson(),
        'properties': properties,
        'children': children.map((c) => c.toJson()).toList(),
        'rebuildCount': rebuildCount,
      };

  int get totalNodes => 1 + children.fold(0, (s, c) => s + c.totalNodes);
  int get maxDepth =>
      children.isEmpty ? depth : children.map((c) => c.maxDepth).reduce((a, b) => a > b ? a : b);
}

@immutable
class WidgetBounds {
  const WidgetBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x, y, width, height;

  factory WidgetBounds.fromJson(Map<String, dynamic> json) => WidgetBounds(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() =>
      {'x': x, 'y': y, 'width': width, 'height': height};
}

/// Full immutable snapshot of the widget tree at a point in time.
@immutable
class WidgetTreeSnapshot {
  const WidgetTreeSnapshot({
    required this.capturedAt,
    required this.root,
    required this.totalNodes,
    required this.maxDepth,
  });

  final DateTime capturedAt;
  final WidgetNode? root;
  final int totalNodes;
  final int maxDepth;

  Map<String, dynamic> toJson() => {
        'capturedAt': capturedAt.toIso8601String(),
        'root': root?.toJson(),
        'totalNodes': totalNodes,
        'maxDepth': maxDepth,
      };
}
