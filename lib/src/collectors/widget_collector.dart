// lib/src/collectors/widget_collector.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../models/widget_snapshot.dart';
import 'base_collector.dart';

class WidgetCollector extends BaseCollector {
  WidgetCollector({required super.store, required super.config});

  Timer? _snapshotTimer;
  RebuildDirtyWidgetCallback? _prevRebuildCallback;

  @override
  String get id => 'widget_collector';

  @override
  Future<void> onStart() async {
    // Count widget rebuilds *silently* via Flutter's rebuild hook. We
    // deliberately do NOT enable debugPrintRebuildDirtyWidgets: it prints every
    // rebuild to stdout (thousands of lines/min) and drowns the live console
    // that get_logs surfaces. This callback feeds store.widgetRebuildCounts
    // (used by analyze_rebuilds) with zero console output, and chains any
    // previously-installed hook.
    if (kDebugMode) {
      _prevRebuildCallback = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        _prevRebuildCallback?.call(element, builtOnce);
        store.incrementRebuild(element.widget.runtimeType.toString());
      };
    }
    _snapshotTimer = Timer.periodic(const Duration(seconds: 3), (_) => _capture());
  }

  @override
  Future<void> onStop() async {
    _snapshotTimer?.cancel();
    if (kDebugMode) debugOnRebuildDirtyWidget = _prevRebuildCallback;
  }

  void _capture() {
    try {
      final counter = _Counter();
      final root = _buildNode(
        WidgetsBinding.instance.rootElement,
        depth: 0,
        maxDepth: config.widgetSnapshotMaxDepth,
        maxNodes: config.widgetSnapshotMaxNodes,
        count: counter,
      );
      store.updateWidgetTree(WidgetTreeSnapshot(
        capturedAt: DateTime.now(),
        root: root,
        totalNodes: root?.totalNodes ?? 0,
        maxDepth: root?.maxDepth ?? 0,
      ));
    } catch (_) {}
  }

  WidgetNode? _buildNode(
    Element? element, {
    required int depth,
    required int maxDepth,
    required int maxNodes,
    required _Counter count,
  }) {
    if (element == null || depth > maxDepth || count.value >= maxNodes) return null;
    count.value++;
    final type = element.widget.runtimeType.toString();
    Rect? rect;
    if (element is RenderObjectElement) {
      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize) {
        final offset = ro.localToGlobal(Offset.zero);
        rect = Rect.fromLTWH(offset.dx, offset.dy, ro.size.width, ro.size.height);
      }
    }
    final children = <WidgetNode>[];
    element.visitChildren((child) {
      final node = _buildNode(child,
          depth: depth + 1,
          maxDepth: maxDepth,
          maxNodes: maxNodes,
          count: count);
      if (node != null) children.add(node);
    });
    return WidgetNode(
      id: '${type}_$depth',
      type: type,
      depth: depth,
      key: element.widget.key?.toString(),
      bounds: rect == null
          ? null
          : WidgetBounds(
              x: rect.left, y: rect.top, width: rect.width, height: rect.height),
      children: children,
      rebuildCount: store.widgetRebuildCounts[type] ?? 0,
    );
  }
}

class _Counter {
  int value = 0;
}
